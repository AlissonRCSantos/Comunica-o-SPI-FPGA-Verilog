
module tb_spi_slave_controller;

    // --- Sinais do Sistema ---
    reg  clk_sys;
    reg  rst_n;
    
    // --- Sinais Simulados vindos do Módulo 1 (Sincronizador) ---
    reg  cs_n_sync;
    reg  sclk_rise;
    reg  sclk_fall;
    
    // --- Configurações Estáticas ---
    reg  cpol;
    reg  cpha;
    
    // --- Saídas da FSM do Escravo ---
    wire shift_en;
    wire sample_en;
    wire miso_en;
    wire rx_done_flag;

    // --- Instanciação do DUT ---
    spi_slave_controller dut (
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

    // --- Geração do Clock do Sistema (50 MHz) ---
    initial begin
        clk_sys = 0;
        forever #10 clk_sys = ~clk_sys; 
    end

    // --- TASK: Injetar Pulso de Borda (1 ciclo de clk_sys) ---
    task injetar_borda;
        input is_rise; // 1 = sclk_rise, 0 = sclk_fall
        begin
            @(posedge clk_sys);
            if (is_rise) sclk_rise = 1'b1;
            else         sclk_fall = 1'b1;
            
            @(posedge clk_sys);
            sclk_rise = 1'b0;
            sclk_fall = 1'b0;
            
            #40; // Simula o tempo ocioso entre bordas do SCLK físico
        end
    endtask

    // --- Monitores de Contagem ---
    integer contagem_shift = 0;
    integer contagem_sample = 0;

    always @(posedge clk_sys) begin
        if (shift_en)  contagem_shift = contagem_shift + 1;
        if (sample_en) contagem_sample = contagem_sample + 1;
    end

    // --- Rotina Principal de Testes ---
    integer i;

    initial begin
        // Configuração de ondas
        $dumpfile("ondas_slave_fsm.vcd");
        $dumpvars(0, tb_spi_slave_controller);

        // 1. Estado Inicial
        rst_n     = 0;
        cs_n_sync = 1;
        sclk_rise = 0;
        sclk_fall = 0;
        cpol      = 0;
        cpha      = 0;

        #100;
        rst_n = 1;
        #50;

        $display("--------------------------------------------------");
        $display("INICIANDO TESTE DA FSM DO ESCRAVO");
        $display("--------------------------------------------------");

        // ==========================================
        // CASO 1: Transmissão Padrão (Modo 0: CPOL=0, CPHA=0)
        // Borda Líder = Subida (Sample), Borda Final = Descida (Shift)
        // ==========================================
        $display("-> Caso 1: Operacao Padrao (Modo 0)");
        cpol = 0; cpha = 0;
        contagem_shift = 0; contagem_sample = 0;
        
        @(posedge clk_sys);
        cs_n_sync = 0; // Escravo ativado
        #50;

        for (i = 0; i < 8; i = i + 1) begin
            injetar_borda(1); // Injeta sclk_rise
            injetar_borda(0); // Injeta sclk_fall
        end

        wait(rx_done_flag == 1'b1);
        
        // Retorna o barramento ao estado ocioso
        @(posedge clk_sys);
        cs_n_sync = 1; 

        if (contagem_shift == 8 && contagem_sample == 8)
            $display("   [OK] Contagem perfeita (8 Shifts, 8 Samples).");
        else
            $display("   [ERRO] Falha na contagem.");

        #150;

        // ==========================================
        // CASO 2: Inversão Extrema (Modo 3: CPOL=1, CPHA=1)
        // Borda Líder = Descida (Shift), Borda Final = Subida (Sample)
        // ==========================================
        $display("\n-> Caso 2: Modo 3 (CPOL=1, CPHA=1)");
        cpol = 1; cpha = 1;
        contagem_shift = 0; contagem_sample = 0;
        
        @(posedge clk_sys);
        cs_n_sync = 0; // Escravo ativado
        #50;

        for (i = 0; i < 8; i = i + 1) begin
            injetar_borda(0); // Injeta sclk_fall (Borda Líder no Modo 3)
            injetar_borda(1); // Injeta sclk_rise (Borda Final no Modo 3)
        end

        wait(rx_done_flag == 1'b1);
        
        @(posedge clk_sys);
        cs_n_sync = 1; 

        if (contagem_shift == 8 && contagem_sample == 8)
            $display("   [OK] Lógica CPHA/CPOL abstrata funcionou.");
        else
            $display("   [ERRO] Falha na contagem do Modo 3.");

        #150;

        // ==========================================
        // CASO 3: Aborto Abrupto (Falha de Comunicação)
        // ==========================================
        $display("\n-> Caso 3: Aborto no meio da transmissão");
        cpol = 0; cpha = 0;
        
        @(posedge clk_sys);
        cs_n_sync = 0;
        
        // Transmite apenas 3 bits (6 transições)
        for (i = 0; i < 3; i = i + 1) begin
            injetar_borda(1);
            injetar_borda(0);
        end
        
        // Mestre sofre reset e puxa o CS abruptamente!
        #20;
        $display("   [!] Mestre abortou a transmissao!");
        cs_n_sync = 1;

        // Espera um pouco para garantir que a flag não vai subir por acidente
        #200;
        
        if (rx_done_flag == 1'b0)
            $display("   [OK] FSM do Escravo resetou graciosamente sem gerar falso evento.");
        else
            $display("   [ERRO] FSM emitiu um DONE para um dado corrompido.");

        #100;
        $display("--------------------------------------------------");
        $display("SIMULACAO CONCLUIDA COM EXITO.");
        $finish;
    end

endmodule