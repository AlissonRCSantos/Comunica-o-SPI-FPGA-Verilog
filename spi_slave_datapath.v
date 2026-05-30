
module spi_slave_datapath (
    input  wire       clk_sys,       // Clock principal do sistema local
    input  wire       rst_n,         // Reset assíncrono
    
    // Interface com o Sistema Superior
    input  wire [7:0] tx_data,       // Byte que o Escravo deseja enviar ao Mestre
    input  wire       dord,          // Ordem dos dados (0 = MSB-First, 1 = LSB-First)
    output wire [7:0] rx_data,       // Byte completo recebido do Mestre
    
    // Sinais de Controle (Vindos da FSM do Escravo)
    input  wire       load_en,       // Pulso para carregar tx_data no início da transação
    input  wire       shift_en,      // Pulso para deslocar o registrador de TX
    input  wire       sample_en,     // Pulso para amostrar o registrador de RX
    
    // Sinais de Dados (Vindos do Módulo 1 Sincronizador)
    input  wire       mosi_sync,     // Dado de entrada limpo e sincronizado
    
    // Saída de Dados Interna (Vai para o Buffer Tri-State no Top-Level)
    output wire       miso_internal  
);

    // --- Registradores de Deslocamento ---
    reg [7:0] tx_shift_reg;
    reg [7:0] rx_shift_reg;

    // --- Lógica Combinacional de Saída ---
    // O miso_internal reflete instantaneamente a "ponta" do registrador de TX.
    // O controle de ligar/desligar esse sinal fisicamente ficará no Top-Level.
    assign miso_internal = (dord == 1'b0) ? tx_shift_reg[7] : tx_shift_reg[0];
    
    // O byte recebido é espelhado direto para a saída do sistema
    assign rx_data = rx_shift_reg;

    // =======================================================================
    // LÓGICA DE TRANSMISSÃO (MISO)
    // =======================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift_reg <= 8'h00;
        end else begin
            if (load_en) begin
                // A FSM aciona load_en assim que detecta o CS_N caindo
                tx_shift_reg <= tx_data;
            end 
            else if (shift_en) begin
                // A FSM aciona shift_en baseada nas bordas de SCLK detectadas
                if (dord == 1'b0) begin
                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0}; // MSB-First
                end else begin
                    tx_shift_reg <= {1'b0, tx_shift_reg[7:1]}; // LSB-First
                end
            end
        end
    end

    // =======================================================================
    // LÓGICA DE RECEPÇÃO (MOSI)
    // =======================================================================
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift_reg <= 8'h00;
        end else begin
            if (sample_en) begin
                // A FSM aciona sample_en para ler o mosi_sync
                if (dord == 1'b0) begin
                    rx_shift_reg <= {rx_shift_reg[6:0], mosi_sync}; // MSB-First
                end else begin
                    rx_shift_reg <= {mosi_sync, rx_shift_reg[7:1]}; // LSB-First
                end
            end
        end
    end

endmodule