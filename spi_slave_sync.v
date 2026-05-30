module spi_slave_sync (
    input  wire clk_sys,      // Clock rápido do sistema local
    input  wire rst_n,        // Reset assíncrono
    input  wire cpol,         // Polaridade do clock (0 = ocioso baixo, 1 = ocioso alto)

    // Pinos físicos assíncronos vindos do Mestre
    input  wire sclk_in,
    input  wire cs_n_in,
    input  wire mosi_in,

    // Sinais sincronizados e limpos para uso interno do Escravo
    output wire cs_n_sync,
    output wire mosi_sync,

    // Pulsos de gatilho (Duram exatamente 1 ciclo de clk_sys)
    output wire sclk_rise,
    output wire sclk_fall
);

    // Registradores para a cascata de sincronização (Double-Flop)
    // Usamos vetores de 3 bits: 
    // [0] = 1º estágio (amostra bruta, sujeita a erro)
    // [1] = 2º estágio (amostra segura/sincronizada)
    // [2] = 3º estágio (amostra do ciclo passado, usada para achar a borda)
    
    reg [2:0] sclk_reg;
    reg [1:0] cs_n_reg;
    reg [1:0] mosi_reg;

    // --- Atribuições de Saída ---
    // A saída sincronizada é sempre o 2º estágio da cascata
    assign cs_n_sync = cs_n_reg[1];
    assign mosi_sync = mosi_reg[1];

    // --- Lógica de Detecção de Borda (Edge Detector) ---
    // Subida: O ciclo atual [1] é Alto e o ciclo passado [2] era Baixo.
    assign sclk_rise = (sclk_reg[1] == 1'b1) && (sclk_reg[2] == 1'b0);
    
    // Descida: O ciclo atual [1] é Baixo e o ciclo passado [2] era Alto.
    assign sclk_fall = (sclk_reg[1] == 1'b0) && (sclk_reg[2] == 1'b1);

    // --- Processo Sequencial de Amostragem ---
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            // No reset, todos os estágios assumem o estado ocioso do barramento:
            // CS alto, MOSI indefinido (0), SCLK no nível ocioso definido por CPOL.
            sclk_reg <= {3{cpol}};
            cs_n_reg <= 2'b11;
            mosi_reg <= 2'b00;
        end else begin
            // Deslocamento da cascata (Shift Register interno)
            // O sinal físico entra no bit [0], e vai empurrando para a esquerda
            sclk_reg <= {sclk_reg[1:0], sclk_in};
            cs_n_reg <= {cs_n_reg[0],   cs_n_in};
            mosi_reg <= {mosi_reg[0],   mosi_in};
        end
    end

endmodule