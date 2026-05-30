// xrun tb_spi_datapath.v spi_datapath.v +access+rwc -gui
module tb_spi_datapath;

    // --- Sinais do Testbench ---
    reg        clk_sys;
    reg        rst_n;
    reg  [7:0] tx_data;
    reg        load_en;
    reg        shift_en;
    reg        sample_en;
    reg        dord;
    reg        miso_in;
    
    wire       mosi_out;
    wire [7:0] rx_data;

    // --- Instanciação do DUT (Device Under Test) ---
    spi_datapath dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .load_en(load_en),
        .shift_en(shift_en),
        .sample_en(sample_en),
        .dord(dord),
        .miso_in(miso_in),
        .mosi_out(mosi_out),
        .rx_data(rx_data)
    );

    // --- Geração do Clock do Sistema (50 MHz) ---
    initial begin
        clk_sys = 0;
        forever #10 clk_sys = ~clk_sys; // Período de 20ns
    end

    // --- TASK: Simular a FSM transferindo 1 Byte ---
    // Esta task injeta os pulsos de controle e verifica o MOSI bit a bit.
    task simular_fsm_transferencia;
        input [7:0] byte_para_enviar;
        input [7:0] byte_simulado_receber; // Dado que fingiremos que o escravo está mandando
        input       modo_dord;             // 0 = MSB-First, 1 = LSB-First
        
        integer i, bit_idx;
        reg expected_mosi;
        begin
            // 1. Configuração Inicial
            dord    = modo_dord;
            tx_data = byte_para_enviar;
            
            // 2. Pulso de Carregamento (Load)
            @(posedge clk_sys);
            load_en = 1;
            @(posedge clk_sys);
            load_en = 0;

            // 3. Loop de 8 ciclos para transmitir/receber bit a bit
            for (i = 0; i < 8; i = i + 1) begin
                
                // Determina o índice do bit com base no DORD
                if (modo_dord == 1'b0) 
                    bit_idx = 7 - i; // MSB-First: 7, 6, 5...
                else                   
                    bit_idx = i;     // LSB-First: 0, 1, 2...

                // -- Verifica o MOSI (Previsão combinacional) --
                expected_mosi = byte_para_enviar[bit_idx];
                if (mosi_out !== expected_mosi)
                    $display("[ERRO] MOSI falhou no bit %0d. Esperado: %b, Obtido: %b", bit_idx, expected_mosi, mosi_out);

                // -- Alimenta o MISO (Simulando o Escravo) --
                miso_in = byte_simulado_receber[bit_idx];

                // -- Pulso de Amostragem (Sample) --
                @(posedge clk_sys);
                sample_en = 1;
                @(posedge clk_sys);
                sample_en = 0;

                // -- Pulso de Deslocamento (Shift) --
                @(posedge clk_sys);
                shift_en = 1;
                @(posedge clk_sys);
                shift_en = 0;
            end

            // 4. Verificação Final do Byte Recebido (RX Data)
            @(posedge clk_sys);
            if (rx_data === byte_simulado_receber)
                $display("[SUCESSO] Byte recebido perfeitamente! (Enviado: %h | Recebido: %h | DORD: %0b)", 
                         byte_para_enviar, rx_data, modo_dord);
            else
                $display("[ERRO] Byte corrompido. Recebido: %h, Esperado: %h", rx_data, byte_simulado_receber);
        end
    endtask

    // --- Rotina Principal de Testes ---
    initial begin
        // Geração do banco de dados para o SimVision
        $dumpfile("ondas_datapath.vcd");
        $dumpvars(0, tb_spi_datapath);

        // Estado inicial de repouso
        rst_n = 0; load_en = 0; shift_en = 0; sample_en = 0; dord = 0; miso_in = 0; tx_data = 0;
        
        // Sai do reset
        #100;
        rst_n = 1;
        #50;

        $display("--------------------------------------------------");
        $display("INICIANDO TESTE DO DATAPATH SPI");
        $display("--------------------------------------------------");

        // Teste 1: Padrão da Indústria (MSB-First)
        // Vamos enviar 0xA5 (10100101) e fingir que o escravo respondeu 0xC3 (11000011)
        $display("-> Executando Teste 1: MSB-First (DORD = 0)");
        simular_fsm_transferencia(8'hA5, 8'hC3, 0);

        #100; // Pausa entre os bytes

        // Teste 2: Invertido (LSB-First)
        // Vamos enviar 0x81 (10000001) e fingir que o escravo respondeu 0x7E (01111110)
        $display("-> Executando Teste 2: LSB-First (DORD = 1)");
        simular_fsm_transferencia(8'h81, 8'h7E, 1);

        #100;
        $display("--------------------------------------------------");
        $display("SIMULACAO CONCLUIDA.");
        $finish;
    end

endmodule