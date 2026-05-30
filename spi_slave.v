

module spi_slave (
    // ==========================================
    // Interface do Sistema Local (Processador / FPGA)
    // ==========================================
    input  wire       clk_sys,       // Clock rápido do sistema local
    input  wire       rst_n,         // Reset assíncrono (ativo em baixo)
    
    input  wire [7:0] tx_data,       // Byte que o sistema quer que o Escravo envie
    output wire [7:0] rx_data,       // Byte recebido do Mestre
    output wire       rx_done_flag,  // Pulso indicando que um byte completo chegou
    
    // Configurações Estáticas
    input  wire       cpol,          // Clock Polarity
    input  wire       cpha,          // Clock Phase
    input  wire       dord,          // Data Order (0=MSB, 1=LSB)

    // ==========================================
    // Interface Física (Pinos do Barramento SPI)
    // ==========================================
    input  wire       sclk_in,       // Relógio vindo do Mestre
    input  wire       cs_n_in,       // Chip Select vindo do Mestre
    input  wire       mosi_in,       // Master Out Slave In
    output wire       miso_out       // Master In Slave Out (Tri-State)
);

    // --------------------------------------------------------
    // Fios Internos (Interconexão entre os Módulos)
    // --------------------------------------------------------
    // Saídas do Sincronizador (Módulo 1)
    wire cs_n_sync;
    wire mosi_sync;
    wire sclk_rise;
    wire sclk_fall;

    // Saídas da FSM (Módulo 2)
    wire shift_en;
    wire sample_en;
    wire miso_en;

    // Saídas do Datapath (Módulo 3)
    wire miso_internal;

    // --------------------------------------------------------
    // Lógica Cola (Glue Logic) para Geração do Load Enable
    // --------------------------------------------------------
    // Precisamos de um pulso de 1 ciclo no exato momento em que o CS sincronizado cai.
    // Usamos um registrador simples para detectar a borda de descida do cs_n_sync.
    reg cs_n_sync_d;
    wire load_en;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            cs_n_sync_d <= 1'b1; // Repouso em alto
        end else begin
            cs_n_sync_d <= cs_n_sync;
        end
    end

    // O pulso ocorre quando o estado atual é 0 e o estado passado era 1
    assign load_en = (~cs_n_sync) & cs_n_sync_d;

    // --------------------------------------------------------
    // INSTÂNCIA 1: Sincronizador Front-end (CDC)
    // --------------------------------------------------------
    spi_slave_sync mod_sync (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .sclk_in(sclk_in),
        .cs_n_in(cs_n_in),
        .mosi_in(mosi_in),
        .cs_n_sync(cs_n_sync),
        .mosi_sync(mosi_sync),
        .sclk_rise(sclk_rise),
        .sclk_fall(sclk_fall)
    );

    // --------------------------------------------------------
    // INSTÂNCIA 2: Máquina de Estados Finita (Controller)
    // --------------------------------------------------------
    spi_slave_controller mod_fsm (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .cs_n_sync(cs_n_sync),
        .sclk_rise(sclk_rise),
        .sclk_fall(sclk_fall),
        .cpol(cpol),
        .cpha(cpha),
        .shift_en(shift_en),
        .sample_en(sample_en),
        .miso_en(miso_en),
        .rx_done_flag(rx_done_flag)
    );

    // --------------------------------------------------------
    // INSTÂNCIA 3: Registrador de Deslocamento (Datapath)
    // --------------------------------------------------------
    spi_slave_datapath mod_datapath (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .dord(dord),
        .rx_data(rx_data),
        .load_en(load_en),      // Impulsionado pela Lógica Cola local
        .shift_en(shift_en),
        .sample_en(sample_en),
        .mosi_sync(mosi_sync),
        .miso_internal(miso_internal)
    );

    // --------------------------------------------------------
    // DRIVER FÍSICO DO MISO (Buffer Tri-State)
    // --------------------------------------------------------
    // Se a FSM diz que temos o barramento (miso_en == 1), empurramos o bit interno.
    // Se não (miso_en == 0), desconectamos eletricamente o pino deixando-o em Alta Impedância (Z).
    assign miso_out = (miso_en) ? miso_internal : 1'bz;

endmodule