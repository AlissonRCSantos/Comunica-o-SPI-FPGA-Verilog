// xrun -clean tb_spi_slave_sync.v spi_slave_sync.v +access+rwc -gui
module tb_spi_slave_sync;

    // --- Sinais do Sistema ---
    reg  clk_sys;
    reg  rst_n;

    // --- Sinais Físicos Assíncronos (Vindos do Master) ---
    reg  sclk_in;
    reg  cs_n_in;
    reg  mosi_in;

    // --- Sinais Sincronizados (Saídas do DUT) ---
    wire cs_n_sync;
    wire mosi_sync;
    wire sclk_rise;
    wire sclk_fall;

    // --- Instanciação do DUT ---
    spi_slave_sync dut (
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

    // --- Geração do Clock do Sistema (50 MHz = Período de 20ns) ---
    initial begin
        clk_sys = 0;
        forever #10 clk_sys = ~clk_sys; 
    end

    // --- Rotina de Estímulos Caóticos ---
    initial begin
        // Geração do banco de ondas
        $dumpfile("ondas_slave_sync.vcd");
        $dumpvars(0, tb_spi_slave_sync);

        // 1. Estado Inicial de Repouso
        rst_n   = 0;
        sclk_in = 0;
        cs_n_in = 1;
        mosi_in = 0;

        // Sai do reset em um tempo "quebrado" para desalinhar tudo desde o início
        #43; 
        rst_n = 1;

        $display("--------------------------------------------------");
        $display("INICIANDO TESTE DO SINCRONIZADOR CDC (SLAVE)");
        $display("--------------------------------------------------");

        // 2. Simulando o início da comunicação
        #33; // Atraso arbitrário
        cs_n_in = 0; // Master puxa o CS para baixo
        
        #17; 
        mosi_in = 1; // Master prepara o primeiro bit no MOSI

        // 3. Batidas do SCLK (Totalmente assíncronas)
        // Pulso 1
        #21; sclk_in = 1; // Sobe no meio do ciclo do clk_sys
        #47; sclk_in = 0; // Desce desincronizado
        
        // Pulso 2 (Com variação no Duty Cycle)
        #38; sclk_in = 1; mosi_in = 0;
        #31; sclk_in = 0;
        
        // Pulso 3
        #53; sclk_in = 1; mosi_in = 1;
        #42; sclk_in = 0;

        // 4. Teste de Rejeição a Ruído Crítico (Glitch / Spikes)
        // Um pico de ruído na linha SCLK de apenas 4ns (muito mais rápido que os 20ns do sistema).
        // Isso simula interferência eletromagnética (EMI) no cabo.
        #80;
        $display("[%0t] Injetando ruído de alta frequência no SCLK...", $time);
        sclk_in = 1;
        #4; // Ruído rápido de 4ns
        sclk_in = 0;

        // 5. Finaliza a comunicação
        #100;
        cs_n_in = 1;

        #100;
        $display("--------------------------------------------------");
        $display("SIMULACAO CONCLUIDA.");
        $finish;
    end

endmodule