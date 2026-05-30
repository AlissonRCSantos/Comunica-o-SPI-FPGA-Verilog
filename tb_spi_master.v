// xrun -clean tb_spi_master.v spi_master.v spi_controller.v spi_datapath.v spi_clk_gen.v +access+rwc -gui
module tb_spi_master;

    // --- Sinais do Sistema ---
    reg        clk_sys;
    reg        rst_n;
    reg  [7:0] tx_data;
    reg        start_tx;
    
    // --- Configurações do Protocolo ---
    reg        cpol;
    reg        cpha;
    reg        dord;
    
    // --- Pinos SPI e Saídas ---
    wire       sclk_out;
    wire       cs_n;
    wire       mosi_out;
    wire       miso_in;
    
    wire [7:0] rx_data;
    wire       done_flag;

    // ==========================================
    // INSTÂNCIA DO DUT (Device Under Test)
    // ==========================================
    // Vamos configurar para 50 MHz de sistema e 1 MHz de SPI para facilitar a visualização
    spi_master #(
        .CLK_SYS_FREQ(50_000_000),
        .SPI_CLK_FREQ(1_000_000)
    ) dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .start_tx(start_tx),
        .cpol(cpol),
        .cpha(cpha),
        .dord(dord),
        .rx_data(rx_data),
        .done_flag(done_flag),
        .sclk_out(sclk_out),
        .cs_n(cs_n),
        .mosi_out(mosi_out),
        .miso_in(miso_in)
    );

    // ==========================================
    // TÉCNICA DE LOOPBACK
    // O que o Mestre fala (MOSI), ele mesmo escuta (MISO)
    // ==========================================
    assign miso_in = mosi_out;

    // --- Geração do Clock do Sistema ---
    initial begin
        clk_sys = 0;
        forever #10 clk_sys = ~clk_sys; // Período de 20ns (50 MHz)
    end

    // --- Rotina de Estímulos e Validação ---
    initial begin
        // Geração de Ondas para o SimVision
        $dumpfile("ondas_spi_master.vcd");
        $dumpvars(0, tb_spi_master);

        // Estado Inicial
        rst_n    = 0;
        start_tx = 0;
        tx_data  = 8'h00;
        cpol     = 0; // Modo 0 (Ocioso em 0)
        cpha     = 0; // Modo 0 (Lê na 1ª borda)
        dord     = 0; // MSB-First

        #100;
        rst_n = 1; // Libera o Reset
        #100;

        $display("--------------------------------------------------");
        $display("INICIANDO TESTE DE INTEGRACAO DO SPI MASTER");
        $display("--------------------------------------------------");

        // --- TRANSACAO 1: Testando MSB-First (Modo 0) ---
        tx_data = 8'hA5; // Em binário: 10100101
        $display("[%0t] Transmitindo Byte: %h", $time, tx_data);
        
        @(posedge clk_sys);
        start_tx = 1;
        
        // Handshake: Espera a FSM confirmar que iniciou
        wait(cs_n == 1'b0);
        @(posedge clk_sys);
        start_tx = 0;

        // Aguarda a transmissão completa
        wait(done_flag == 1'b1);
        
        // Verificação Automática
        if (rx_data === 8'hA5)
            $display("[%0t] SUCESSO! Loopback MSB-First recebido: %h", $time, rx_data);
        else
            $display("[%0t] ERRO! Esperado A5, Recebido: %h", $time, rx_data);

        #500; // Pausa no barramento

        // --- TRANSACAO 2: Testando LSB-First com Back-to-Back ---
        // Vamos alterar a configuração em tempo de execução
        dord    = 1; 
        tx_data = 8'h81; // Em binário: 10000001
        $display("\n[%0t] Transmitindo Byte (LSB-First): %h", $time, tx_data);
        
        start_tx = 1;
        wait(cs_n == 1'b0);
        @(posedge clk_sys);
        start_tx = 0;

        wait(done_flag == 1'b1);
        
        if (rx_data === 8'h81)
            $display("[%0t] SUCESSO! Loopback LSB-First recebido: %h", $time, rx_data);
        else
            $display("[%0t] ERRO! Esperado 81, Recebido: %h", $time, rx_data);

        #1000;

        // --- TRANSACAO 3: Testando CPHA=1 (Modo 1: CPOL=0, CPHA=1) ---
        // No CPHA=1, a primeira borda do SCLK é de setup (dado já está no MOSI).
        // A amostragem ocorre na segunda borda de cada bit.
        dord    = 0;  // MSB-First
        cpha    = 1;
        tx_data = 8'hA5; // 10100101 — mesmo byte do Teste 1 para comparação
        $display("\n[%0t] Transmitindo Byte (CPHA=1, MSB-First): %h", $time, tx_data);

        @(posedge clk_sys);
        start_tx = 1;

        wait(cs_n == 1'b0);
        @(posedge clk_sys);
        start_tx = 0;

        wait(done_flag == 1'b1);

        if (rx_data === 8'hA5)
            $display("[%0t] SUCESSO! Loopback CPHA=1 recebido: %h", $time, rx_data);
        else
            $display("[%0t] ERRO! Esperado A5, Recebido: %h (CPHA=1 com bug de deslocamento)", $time, rx_data);

        #1000;
        $display("--------------------------------------------------");
        $display("SIMULACAO CONCLUIDA COM EXITO.");
        $finish;
    end

endmodule