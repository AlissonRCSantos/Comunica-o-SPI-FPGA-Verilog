module tb_spi_clk_gen;

    // --- Parâmetros ---
    localparam SYS_FREQ = 50_000_000; // 50 MHz
    localparam SPI_FREQ = 1_000_000;  // 1 MHz
    
    // O período de 50 MHz é 20 ns (10 ns em alto, 10 ns em baixo)
    localparam CLK_PERIOD = 20; 

    // --- Sinais do Testbench ---
    reg  clk_sys;
    reg  rst_n;
    reg  en_sclk;
    reg  cpol;
    
    wire sclk_out;
    wire edge_tick;

    // --- Instanciação do DUT (Device Under Test) ---
    spi_clk_gen #(
        .CLK_SYS_FREQ(SYS_FREQ),
        .SPI_CLK_FREQ(SPI_FREQ)
    ) dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .en_sclk(en_sclk),
        .cpol(cpol),
        .sclk_out(sclk_out),
        .edge_tick(edge_tick)
    );

    // --- Geração do Clock do Sistema ---
    initial begin
        clk_sys = 0;
        forever #(CLK_PERIOD / 2) clk_sys = ~clk_sys;
    end

    // --- Medidor Automático de Frequência ---
    realtime t1, t2, measured_period;
    initial begin
        // Aguarda o módulo ser habilitado
        wait(en_sclk == 1'b1);
        
        // Pega o tempo da primeira borda de subida
        @(posedge sclk_out);
        t1 = $realtime;
        
        // Pega o tempo da segunda borda de subida
        @(posedge sclk_out);
        t2 = $realtime;
        
        measured_period = t2 - t1;
        
        $display("--------------------------------------------------");
        $display("Tempo medido do Periodo SCLK: %0.2f ns", measured_period);
        
        // Se queremos 1 MHz, o período deve ser exatos 1000 ns.
        if (measured_period == 1000.0)
            $display("RESULTADO: SUCESSO! Frequencia esta correta (1 MHz).");
        else
            $display("RESULTADO: FALHA! Frequencia incorreta.");
        $display("--------------------------------------------------");
    end

    // --- Estímulos do Teste ---
    initial begin
        // Configuração para o Cadence gerar o banco de dados de ondas (.shm) ou (.vcd) padrão
        $dumpfile("ondas_spi.vcd"); 
        $dumpvars(0, tb_spi_clk_gen);

        // Estado inicial
        rst_n   = 0;
        en_sclk = 0;
        cpol    = 0; // Modo 0 (Clock ocioso em 0)

        // Tira do reset após 100ns
        #100;
        rst_n = 1;
        
        // Aguarda um pouco e habilita o gerador de clock do SPI
        #100;
        en_sclk = 1;
        
        // Deixa rodar por 5 microsegundos (suficiente para ver 5 ciclos completos de 1MHz)
        #5000;
        
        // Desliga o gerador (simulando fim da transmissão)
        en_sclk = 0;
        
        // Testa o comportamento com CPOL = 1 (Clock ocioso em 1)
        #1000;
        cpol = 1;
        #100; // Tempo de setup
        en_sclk = 1;
        #5000;
        en_sclk = 0;

        // Fim da simulação
        #500;
        $display("Simulacao concluida com exito.");
        $finish;
    end

endmodule