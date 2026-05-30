`timescale 1ns / 1ps

module fpga_spi_loopback (
    input  wire       clk_50mhz,     // Clock cristal da placa (ex: 50 MHz)
    input  wire       btn_rst_n,     // Botão de reset (ativo em baixo)
    input  wire       btn_start,     // Botão para disparar a transmissão
    input  wire [7:0] sw_data,       // 8 chaves para compor o byte de envio do Master
    input  wire       sw_sel_led,    // CHAVE NOVA: Seletor do MUX (0 = Master RX, 1 = Slave RX)

    output wire [7:0] led_out        // SAÍDA UNIFICADA: 8 LEDs físicos da placa
);

    // ========================================================
    // Sinais Internos: O "Cabo Físico" Virtual
    // ========================================================
    wire spi_sclk;
    wire spi_cs_n;
    wire spi_mosi;
    wire spi_miso;

    // Sinais de controle e dados
    wire start_tx_pulse;
    wire master_done;
    wire slave_done;
    wire [7:0] master_rx_data_bus;
    wire [7:0] slave_rx_data_bus;

    // ========================================================
    // Lógica 1: Detector de Borda (One-Shot) para o Botão
    // ========================================================
    reg [1:0] btn_sync;
    
    always @(posedge clk_50mhz or negedge btn_rst_n) begin
        if (!btn_rst_n) begin
            btn_sync <= 2'b00;
        end else begin
            btn_sync <= {btn_sync[0], btn_start};
        end
    end
    
    assign start_tx_pulse = (btn_sync[0] == 1'b1 && btn_sync[1] == 1'b0);

    // ========================================================
    // Lógica 2: Registradores de Retenção para os Dados
    // ========================================================
    reg [7:0] reg_led_master;
    reg [7:0] reg_led_slave;

    always @(posedge clk_50mhz or negedge btn_rst_n) begin
        if (!btn_rst_n) begin
            reg_led_master <= 8'h00;
            reg_led_slave  <= 8'h00;
        end else begin
            if (master_done) reg_led_master <= master_rx_data_bus;
            if (slave_done)  reg_led_slave  <= slave_rx_data_bus;
        end
    end

    // ========================================================
    // LÓGICA NOVA: Multiplexador de Saída dos LEDs
    // ========================================================
    // Operador ternário implementa um circuito combinacional MUX puro.
    // Se sw_sel_led for 1, direciona reg_led_slave. Se for 0, direciona reg_led_master.
    assign led_out = (sw_sel_led) ? reg_led_slave : reg_led_master;

    // ========================================================
    // INSTÂNCIA DO MESTRE
    // ========================================================
    spi_master #(
        .CLK_SYS_FREQ(50_000_000),
        .SPI_CLK_FREQ(1_000_000)
    ) master_inst (
        .clk_sys(clk_50mhz),
        .rst_n(btn_rst_n),
        .tx_data(sw_data),
        .start_tx(start_tx_pulse),
        .cpol(1'b0),
        .cpha(1'b0),
        .dord(1'b0),
        .rx_data(master_rx_data_bus),
        .done_flag(master_done),
        .sclk_out(spi_sclk),
        .cs_n(spi_cs_n),
        .mosi_out(spi_mosi),
        .miso_in(spi_miso)
    );

    // ========================================================
    // INSTÂNCIA DO ESCRAVO
    // ========================================================
    spi_slave slave_inst (
        .clk_sys(clk_50mhz),
        .rst_n(btn_rst_n),
        .tx_data(~sw_data), // Envia o inverso do switch para validação assimétrica
        .rx_data(slave_rx_data_bus),
        .rx_done_flag(slave_done),
        .cpol(1'b0),
        .cpha(1'b0),
        .dord(1'b0),
        .sclk_in(spi_sclk),
        .cs_n_in(spi_cs_n),
        .mosi_in(spi_mosi),
        .miso_out(spi_miso)
    );

endmodule