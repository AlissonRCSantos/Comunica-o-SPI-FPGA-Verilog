// xrun -clean tb_spi_slave_datapath.v spi_slave_datapath.v +access+rwc -gui

module tb_spi_slave_datapath;

    // --- Sinais do Testbench ---
    reg        clk_sys;
    reg        rst_n;
    
    reg  [7:0] tx_data;
    reg        dord;
    wire [7:0] rx_data;
    
    reg        load_en;
    reg        shift_en;
    reg        sample_en;
    reg        mosi_sync;
    
    wire       miso_internal;

    // --- Instanciação do DUT ---
    spi_slave_datapath dut (
        .clk_sys(clk_sys),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .dord(dord),
        .rx_data(rx_data),
        .load_en(load_en),
        .shift_en(shift_en),
        .sample_en(sample_en),
        .mosi_sync(mosi_sync),
        .miso_internal(miso_internal)
    );

    // --- Geração do Clock do Sistema (50 MHz) ---
    initial begin
        clk_sys = 0;
        forever #10 clk_sys = ~clk_sys; // Período de 20ns
    end

    // --- TASK: Simular a FSM do Escravo processando 1 Byte ---
    task simular_fsm_escravo;
        input [7:0] byte_para_transmitir;
        input [7:0] byte_simulado_receber;
        input       modo_dord;
        
        integer i, bit_idx;
        reg expected_miso;
        begin
            // 1. Configuração Inicial do Sistema Superior
            dord    = modo_dord;
            tx_data = byte_para_transmitir;
            
            // 2. Pulso de Load (Simulando a detecção da queda do CS)
            @(posedge clk_sys);
            load_en = 1;
            @(posedge clk_sys);
            load_en = 0;

            // 3. Processamento Bit a Bit (8 ciclos do protocolo)
            for (i = 0; i < 8; i = i + 1) begin
                
                // Determina qual bit esperamos ver no MISO com base no DORD
                if (modo_dord == 1'b0) 
                    bit_idx = 7 - i; // MSB-First
                else                   
                    bit_idx = i;     // LSB-First

                // -- Verifica a saída combinacional MISO --
                expected_miso = byte_para_transmitir[bit_idx];
                if (miso_internal !== expected_miso)
                    $display("[ERRO] MISO falhou no bit %0d. Esperado: %b, Obtido: %b", bit_idx, expected_miso, miso_internal);

                // -- Alimenta o MOSI Sincronizado (Simulando o dado vindo do Master) --
                mosi_sync = byte_simulado_receber[bit_idx];

                // -- Pulso de Amostragem (FSM detectou borda apropriada) --
                @(posedge clk_sys);
                sample_en = 1;
                @(posedge clk_sys);
                sample_en = 0;

                // -- Pulso de