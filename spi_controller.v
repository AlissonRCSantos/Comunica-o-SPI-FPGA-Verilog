module spi_controller (
    input  wire clk_sys,      // Clock principal do sistema
    input  wire rst_n,        // Reset assíncrono (ativo em baixo)
    
    // Interface com o Sistema Superior
    input  wire start_tx,     // Gatilho para iniciar a transmissão
    input  wire cpha,         // Configuração da Fase do Clock (0 ou 1)
    output reg  done_flag,    // Pulso indicando fim da operação
    
    // Interface com o Gerador de Clock (Módulo 1)
    input  wire edge_tick,    // Pulso avisando que uma borda de SCLK ocorreu
    output reg  en_sclk,      // Liga/desliga o gerador de clock
    
    // Interface com o Datapath (Módulo 3) e Pinos Físicos
    output reg  cs_n,         // Chip Select físico (Ativo em baixo)
    output reg  load_en,      // Comando para carregar o tx_data paralelo
    output reg  shift_en,     // Comando para deslocar o dado (MOSI)
    output reg  sample_en     // Comando para amostrar o dado (MISO)
);

    // --- Definição dos Estados (Encapsulamento com localparam) ---
    localparam [1:0] IDLE     = 2'b00;
    localparam [1:0] START    = 2'b01;
    localparam [1:0] TRANSFER = 2'b10;
    localparam [1:0] END      = 2'b11;

    // Registradores de Estado
    reg [1:0] current_state, next_state;
    
    // Contador de Bordas (0 a 15, logo 4 bits)
    reg [3:0] edge_cnt;

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
    // BLOCO EXTRA: Gerenciamento do Contador de Bordas (Sequencial)
    // =======================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            edge_cnt <= 4'd0;
        end else begin
            if (current_state != TRANSFER) begin
                edge_cnt <= 4'd0; // Zera o contador fora do estado de transferência
            end else if (edge_tick) begin
                edge_cnt <= edge_cnt + 1'b1; // Incrementa apenas quando o clock físico bate
            end
        end
    end

    // =======================================================================
    // BLOCO 2: Lógica de Próximo Estado (Combinacional)
    // =======================================================================
    always @(*) begin
        // Valor padrão para evitar latches
        next_state = current_state; 

        case (current_state)
            IDLE: begin
                if (start_tx)
                    next_state = START;
            end
            
            START: begin
                // Fica apenas 1 ciclo de clock aqui para setup inicial e avança
                next_state = TRANSFER;
            end
            
            TRANSFER: begin
                // Sai de TRANSFER no exato momento em que a 16ª borda (índice 15) é processada
                if (edge_tick && (edge_cnt == 4'd15))
                    next_state = END;
            end
            
            END: begin
                // Se o sistema superior já estiver pedindo uma nova transmissão (Back-to-Back),
                // pula o IDLE e vai direto para a preparação do novo byte.
                if (start_tx)
                    next_state = START;
                else
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end

    // =======================================================================
    // BLOCO 3: Lógica de Saída (Combinacional)
    // =======================================================================
    always @(*) begin
        // Atribuições padrão: Garante que NENHUM latch combinacional seja criado
        // e limpa todos os pulsos no final do ciclo do clk_sys.
        cs_n      = 1'b1; 
        en_sclk   = 1'b0;
        load_en   = 1'b0;
        shift_en  = 1'b0;
        sample_en = 1'b0;
        done_flag = 1'b0;

        case (current_state)
            IDLE: begin
                cs_n = 1'b1; // Mantém o barramento liberado
            end
            
            START: begin
                cs_n    = 1'b0; // Trava o escravo alvo
                en_sclk = 1'b1; // Permite que o clock generator comece a trabalhar
                load_en = 1'b1; // Diz ao Datapath para ingerir o tx_data do sistema
            end
            
            TRANSFER: begin
                cs_n    = 1'b0;
                en_sclk = 1'b1;
                
                // Lógica para tratar CPHA:
                // CPHA=0: Amostra nas bordas pares (0,2,4...) e Desloca nas ímpares (1,3...)
                // CPHA=1: Borda 0 é inativa (dado já está no MOSI via load_en em START).
                //         A partir da borda 1: Amostra nas ímpares (1,3...) e Desloca nas pares (2,4...)
                if (edge_tick) begin
                    if (cpha && (edge_cnt == 4'd0)) begin
                        // Borda de setup do CPHA=1: bit 7 já está no MOSI, não desloca
                    end else if (edge_cnt[0] == cpha) begin
                        sample_en = 1'b1;
                    end else begin
                        shift_en = 1'b1;
                    end
                end
            end
            
            END: begin
                cs_n      = 1'b1; // Libera o barramento
                done_flag = 1'b1; // Avisa ao processador que terminou
                // en_sclk cai para 0 automaticamente via atribuição padrão, freando o clock.
            end
        endcase
    end

endmodule