module spi_master #(
    // Parâmetros repassados para o gerador de clock
    parameter CLK_SYS_FREQ = 50_000_000, // 50 MHz default
    parameter SPI_CLK_FREQ = 1_000_000   // 1 MHz default
)(
    // ==========================================
    // Interface do Sistema (Processador / FPGA)
    // ==========================================
    input  wire       clk_sys,     // Clock principal do sistema
    input  wire       rst_n,       // Reset assíncrono (ativo baixo)
    input  wire [7:0] tx_data,     // Byte a ser enviado
    input  wire       start_tx,    // Pulso para iniciar transmissão
    
    // Configurações Estáticas (Modos)
    input  wire       cpol,        // Clock Polarity
    input  wire       cpha,        // Clock Phase
    input  wire       dord,        // Data Order (0=MSB, 1=LSB)
    
    // Status e Dados Recebidos
    output wire [7:0] rx_data,     // Byte lido do escravo
    output wire       done_flag,   // Pulso de 1 ciclo indicando fim
    
    // ==========================================
    // Interface Física (Pinos do Barramento SPI)
    // ==========================================
    output wire       sclk_out,    // Relógio SPI
    output wire       cs_n,        // Chip Select (Ativo baixo)
    output wire       mosi_out,    // Master Out Slave In
    input  wire       miso_in      // Master In Slave Out
);

    // --------------------------------------------------------
    // Fios Internos (Interconexão entre os Módulos)
    // --------------------------------------------------------
    wire edge_tick;  // Liga Módulo 1 -> Módulo 2
    wire en_sclk;    // Liga Módulo 2 -> Módulo 1
    wire load_en;    // Liga Módulo 2 -> Módulo 3
    wire shift_en;   // Liga Módulo 2 -> Módulo 3
    wire sample_en;  // Liga Módulo 2 -> Módulo 3

    // --------------------------------------------------------
    // INSTÂNCIA 1: Gerador de Clock
    // --------------------------------------------------------
    spi_clk_gen #(
        .CLK_SYS_FREQ(CLK_SYS_FREQ),
        .SPI_CLK_FREQ(SPI_CLK_FREQ)
    ) mod_clk_gen (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .en_sclk(en_sclk),     // Input da FSM
        .cpol(cpol),           // Input do Sistema
        .sclk_out(sclk_out),   // Output Físico
        .edge_tick(edge_tick)  // Output para FSM
    );

    // --------------------------------------------------------
    // INSTÂNCIA 2: Máquina de Estados Finita (Cérebro)
    // --------------------------------------------------------
    spi_controller mod_fsm (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .start_tx(start_tx),   // Input do Sistema
        .cpha(cpha),           // Input do Sistema
        .done_flag(done_flag), // Output para o Sistema
        .edge_tick(edge_tick), // Input do Gerador
        .en_sclk(en_sclk),     // Output para Gerador
        .cs_n(cs_n),           // Output Físico
        .load_en(load_en),     // Output para Datapath
        .shift_en(shift_en),   // Output para Datapath
        .sample_en(sample_en)  // Output para Datapath
    );

    // --------------------------------------------------------
    // INSTÂNCIA 3: Registrador de Deslocamento (Datapath)
    // --------------------------------------------------------
    spi_datapath mod_datapath (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .tx_data(tx_data),     // Input do Sistema
        .load_en(load_en),     // Input da FSM
        .shift_en(shift_en),   // Input da FSM
        .sample_en(sample_en), // Input da FSM
        .dord(dord),           // Input do Sistema
        .miso_in(miso_in),     // Input Físico
        .mosi_out(mosi_out),   // Output Físico
        .rx_data(rx_data)      // Output para o Sistema
    );

endmodule