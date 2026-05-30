module spi_datapath (
    input  wire       clk_sys,    // Clock principal do sistema
    input  wire       rst_n,      // Reset assíncrono (ativo em baixo)
    
    // Interface de Controle (Sinais vindos da FSM e do Sistema)
    input  wire [7:0] tx_data,    // Byte a ser transmitido (Parallel-In)
    input  wire       load_en,    // Pulso para carregar o tx_data no registrador (início da tx)
    input  wire       shift_en,   // Comando da FSM para deslocar o dado de saída
    input  wire       sample_en,  // Comando da FSM para amostrar o dado de entrada
    input  wire       dord,       // 0 = MSB-First, 1 = LSB-First
    
    // Interface Física SPI
    input  wire       miso_in,    // Dado vindo do escravo
    output wire       mosi_out,   // Dado indo para o escravo
    
    // Saída Paralela
    output wire [7:0] rx_data     // Byte recebido do escravo (Parallel-Out)
);

    // --- Registradores Internos ---
    reg [7:0] tx_shift_reg; // Registrador dedicado à transmissão
    reg [7:0] rx_shift_reg; // Registrador dedicado à recepção

    // --- Lógica Combinacional de Saída (MOSI) ---
    // O MOSI sempre reflete o bit da "ponta" do registrador de TX.
    // Se MSB-First (dord=0), a ponta é o bit 7. Se LSB-First, a ponta é o bit 0.
    assign mosi_out = (dord == 1'b0) ? tx_shift_reg[7] : tx_shift_reg[0];
    
    // A saída paralela de recepção é simplesmente o conteúdo do registrador de RX
    assign rx_data = rx_shift_reg;

    // --- Lógica Sequencial: Transmissão (TX) ---
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            tx_shift_reg <= 8'h00;
        end else begin
            if (load_en) begin
                // Carrega o dado paralelo do barramento no momento em que a FSM inicia
                tx_shift_reg <= tx_data;
            end 
            else if (shift_en) begin
                // Momento exato de empurrar o próximo bit para a linha MOSI
                if (dord == 1'b0) begin
                    // MSB-First: Desloca para a esquerda (<<). 
                    // O bit 7 vai embora, o resto sobe, entra 0 no LSB.
                    tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                end else begin
                    // LSB-First: Desloca para a direita (>>). 
                    // O bit 0 vai embora, o resto desce, entra 0 no MSB.
                    tx_shift_reg <= {1'b0, tx_shift_reg[7:1]};
                end
            end
        end
    end

    // --- Lógica Sequencial: Recepção (RX) ---
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            rx_shift_reg <= 8'h00;
        end else begin
            if (sample_en) begin
                // Momento exato de ler o pino MISO e guardar no registrador
                if (dord == 1'b0) begin
                    // MSB-First: O dado entra pela direita (LSB) e empurra o resto pra esquerda
                    rx_shift_reg <= {rx_shift_reg[6:0], miso_in};
                end else begin
                    // LSB-First: O dado entra pela esquerda (MSB) e empurra o resto pra direita
                    rx_shift_reg <= {miso_in, rx_shift_reg[7:1]};
                end
            end
        end
    end

endmodule