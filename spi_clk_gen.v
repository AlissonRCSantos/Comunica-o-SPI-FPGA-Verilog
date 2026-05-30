module spi_clk_gen #(
    // Parâmetros configuráveis na instanciação do módulo
    parameter CLK_SYS_FREQ = 50_000_000, // Frequência do clock do sistema (Ex: 50 MHz)
    parameter SPI_CLK_FREQ = 1_000_000   // Frequência desejada para o SPI (Ex: 1 MHz)
)(
    input  wire clk_sys,      // Clock principal do sistema
    input  wire rst_n,        // Reset assíncrono (ativo em baixo)
    input  wire en_sclk,      // Habilita a geração do clock (Vem da FSM)
    input  wire cpol,         // Polaridade do Clock (0 ou 1)
    
    output reg  sclk_out,     // Pino físico do SCLK
    output wire edge_tick     // Pulso de 1 ciclo indicando transição de borda
);

    // --- Cálculo Interno dos Parâmetros ---
    // O contador precisa contar metade do período para alternar o sinal (toggle).
    localparam integer MAX_COUNT = (CLK_SYS_FREQ / SPI_CLK_FREQ) / 2;
    
    // Calcula automaticamente o número de bits necessários para o contador
    localparam integer COUNT_WIDTH = $clog2(MAX_COUNT);

    // Registrador do contador
    reg [COUNT_WIDTH-1:0] counter;

    // --- Geração do Edge Tick ---
    // O tick é emitido no mesmo ciclo em que sclk_out é registrado com o novo valor.
    // A FSM e o Datapath reagem a edge_tick no mesmo posedge clk_sys em que a borda ocorre.
    assign edge_tick = (en_sclk && (counter == MAX_COUNT - 1));

    // --- Lógica Sequencial do Gerador ---
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            counter  <= 0;
            sclk_out <= cpol; // No reset, o SCLK assume o estado ocioso definido por CPOL
        end else begin
            if (!en_sclk) begin
                // Se o módulo SPI está ocioso (FSM não ativou), zera contador e respeita CPOL
                counter  <= 0;
                sclk_out <= cpol;
            end else begin
                // Se a FSM mandou gerar o clock
                if (counter == MAX_COUNT - 1) begin
                    counter  <= 0;
                    sclk_out <= ~sclk_out; // Inverte o pino SCLK (Toggle)
                end else begin
                    counter  <= counter + 1;
                end
            end
        end
    end

endmodule