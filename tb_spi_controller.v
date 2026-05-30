//xrun -clean tb_spi_controller.v spi_controller.v +access+rwc -gui
module tb_spi_controller;

    // --- Sinais do Testbench ---
    reg  clk_sys;
    reg  rst_n;
    reg  start_tx;
    reg  cpha;
    
    wire done_flag;
    wire cs_n;
    wire en_sclk;
    wire load_en;
    wire shift_en;
    wire sample_en;

    // --- Sinal Simulado (Mock) ---
    reg  edge_tick;
    reg  [2:0] tick_div; // Divisor simples para simular o tempo do clock físico

    // --- Instanciação do DUT (Device Under Test) ---
    spi_controller dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .start_tx(start_tx),
        .cpha(cpha),
        .done_flag(done_flag),
        .edge_tick(edge_tick),
        .en_sclk(en_sclk),
        .cs_n(cs_n),
        .load_en(load_en),
        .shift_en(shift_en),
        .sample_en(sample_en)
    );

    // --- Geração do Clock do Sistema ---
    initial begin
        clk_sys = 0;
        forever #10 clk_sys = ~clk_sys; // 50 MHz (Período 20ns)
    end

    // --- Emulador do Módulo Gerador de Clock ---
    // Sempre que a FSM ativar en_sclk, começamos a gerar um edge_tick 
    // a cada 4 ciclos de clk_sys para simular a passagem do tempo.
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            tick_div  <= 0;
            edge_tick <= 0;
        end else begin
            if (!en_sclk) begin
                tick_div  <= 0;
                edge_tick <= 0;
            end else begin
                if (tick_div == 3) begin
                    tick_div  <= 0;
                    edge_tick <= 1'b1; // Dispara o pulso
                end else begin
                    tick_div  <= tick_div + 1'b1;
                    edge_tick <= 1'b0; // Abaixa o pulso no ciclo seguinte
                end
            end
        end
    end

    // --- Monitores de Verificação ---
    integer contagem_shift = 0;
    integer contagem_sample = 0;

    // Conta quantos comandos foram enviados durante uma transferência
    always @(posedge clk_sys) begin
        if (shift_en)  contagem_shift = contagem_shift + 1;
        if (sample_en) contagem_sample = contagem_sample + 1;
    end

    // --- Rotina de Estímulos ---
    initial begin
        $dumpfile("ondas_fsm.vcd");
        $dumpvars(0, tb_spi_controller);

        // Estado Inicial
        rst_n    = 0;
        start_tx = 0;
        cpha     = 0;

        #50;
        rst_n = 1; // Libera o reset
        #50;

        // ==========================================
        // CASO 1: Transmissão Padrão (CPHA = 0)
        // ==========================================
        $display("Iniciando Caso 1: CPHA = 0");
        cpha = 0;
        contagem_shift = 0;
        contagem_sample = 0;
        
        @(posedge clk_sys);
        start_tx = 1;
        @(posedge clk_sys);
        start_tx = 0; // Pulso de 1 ciclo

        // Injeta ruído no gatilho durante a transferência (Caso 4)
        #200;
        start_tx = 1;
        #20;
        start_tx = 0;

        // Aguarda a flag de fim
        wait(done_flag == 1'b1);
        
        $display("Fim Caso 1. Shifts: %0d | Samples: %0d", contagem_shift, contagem_sample);
        if (contagem_shift == 8 && contagem_sample == 8)
            $display("[OK] Contagem perfeita.");
        else
            $display("[ERRO] Contagem falhou.");

        #100;

        // ==========================================
        // CASO 2: Inversão de Fase (CPHA = 1)
        // ==========================================
        $display("\nIniciando Caso 2: CPHA = 1");
        cpha = 1;
        contagem_shift = 0;
        contagem_sample = 0;
        
        @(posedge clk_sys);
        start_tx = 1;
        @(posedge clk_sys);
        start_tx = 0;

        wait(done_flag == 1'b1);
        
        $display("Fim Caso 2. Shifts: %0d | Samples: %0d", contagem_shift, contagem_sample);
        if (contagem_shift == 8 && contagem_sample == 8)
            $display("[OK] Contagem perfeita.");
        else
            $display("[ERRO] Contagem falhou.");

        // ==========================================
        // CASO 3: Gatilho Back-to-Back VERDADEIRO
        // ==========================================
        $display("\nIniciando Caso 3: Back-to-Back");
        
        // Levanta o start_tx IMEDIATAMENTE após o fim do Caso 2.
        // Não esperamos o posedge clk_sys aqui. Isso injeta o gatilho 
        // no exato momento em que a FSM está no estado END.
        start_tx = 1; 
        
        // A FSM vai avaliar isso no próximo clock e pular direto para START.
        // Esperamos a confirmação da FSM (CS caindo para zero).
        wait(cs_n == 1'b0); 
        
        // Agora a FSM já engatou a nova transmissão, podemos abaixar o gatilho com segurança.
        @(posedge clk_sys);
        start_tx = 0;
        
        // Aguarda a flag de fim desta nova transmissão
        wait(done_flag == 1'b1);
        $display("Transmissão 3 (Back-to-Back) concluída.");

        #100;
        $display("Teste da FSM Finalizado.");
        $finish;
    end

endmodule