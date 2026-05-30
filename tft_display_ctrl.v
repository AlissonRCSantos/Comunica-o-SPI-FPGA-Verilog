// xrun -clean tb_tft_display_ctrl.v tft_display_ctrl.v spi_master.v spi_controller.v spi_datapath.v spi_clk_gen.v +access+rwc -gui
module tft_display_ctrl #(
    parameter CLK_SYS_FREQ      = 50_000_000,
    parameter SPI_CLK_FREQ      = 10_000_000,
    parameter FILL_COLOR        = 16'hF800,     // Vermelho em RGB565
    parameter TOTAL_PIXELS      = 240 * 320,    // Tela completa 240x320
    parameter WAIT_LONG_CYCLES  = 7_500_000,    // 150ms @ 50MHz (apos SW Reset)
    parameter WAIT_MED_CYCLES   = 6_000_000,    // 120ms @ 50MHz (apos Sleep Out / Display On)
    parameter WAIT_SHORT_CYCLES = 250_000       // 5ms  @ 50MHz (RST hardware)
)(
    input  wire clk_sys,
    input  wire rst_n,
    output reg  done,

    // Pinos fisicos do display TFT ILI9341
    output wire tft_sclk,
    output wire tft_cs_n,
    output reg  tft_dc,      // 0 = Comando, 1 = Dado
    output wire tft_mosi,
    output reg  tft_rst_n,   // Reset ativo-baixo do display
    input  wire tft_miso     // Nao utilizado (display write-only)
);

    // =========================================================
    // Interface com o SPI Master
    // =========================================================
    reg  [7:0] tx_data;
    reg        start_tx;
    wire [7:0] rx_data;
    wire       done_flag;

    spi_master #(
        .CLK_SYS_FREQ(CLK_SYS_FREQ),
        .SPI_CLK_FREQ(SPI_CLK_FREQ)
    ) u_spi (
        .clk_sys  (clk_sys),
        .rst_n    (rst_n),
        .tx_data  (tx_data),
        .start_tx (start_tx),
        .cpol     (1'b0),       // ILI9341: Modo 0 (CPOL=0, CPHA=0)
        .cpha     (1'b0),
        .dord     (1'b0),       // MSB primeiro
        .rx_data  (rx_data),
        .done_flag(done_flag),
        .sclk_out (tft_sclk),
        .cs_n     (tft_cs_n),
        .mosi_out (tft_mosi),
        .miso_in  (tft_miso)
    );

    // =========================================================
    // ROM da Sequencia de Inicializacao ILI9341
    //
    // Formato de cada entrada [10:0]:
    //   [10:9] wait_type: 00=nenhuma, 01=curta(5ms), 10=media(120ms), 11=longa(150ms)
    //   [8]    is_data:   0=comando (DC=0),  1=dado (DC=1)
    //   [7:0]  byte a enviar
    // =========================================================
    localparam INIT_LEN = 18;

    reg [4:0]  seq_ptr;
    reg [10:0] seq_entry;

    always @(*) begin
        case (seq_ptr)
            // Software Reset — espera 150ms para o display reiniciar
            5'd0:  seq_entry = {2'b11, 1'b0, 8'h01};
            // Sleep Out — espera 120ms para o oscilador estabilizar
            5'd1:  seq_entry = {2'b10, 1'b0, 8'h11};
            // Pixel Format Set: 0x55 = 16 bits por pixel (RGB565)
            5'd2:  seq_entry = {2'b00, 1'b0, 8'h3A};
            5'd3:  seq_entry = {2'b00, 1'b1, 8'h55};
            // Memory Access Control: 0x48 = orientacao padrao portrait
            5'd4:  seq_entry = {2'b00, 1'b0, 8'h36};
            5'd5:  seq_entry = {2'b00, 1'b1, 8'h48};
            // Column Address Set: coluna 0 ate 239 (0x00EF)
            5'd6:  seq_entry = {2'b00, 1'b0, 8'h2A};
            5'd7:  seq_entry = {2'b00, 1'b1, 8'h00};
            5'd8:  seq_entry = {2'b00, 1'b1, 8'h00};
            5'd9:  seq_entry = {2'b00, 1'b1, 8'h00};
            5'd10: seq_entry = {2'b00, 1'b1, 8'hEF};
            // Row Address Set: linha 0 ate 319 (0x013F)
            5'd11: seq_entry = {2'b00, 1'b0, 8'h2B};
            5'd12: seq_entry = {2'b00, 1'b1, 8'h00};
            5'd13: seq_entry = {2'b00, 1'b1, 8'h00};
            5'd14: seq_entry = {2'b00, 1'b1, 8'h01};
            5'd15: seq_entry = {2'b00, 1'b1, 8'h3F};
            // Display On — espera 120ms
            5'd16: seq_entry = {2'b10, 1'b0, 8'h29};
            // Memory Write — proximo dado sao os pixels
            5'd17: seq_entry = {2'b00, 1'b0, 8'h2C};
            default: seq_entry = 11'd0;
        endcase
    end

    // =========================================================
    // FSM Principal
    // =========================================================
    localparam [3:0]
        S_RST_LOW    = 4'd0,
        S_RST_WAIT   = 4'd1,
        S_LOAD       = 4'd2,
        S_SEND       = 4'd3,
        S_WAIT_SPI   = 4'd4,
        S_TIMER      = 4'd5,
        S_NEXT       = 4'd6,
        S_PIXEL_HI   = 4'd7,
        S_WAIT_PX_HI = 4'd8,
        S_PIXEL_LO   = 4'd9,
        S_WAIT_PX_LO = 4'd10,
        S_DONE       = 4'd11;

    reg [3:0]  state;
    reg [24:0] timer;
    reg [17:0] pixel_cnt;
    reg [1:0]  wait_type_reg;

    function [24:0] get_wait_cycles;
        input [1:0] wt;
        case (wt)
            2'd1:    get_wait_cycles = WAIT_SHORT_CYCLES - 1;
            2'd2:    get_wait_cycles = WAIT_MED_CYCLES   - 1;
            2'd3:    get_wait_cycles = WAIT_LONG_CYCLES  - 1;
            default: get_wait_cycles = 25'd0;
        endcase
    endfunction

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_RST_LOW;
            tft_rst_n     <= 1'b0;
            tft_dc        <= 1'b0;
            start_tx      <= 1'b0;
            tx_data       <= 8'h00;
            seq_ptr       <= 5'd0;
            timer         <= WAIT_SHORT_CYCLES - 1;
            pixel_cnt     <= 18'd0;
            wait_type_reg <= 2'd0;
            done          <= 1'b0;
        end else begin
            start_tx <= 1'b0; // pulso de 1 ciclo: limpa por padrao

            case (state)

                // --- Reset de hardware do display ---
                S_RST_LOW: begin
                    tft_rst_n <= 1'b0;
                    if (timer == 25'd0) begin
                        tft_rst_n <= 1'b1;
                        timer     <= WAIT_MED_CYCLES - 1;
                        state     <= S_RST_WAIT;
                    end else
                        timer <= timer - 25'd1;
                end

                S_RST_WAIT: begin
                    if (timer == 25'd0) state <= S_LOAD;
                    else                timer <= timer - 25'd1;
                end

                // --- Sequenciador de inicializacao ---
                S_LOAD: begin
                    tft_dc        <= seq_entry[8];
                    tx_data       <= seq_entry[7:0];
                    wait_type_reg <= seq_entry[10:9];
                    state         <= S_SEND;
                end

                S_SEND: begin
                    start_tx <= 1'b1;
                    state    <= S_WAIT_SPI;
                end

                S_WAIT_SPI: begin
                    if (done_flag) begin
                        if (wait_type_reg != 2'd0) begin
                            timer <= get_wait_cycles(wait_type_reg);
                            state <= S_TIMER;
                        end else
                            state <= S_NEXT;
                    end
                end

                S_TIMER: begin
                    if (timer == 25'd0) state <= S_NEXT;
                    else                timer <= timer - 25'd1;
                end

                S_NEXT: begin
                    if (seq_ptr == INIT_LEN - 1) begin
                        // Inicializacao concluida: muda para modo dado e começa pixels
                        pixel_cnt <= 18'd0;
                        tft_dc    <= 1'b1;
                        state     <= S_PIXEL_HI;
                    end else begin
                        seq_ptr <= seq_ptr + 5'd1;
                        state   <= S_LOAD;
                    end
                end

                // --- Preenchimento da tela pixel a pixel ---
                S_PIXEL_HI: begin
                    tx_data  <= FILL_COLOR[15:8];
                    start_tx <= 1'b1;
                    state    <= S_WAIT_PX_HI;
                end

                S_WAIT_PX_HI: begin
                    if (done_flag) state <= S_PIXEL_LO;
                end

                S_PIXEL_LO: begin
                    tx_data  <= FILL_COLOR[7:0];
                    start_tx <= 1'b1;
                    state    <= S_WAIT_PX_LO;
                end

                S_WAIT_PX_LO: begin
                    if (done_flag) begin
                        if (pixel_cnt == TOTAL_PIXELS - 1)
                            state <= S_DONE;
                        else begin
                            pixel_cnt <= pixel_cnt + 18'd1;
                            state     <= S_PIXEL_HI;
                        end
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                end

                default: state <= S_RST_LOW;
            endcase
        end
    end

endmodule
