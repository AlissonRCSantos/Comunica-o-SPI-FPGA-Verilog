// xrun -clean tb_tft_display_ctrl.v tft_display_ctrl.v spi_master.v spi_controller.v spi_datapath.v spi_clk_gen.v +access+rwc -gui
module tb_tft_display_ctrl;

    // --- Parametros de simulacao (valores reduzidos para velocidade) ---
    localparam CLK_PERIOD  = 20;         // 50 MHz
    localparam SIM_PIXELS  = 4;          // 4 pixels = 8 bytes de cor
    localparam SIM_WAIT_L  = 50;         // substitui 150ms
    localparam SIM_WAIT_M  = 40;         // substitui 120ms
    localparam SIM_WAIT_S  = 20;         // substitui 5ms

    // --- Sinais ---
    reg  clk_sys;
    reg  rst_n;
    wire done;
    wire tft_sclk;
    wire tft_cs_n;
    wire tft_dc;
    wire tft_mosi;
    wire tft_rst_n;
    reg  tft_miso;

    // --- Instancia do DUT ---
    tft_display_ctrl #(
        .CLK_SYS_FREQ     (50_000_000),
        .SPI_CLK_FREQ     (1_000_000),   // 1 MHz para facilitar visualizacao
        .FILL_COLOR       (16'hF800),    // Vermelho
        .TOTAL_PIXELS     (SIM_PIXELS),
        .WAIT_LONG_CYCLES (SIM_WAIT_L),
        .WAIT_MED_CYCLES  (SIM_WAIT_M),
        .WAIT_SHORT_CYCLES(SIM_WAIT_S)
    ) dut (
        .clk_sys  (clk_sys),
        .rst_n    (rst_n),
        .done     (done),
        .tft_sclk (tft_sclk),
        .tft_cs_n (tft_cs_n),
        .tft_dc   (tft_dc),
        .tft_mosi (tft_mosi),
        .tft_rst_n(tft_rst_n),
        .tft_miso (tft_miso)
    );

    // --- Clock ---
    initial clk_sys = 0;
    always #(CLK_PERIOD / 2) clk_sys = ~clk_sys;

    // --- MISO fixo em 0 (display write-only) ---
    initial tft_miso = 0;

    // =========================================================
    // Estimulos principais
    // =========================================================
    initial begin
        $dumpfile("ondas_tft.vcd");
        $dumpvars(0, tb_tft_display_ctrl);

        rst_n = 0;
        repeat(5) @(posedge clk_sys);
        rst_n = 1;

        $display("==================================================");
        $display(" SIMULACAO: Controlador TFT ILI9341 (SPI 2.4\")");
        $display(" Cor de preenchimento: Vermelho (0xF800 RGB565)");
        $display(" Pixels a enviar: %0d (simulacao reduzida)", SIM_PIXELS);
        $display("==================================================");

        wait (done == 1'b1);

        $display("--------------------------------------------------");
        $display("[OK] Sinalizacao done=1: display inicializado.");
        $display("--------------------------------------------------");

        repeat(10) @(posedge clk_sys);
        $finish;
    end

    // =========================================================
    // Monitor comportamental do ILI9341
    // Captura cada byte no barramento SPI e decodifica
    // =========================================================
    integer mon_bits;
    reg [7:0] mon_shift;

    initial mon_bits = 0;

    // Amostra MOSI na borda de subida do SCLK (Modo 0, CPOL=0)
    always @(posedge tft_sclk) begin
        if (!tft_cs_n) begin
            mon_shift = {mon_shift[6:0], tft_mosi};
            mon_bits  = mon_bits + 1;
            if (mon_bits == 8) begin
                mon_bits = 0;
                if (tft_dc == 1'b0) begin
                    $write("[ILI9341] CMD 0x%02X", mon_shift);
                    case (mon_shift)
                        8'h01: $write("  (SW_RESET)");
                        8'h11: $write("  (SLEEP_OUT)");
                        8'h29: $write("  (DISPLAY_ON)");
                        8'h2A: $write("  (COL_ADDR_SET)");
                        8'h2B: $write("  (ROW_ADDR_SET)");
                        8'h2C: $write("  (MEM_WRITE — inicio dos pixels)");
                        8'h36: $write("  (MEM_ACCESS_CTRL)");
                        8'h3A: $write("  (PIX_FORMAT_SET)");
                        default: $write("  (?)");
                    endcase
                    $display("");
                end else begin
                    $display("[ILI9341] DAT 0x%02X", mon_shift);
                end
            end
        end
    end

    // --- Monitora o pino RST ---
    always @(negedge tft_rst_n)
        $display("[RST] Display em reset (tft_rst_n=0)");
    always @(posedge tft_rst_n)
        $display("[RST] Reset liberado — display inicializando");

    // =========================================================
    // Verificador automatico da sequencia de inicializacao
    // Confirma que os 18 primeiros bytes enviados sao os corretos
    // =========================================================
    integer seq_check;
    reg [7:0] expected_bytes [0:17];
    reg       expected_is_cmd [0:17];

    initial begin
        // Comandos e dados esperados (em ordem)
        expected_bytes[0]  = 8'h01; expected_is_cmd[0]  = 1; // SW Reset
        expected_bytes[1]  = 8'h11; expected_is_cmd[1]  = 1; // Sleep Out
        expected_bytes[2]  = 8'h3A; expected_is_cmd[2]  = 1; // Pix Format
        expected_bytes[3]  = 8'h55; expected_is_cmd[3]  = 0; // 16-bit
        expected_bytes[4]  = 8'h36; expected_is_cmd[4]  = 1; // Mem Access
        expected_bytes[5]  = 8'h48; expected_is_cmd[5]  = 0;
        expected_bytes[6]  = 8'h2A; expected_is_cmd[6]  = 1; // Col Addr
        expected_bytes[7]  = 8'h00; expected_is_cmd[7]  = 0;
        expected_bytes[8]  = 8'h00; expected_is_cmd[8]  = 0;
        expected_bytes[9]  = 8'h00; expected_is_cmd[9]  = 0;
        expected_bytes[10] = 8'hEF; expected_is_cmd[10] = 0;
        expected_bytes[11] = 8'h2B; expected_is_cmd[11] = 1; // Row Addr
        expected_bytes[12] = 8'h00; expected_is_cmd[12] = 0;
        expected_bytes[13] = 8'h00; expected_is_cmd[13] = 0;
        expected_bytes[14] = 8'h01; expected_is_cmd[14] = 0;
        expected_bytes[15] = 8'h3F; expected_is_cmd[15] = 0;
        expected_bytes[16] = 8'h29; expected_is_cmd[16] = 1; // Display On
        expected_bytes[17] = 8'h2C; expected_is_cmd[17] = 1; // Mem Write
        seq_check = 0;
    end

    integer chk_bits;
    reg [7:0] chk_shift;
    initial chk_bits = 0;

    always @(posedge tft_sclk) begin
        if (!tft_cs_n && seq_check < 18) begin
            chk_shift = {chk_shift[6:0], tft_mosi};
            chk_bits  = chk_bits + 1;
            if (chk_bits == 8) begin
                chk_bits = 0;
                if (chk_shift === expected_bytes[seq_check] &&
                    (tft_dc === !expected_is_cmd[seq_check])) begin
                    $display("  [CHECK %02d] OK", seq_check);
                end else begin
                    $display("  [CHECK %02d] FALHA — esperado: 0x%02X (dc=%b), recebido: 0x%02X (dc=%b)",
                             seq_check,
                             expected_bytes[seq_check], !expected_is_cmd[seq_check],
                             chk_shift, tft_dc);
                end
                seq_check = seq_check + 1;
            end
        end
    end

endmodule
