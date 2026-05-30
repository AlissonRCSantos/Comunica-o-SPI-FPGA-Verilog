//xrun -clean tb_spi_slave.v spi_slave.v spi_slave_controller.v spi_slave_datapath.v spi_slave_sync.v +access+rwc -gui
module tb_spi_slave;

    // --- Sinais do Sistema Local do Escravo ---
    reg        clk_sys;
    reg        rst_n;
    reg  [7:0] tx_data;
    wire [7:0] rx_data;
    wire       rx_done_flag;
    
    // --- Configurações Estáticas ---
    reg        cpol;
    reg        cpha;
    reg        dord;

    // --- Pinos Físicos do Barramento SPI ---
    reg        sclk_in;
    reg        cs_n_in;
    reg        mosi_in;
    wire       miso_out;

    // --- Variáveis Auxiliares do Testbench ---
    reg [7:0]  master_rx_byte; // Para guardar o que o Mestre Virtual leu do Escravo

    // ==========================================
    // INSTÂNCIA DO DUT (Device Under Test)
    // ==========================================
    spi_slave dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .rx_done_flag(rx_done_flag),
        .cpol(cpol),
        .cpha(cpha),
        .dord(dord),
        .sclk_in(sclk_in),
        .cs_n_in(cs_n_in),
        .mosi_in(mosi_in),
        .miso_out(miso_out)
    );

    // --- Geração do Clock do Sistema Local (50 MHz) ---
    initial begin
        clk_sys = 0;
        forever #10 clk_sys = ~clk_sys; // Período de 20ns
    end

    // ==========================================
    // TASK: Mestre SPI Virtual (Simula o mundo físico)
    // ==========================================
    task mestre_virtual_transmite;
        input  [7:0] byte_para_enviar;
        input        modo_dord;
        input        modo_cpol;
        
        integer i, bit_idx;
        begin
            // 1. Preparação (Setup Time)
            cs_n_in = 0; // Seleciona o escravo
            #100; // Aguarda 100ns para o Escravo perceber e carregar o tx_data

            master_rx_byte = 8'h00;

            // 2. Transmissão dos 8 bits
            for (i = 0; i < 8; i = i + 1) begin
                
                // Define qual bit o Mestre vai enviar (MOSI)
                if (modo_dord == 0) bit_idx = 7 - i; // MSB-First
                else                bit_idx = i;     // LSB-First
                
                mosi_in = byte_para_enviar[bit_idx];
                
                // Simula o tempo do Master (Clock SPI de 1 MHz = Período de 1000ns)
                #500; 
                
                // Borda Líder (Mestre gera clock)
                sclk_in = ~modo_cpol; 
                
                // Amostra o MISO (O que o Escravo está dizendo?)
                master_rx_byte[bit_idx] = miso_out;
                
                #500;
                
                // Borda Final
                sclk_in = modo_cpol;
            end

            // 3. Finalização (Teardown)
            #100;
            cs_n_in = 1; // Libera o escravo
            mosi_in = 0;
        end
    endtask

    // ==========================================
    // ROTINA PRINCIPAL DE TESTES
    // ==========================================
    initial begin
        // Geração de formas de onda
        $dumpfile("ondas_spi_slave_top.vcd");
        $dumpvars(0, tb_spi_slave);

        // Estado inicial
        rst_n   = 0;
        sclk_in = 0;
        cs_n_in = 1;
        mosi_in = 0;
        tx_data = 8'h00;
        cpol    = 0;
        cpha    = 0;
        dord    = 0;

        #100;
        rst_n = 1;
        #100;

        $display("--------------------------------------------------");
        $display("INICIANDO TESTE DO TOP-LEVEL SPI SLAVE");
        $display("--------------------------------------------------");

        // --- VERIFICAÇÃO 1: Teste de Alta Impedância (Tri-State) ---
        if (miso_out === 1'bz) 
            $display("[OK] MISO iniciou em Alta Impedancia (Z) corretamente.");
        else 
            $display("[ERRO] MISO nao esta em estado Z enquanto CS = 1. Valor: %b", miso_out);

        #100;

        // --- VERIFICAÇÃO 2: Comunicação Full-Duplex (Modo 0, MSB-First) ---
        // O Mestre Virtual vai enviar 0x81.
        // O nosso Escravo vai ser carregado para responder 0x3C.
        $display("\n-> Teste 2: Comunicação Full-Duplex (MSB-First)");
        cpol    = 0;
        cpha    = 0;
        dord    = 0;
        tx_data = 8'h3C; // O que o Escravo deve colocar no MISO
        
        fork
            // Thread 1: Mestre Virtual agindo nos pinos físicos
            mestre_virtual_transmite(8'h81, 0, 0);
            
            // Thread 2: Monitorando o lado interno do Escravo
            begin
                wait(rx_done_flag == 1'b1);
                if (rx_data === 8'h81)
                    $display("   [OK] Escravo recebeu perfeitamente: %h", rx_data);
                else
                    $display("   [ERRO] Escravo recebeu: %h (Esperado: 81)", rx_data);
            end
        join

        // Verifica o que o Mestre Virtual leu do Escravo
        if (master_rx_byte === 8'h3C)
            $display("   [OK] Mestre Virtual leu perfeitamente do Escravo: %h", master_rx_byte);
        else
            $display("   [ERRO] Mestre Virtual leu: %h (Esperado: 3C)", master_rx_byte);

        // --- VERIFICAÇÃO 3: Retorno à Alta Impedância ---
        #200;
        if (miso_out === 1'bz) 
            $display("\n[OK] MISO retornou para Alta Impedancia (Z) apos o fim da transacao.");
        else 
            $display("\n[ERRO] MISO travou eletricamente. Valor: %b", miso_out);

        #500;
        $display("--------------------------------------------------");
        $display("SIMULACAO CONCLUIDA COM EXITO.");
        $finish;
    end

endmodule