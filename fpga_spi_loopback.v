module fpga_spi_loopback (
    input  wire       clk_50mhz,     // Clock cristal da placa (ex: 50 MHz)
    input  wire       btn_rst_n,     // Botão de reset (recomendo usar um botão ativo em baixo)
    input  wire       btn_start,     // Botão para disparar a transmissão
    input  wire [7:0] sw_data,       // 8 chaves para compor o byte de envio do Master

    output wire [7:0] led_master_rx, // 8 LEDs mostrando o que o Master recebeu do Escravo
    output wire [7:0] led_slave_rx   // 8 LEDs mostrando o que o Escravo recebeu do Master
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
    // Na FPGA, você ficará com o dedo no botão por uns 200 milissegundos.
    // Em 50MHz, isso equivale a 10 milhões de ciclos de clock! A FSM precisa 
    // de um pulso de exato 1 ciclo. Este circuito gera essa "agulha".
    reg [1:0] btn_sync;
    
    always @(posedge clk_50mhz or negedge btn_rst_n) begin
        if (!btn_rst_n) begin
            btn_sync <= 2'b00;
        end else begin
            btn_sync <= {btn_sync[0], btn_start}; // Shift register de 2 bits
        end
    end
    
    // O pulso sobe apenas no ciclo exato em que o estado atual é 1 e o passado era 0
    assign start_tx_pulse = (btn_sync[0] == 1'b1 && btn_sync[1] == 1'b0);

    // ========================================================
    // Lógica 2: Registradores de Retenção para os LEDs
    // ========================================================
    // Os fios de saída dos datapaths podem assumir valores intermediários. 
    // Nós só atualizamos os LEDs quando a flag "done" avisa que o byte está perfeito.
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

    assign led_master_rx = reg_led_master;
    assign led_slave_rx  = reg_led_slave;

    // ========================================================
    // INSTÂNCIA DO MESTRE
    // ========================================================
    spi_master #(
        .CLK_SYS_FREQ(50_000_000),
        .SPI_CLK_FREQ(1_000_000) // Clock SPI de 1 MHz
    ) master_inst (
        .clk_sys(clk_50mhz),
        .rst_n(btn_rst_n),
        .tx_data(sw_data),         // Envia o estado das chaves
        .start_tx(start_tx_pulse), // Acionado pela agulha do botão
        .cpol(1'b0),               // Hardcoded Modo 0
        .cpha(1'b0),
        .dord(1'b0),               // Hardcoded MSB-First
        .rx_data(master_rx_data_bus),
        .done_flag(master_done),
        .sclk_out(spi_sclk),       // Conecta aos fios do barramento
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
        // O Escravo envia de volta o inverso do que as chaves mostram
        .tx_data(~sw_data),        
        .rx_data(slave_rx_data_bus),
        .rx_done_flag(slave_done),
        .cpol(1'b0),
        .cpha(1'b0),
        .dord(1'b0),
        .sclk_in(spi_sclk),        // Recebe dos fios do barramento
        .cs_n_in(spi_cs_n),
        .mosi_in(spi_mosi),
        .miso_out(spi_miso)
    );

endmodule