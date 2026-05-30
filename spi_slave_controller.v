module spi_slave_controller (
    input  wire clk_sys,      // Clock principal do sistema local
    input  wire rst_n,        // Reset assíncrono (ativo em baixo)
    
    // Interface com o Sincronizador (Módulo 1)
    input  wire cs_n_sync,    // Chip Select sincronizado
    input  wire sclk_rise,    // Pulso de borda de subida do SCLK
    input  wire sclk_fall,    // Pulso de borda de descida do SCLK
    
    // Configurações Estáticas
    input  wire cpol,         // Clock Polarity
    input  wire cpha,         // Clock Phase
    
    // Interface de Controle com o Datapath (Módulo 3) e Top-Level
    output reg  shift_en,     // Comando para deslocar o dado (MISO)
    output reg  sample_en,    // Comando para amostrar o dado (MOSI)
    output reg  miso_en,      // Habilita o buffer Tri-State de saída
    
    // Interface com o Sistema
    output reg  rx_done_flag  // Flag indicando fim da recepção de 1 byte
);

    // --- Definição dos Estados (Encapsulamento com localparam) ---
    localparam [1:0] IDLE     = 2'b00;
    localparam [1:0] TRANSFER = 2'b01;
    localparam [1:0] DONE     = 2'b10;

    // Registradores de Estado
    reg [1:0] current_state, next_state;
    
    // Contador de Transições (Conta de 0 a 15 para formar 8 bits)
    reg [3:0] edge_cnt;

    // --- Abstração das Bordas Lógicas ---
    wire borda_lider = (cpol == 1'b0) ? sclk_rise : sclk_fall;
    wire borda_final = (cpol == 1'b0) ? sclk_fall : sclk_rise;

    // =======================================================================
    // BLOCO 1: Lógica de Atualização do Estado Atual (Sequencial)
    // =======================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    // =======================================================================
    // BLOCO EXTRA: Contador de Bordas do Escravo (Sequencial)
    // =======================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            edge_cnt <= 4'd0;
        end else begin
            // Se o Chip Select foi desativado (Aborto de comunicação ou Ocioso)
            if (cs_n_sync == 1'b1) begin
                edge_cnt <= 4'd0;
            end 
            else if (current_state == TRANSFER) begin
                // Incrementa a cada transição válida de clock (subida ou descida)
                if (sclk_rise || sclk_fall) begin
                    edge_cnt <= edge_cnt + 1'b1;
                end
            end
        end
    end

    // =======================================================================
    // BLOCO 2: Lógica de Próximo Estado (Combinacional)
    // =======================================================================
    always @(*) begin
        next_state = current_state; 

        // Se a qualquer momento o Master abortar a transmissão subindo o CS,
        // força o retorno imediato para IDLE para resetar a máquina.
        if (cs_n_sync == 1'b1) begin
            next_state = IDLE;
        end else begin
            case (current_state)
                IDLE: begin
                    // Como cs_n_sync == 0 já foi verificado acima, 
                    // cai direto para transferência
                    next_state = TRANSFER;
                end
                
                TRANSFER: begin
                    // Ao processar a 16ª borda lógica (índice 15)
                    if ((sclk_rise || sclk_fall) && (edge_cnt == 4'd15)) begin
                        next_state = DONE;
                    end
                end
                
                DONE: begin
                    // Passa 1 ciclo apenas para levantar a flag e volta
                    next_state = IDLE;
                end
                
                default: next_state = IDLE;
            endcase
        end
    end

    // =======================================================================
    // BLOCO 3: Lógica de Saída (Combinacional)
    // =======================================================================
    always @(*) begin
        // Atribuições padrão para evitar latches
        shift_en     = 1'b0;
        sample_en    = 1'b0;
        miso_en      = 1'b0;
        rx_done_flag = 1'b0;

        case (current_state)
            IDLE: begin
                // No IDLE, o miso_en fica 0 (MISO em Alta Impedância)
                miso_en = 1'b0; 
            end
            
            TRANSFER: begin
                // O Escravo "toma posse" da linha MISO
                miso_en = 1'b1;
                
                // Lógica de atuação baseada na Fase do Clock (CPHA)
                if (cpha == 1'b0) begin
                    // CPHA = 0: Amostra na Borda Líder, Desloca na Borda Final
                    if (borda_lider) sample_en = 1'b1;
                    if (borda_final) shift_en  = 1'b1;
                end else begin
                    // CPHA = 1: Desloca na Borda Líder, Amostra na Borda Final
                    if (borda_lider) shift_en  = 1'b1;
                    if (borda_final) sample_en = 1'b1;
                end
            end
            
            DONE: begin
                miso_en      = 1'b1; // Mantém a linha até o Master subir o CS
                rx_done_flag = 1'b1; // Dispara pulso de recebimento para o sistema local
            end
        endcase
    end

endmodule