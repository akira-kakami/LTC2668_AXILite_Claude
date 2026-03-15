// =============================================================================
// ltc2668_axi_tb.sv
// Testbench for ltc2668_axi – LTC2668 AXI4-Lite DAC Controller
//
// Test Cases:
//   TC1  : Reset / デフォルト値確認
//   TC2  : SPI_CLK_DIV 設定
//   TC3  : Write Channel (CMD=0x0)
//   TC4  : Write & Update Channel (CMD=0x3)
//   TC5  : Update All (CMD=0x8)
//   TC6  : Per-channel Span (CMD=0x6)
//   TC7  : Global Span (CMD=0x7)
//   TC8  : Power Down Channel (CMD=0x4)
//   TC9  : Toggle Select (CMD=0xC)
//   TC10 : MUX Output (CMD=0xB)
//   TC11 : LDAC_N / CLR_N ハードウェア制御
//   TC12 : SPI ビットシーケンス検証（受信フレーム照合）
// =============================================================================

`timescale 1ns / 1ps

module ltc2668_axi_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam AXI_ADDR_WIDTH     = 8;
    localparam AXI_DATA_WIDTH     = 32;
    localparam SPI_CLK_DIV_DEFAULT = 4;

    localparam CLK_PERIOD = 10;  // 100 MHz

    // Register offsets
    localparam REG_CTRL        = 8'h00;
    localparam REG_CH_SEL      = 8'h04;
    localparam REG_DAC_DATA    = 8'h08;
    localparam REG_SPAN        = 8'h0C;
    localparam REG_CMD         = 8'h10;
    localparam REG_STATUS      = 8'h14;
    localparam REG_SPI_CLK_DIV = 8'h18;
    localparam REG_TOGGLE_SEL  = 8'h1C;
    localparam REG_MUX_CTRL    = 8'h20;
    localparam REG_GLOBAL_SPAN = 8'h24;

    // LTC2668 Commands
    localparam CMD_WRITE_N          = 4'h0;
    localparam CMD_UPDATE_N         = 4'h1;
    localparam CMD_WRITE_UPDATE_N   = 4'h3;
    localparam CMD_POWER_DOWN_N     = 4'h4;
    localparam CMD_POWER_DOWN_ALL   = 4'h5;
    localparam CMD_SPAN_N           = 4'h6;
    localparam CMD_SPAN_ALL         = 4'h7;
    localparam CMD_UPDATE_ALL       = 4'h8;
    localparam CMD_WRITE_UPDATE_ALL = 4'hA;
    localparam CMD_MUX_OUT          = 4'hB;
    localparam CMD_TOGGLE_SEL       = 4'hC;
    localparam CMD_NOP              = 4'hF;

    // -------------------------------------------------------------------------
    // DUT Signals
    // -------------------------------------------------------------------------
    logic                         s_axi_aclk;
    logic                         s_axi_aresetn;

    logic [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr;
    logic                         s_axi_awvalid;
    logic                         s_axi_awready;

    logic [AXI_DATA_WIDTH-1:0]    s_axi_wdata;
    logic [3:0]                   s_axi_wstrb;
    logic                         s_axi_wvalid;
    logic                         s_axi_wready;

    logic [1:0]                   s_axi_bresp;
    logic                         s_axi_bvalid;
    logic                         s_axi_bready;

    logic [AXI_ADDR_WIDTH-1:0]    s_axi_araddr;
    logic                         s_axi_arvalid;
    logic                         s_axi_arready;

    logic [AXI_DATA_WIDTH-1:0]    s_axi_rdata;
    logic [1:0]                   s_axi_rresp;
    logic                         s_axi_rvalid;
    logic                         s_axi_rready;

    logic                         spi_sck;
    logic                         spi_sdi;
    logic                         spi_sdo;
    logic                         spi_cs_n;
    logic                         ldac_n;
    logic                         clr_n;

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    ltc2668_axi #(
        .AXI_ADDR_WIDTH      (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH      (AXI_DATA_WIDTH),
        .SPI_CLK_DIV_DEFAULT (SPI_CLK_DIV_DEFAULT)
    ) dut (
        .s_axi_aclk    (s_axi_aclk),
        .s_axi_aresetn (s_axi_aresetn),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .spi_sck       (spi_sck),
        .spi_sdi       (spi_sdi),
        .spi_sdo       (spi_sdo),
        .spi_cs_n      (spi_cs_n),
        .ldac_n        (ldac_n),
        .clr_n         (clr_n)
    );

    // -------------------------------------------------------------------------
    // Clock Generation (100 MHz)
    // -------------------------------------------------------------------------
    initial s_axi_aclk = 0;
    always #(CLK_PERIOD/2) s_axi_aclk = ~s_axi_aclk;

    assign spi_sdo = 1'b0;

    // -------------------------------------------------------------------------
    // SPI Monitor: capture received 32-bit frame
    // -------------------------------------------------------------------------
    logic [31:0] spi_rx_frame;
    logic        spi_frame_valid;
    int          spi_bit_idx;

    always @(negedge spi_cs_n) begin
        spi_rx_frame  = 32'h0;
        spi_frame_valid = 1'b0;
        spi_bit_idx   = 31;
    end

    always @(posedge spi_sck) begin
        if (!spi_cs_n) begin
            spi_rx_frame[spi_bit_idx] = spi_sdi;
            if (spi_bit_idx == 0)
                spi_frame_valid = 1'b1;
            else
                spi_bit_idx--;
        end
    end

    // -------------------------------------------------------------------------
    // Test counter / result tracking
    // -------------------------------------------------------------------------
    int pass_count = 0;
    int fail_count = 0;

    task automatic check(
        input string   name,
        input logic [31:0] got,
        input logic [31:0] exp
    );
        if (got === exp) begin
            $display("  [PASS] %s  got=0x%08h", name, got);
            pass_count++;
        end else begin
            $display("  [FAIL] %s  got=0x%08h  exp=0x%08h", name, got, exp);
            fail_count++;
        end
    endtask

    // -------------------------------------------------------------------------
    // AXI4-Lite Write Task
    // -------------------------------------------------------------------------
    task automatic axi_write(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_DATA_WIDTH-1:0] data
    );
        @(posedge s_axi_aclk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wstrb   <= 4'hF;
        s_axi_wvalid  <= 1'b1;

        // Wait for AWREADY
        @(posedge s_axi_aclk);
        while (!s_axi_awready) @(posedge s_axi_aclk);
        s_axi_awvalid <= 1'b0;

        // Wait for WREADY
        while (!s_axi_wready) @(posedge s_axi_aclk);
        s_axi_wvalid  <= 1'b0;

        // Wait for BVALID
        s_axi_bready  <= 1'b1;
        while (!s_axi_bvalid) @(posedge s_axi_aclk);
        @(posedge s_axi_aclk);
        s_axi_bready  <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // AXI4-Lite Read Task
    // -------------------------------------------------------------------------
    task automatic axi_read(
        input  logic [AXI_ADDR_WIDTH-1:0] addr,
        output logic [AXI_DATA_WIDTH-1:0] data
    );
        @(posedge s_axi_aclk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;

        while (!s_axi_arready) @(posedge s_axi_aclk);
        @(posedge s_axi_aclk);
        s_axi_arvalid <= 1'b0;

        while (!s_axi_rvalid) @(posedge s_axi_aclk);
        data = s_axi_rdata;
        @(posedge s_axi_aclk);
        s_axi_rready  <= 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Wait for SPI transaction to complete (poll STATUS.BUSY == 0)
    // -------------------------------------------------------------------------
    task automatic wait_spi_done;
        logic [31:0] status;
        int timeout = 0;
        do begin
            axi_read(REG_STATUS, status);
            timeout++;
            if (timeout > 10000) begin
                $display("  [FAIL] wait_spi_done: timeout");
                fail_count++;
                return;
            end
        end while (status[0]);  // BUSY
    endtask

    // -------------------------------------------------------------------------
    // Send a single LTC2668 SPI command via register writes
    // -------------------------------------------------------------------------
    task automatic send_cmd(
        input logic [3:0]  cmd,
        input logic [3:0]  ch,
        input logic [15:0] dat,
        input logic [2:0]  span_val  = 3'h0,
        input logic [4:0]  mux_val   = 5'h0,
        input logic [15:0] toggle_val= 16'h0
    );
        axi_write(REG_CH_SEL,   {28'h0, ch});
        axi_write(REG_DAC_DATA, {16'h0, dat});

        case (cmd)
            CMD_SPAN_N:     axi_write(REG_SPAN,        {29'h0, span_val});
            CMD_SPAN_ALL:   axi_write(REG_GLOBAL_SPAN,  {29'h0, span_val});
            CMD_MUX_OUT:    axi_write(REG_MUX_CTRL,     {27'h0, mux_val});
            CMD_TOGGLE_SEL: axi_write(REG_TOGGLE_SEL,   {16'h0, toggle_val});
            default: ;
        endcase

        axi_write(REG_CMD, {28'h0, cmd});
        wait_spi_done();
    endtask

    // =========================================================================
    // Main Test
    // =========================================================================
    logic [31:0] rdata;
    logic [31:0] expected_frame;

    initial begin
        // ---------------- Signal Initialization ----------------
        s_axi_aresetn = 1'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
        s_axi_awaddr  = '0;
        s_axi_wdata   = '0;
        s_axi_wstrb   = 4'hF;
        s_axi_araddr  = '0;

        repeat(5) @(posedge s_axi_aclk);
        s_axi_aresetn = 1'b1;
        repeat(3) @(posedge s_axi_aclk);

        $display("=============================================================");
        $display(" LTC2668 AXI Testbench");
        $display("=============================================================");

        // =====================================================================
        // TC1: Reset – デフォルトレジスタ値確認
        // =====================================================================
        $display("\n[TC1] Reset / Default register values");

        axi_read(REG_CTRL,        rdata); check("CTRL default",        rdata, 32'h0);
        axi_read(REG_CH_SEL,      rdata); check("CH_SEL default",      rdata, 32'h0);
        axi_read(REG_DAC_DATA,    rdata); check("DAC_DATA default",     rdata, 32'h0);
        axi_read(REG_SPAN,        rdata); check("SPAN default",         rdata, 32'h0);
        axi_read(REG_SPI_CLK_DIV, rdata); check("SPI_CLK_DIV default",  rdata, 32'(SPI_CLK_DIV_DEFAULT));
        axi_read(REG_STATUS,      rdata); check("STATUS default",       rdata, 32'h0);
        axi_read(REG_TOGGLE_SEL,  rdata); check("TOGGLE_SEL default",   rdata, 32'h0);
        axi_read(REG_MUX_CTRL,    rdata); check("MUX_CTRL default",     rdata, 32'h0);
        axi_read(REG_GLOBAL_SPAN, rdata); check("GLOBAL_SPAN default",  rdata, 32'h0);

        // =====================================================================
        // TC2: SPI_CLK_DIV 書き込み・読み返し
        // =====================================================================
        $display("\n[TC2] SPI_CLK_DIV write/readback");

        axi_write(REG_SPI_CLK_DIV, 32'h08);
        axi_read (REG_SPI_CLK_DIV, rdata);
        check("SPI_CLK_DIV=8", rdata, 32'h08);

        // Restore default
        axi_write(REG_SPI_CLK_DIV, 32'(SPI_CLK_DIV_DEFAULT));

        // =====================================================================
        // TC3: Write Channel – CH5, DATA=0xABCD (CMD=0x0)
        // =====================================================================
        $display("\n[TC3] CMD_WRITE_N (ch=5, data=0xABCD)");

        fork
            send_cmd(CMD_WRITE_N, 4'h5, 16'hABCD);
            begin
                @(posedge spi_frame_valid);
                // Expected frame: {CMD[3:0], ADDR[3:0], DATA[15:0], X[7:0]}
                expected_frame = {CMD_WRITE_N, 4'h5, 16'hABCD, 8'h00};
                check("TC3 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC4: Write & Update Channel – CH0, DATA=0x1234 (CMD=0x3)
        // =====================================================================
        $display("\n[TC4] CMD_WRITE_UPDATE_N (ch=0, data=0x1234)");

        fork
            send_cmd(CMD_WRITE_UPDATE_N, 4'h0, 16'h1234);
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_WRITE_UPDATE_N, 4'h0, 16'h1234, 8'h00};
                check("TC4 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC5: Update All (CMD=0x8)
        // =====================================================================
        $display("\n[TC5] CMD_UPDATE_ALL");

        fork
            send_cmd(CMD_UPDATE_ALL, 4'hF, 16'h0);
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_UPDATE_ALL, 4'hF, 16'h0000, 8'h00};
                check("TC5 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC6: Per-channel Span – CH3, SPAN=2 (±5V) (CMD=0x6)
        // =====================================================================
        $display("\n[TC6] CMD_SPAN_N (ch=3, span=2)");

        fork
            send_cmd(CMD_SPAN_N, 4'h3, 16'h0, .span_val(3'h2));
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_SPAN_N, 4'h3, 13'b0, 3'h2, 8'h00};
                check("TC6 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC7: Global Span – SPAN=3 (±10V) (CMD=0x7)
        // =====================================================================
        $display("\n[TC7] CMD_SPAN_ALL (span=3)");

        fork
            begin
                axi_write(REG_GLOBAL_SPAN, 32'h3);
                axi_write(REG_CMD, {28'h0, CMD_SPAN_ALL});
                wait_spi_done();
            end
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_SPAN_ALL, 4'hF, 13'b0, 3'h3, 8'h00};
                check("TC7 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC8: Power Down Channel – CH7 (CMD=0x4)
        // =====================================================================
        $display("\n[TC8] CMD_POWER_DOWN_N (ch=7)");

        fork
            send_cmd(CMD_POWER_DOWN_N, 4'h7, 16'h0);
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_POWER_DOWN_N, 4'h7, 16'h0000, 8'h00};
                check("TC8 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC9: Toggle Select – mask=0xFF00 (CMD=0xC)
        // =====================================================================
        $display("\n[TC9] CMD_TOGGLE_SEL (mask=0xFF00)");

        fork
            send_cmd(CMD_TOGGLE_SEL, 4'hF, 16'h0, .toggle_val(16'hFF00));
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_TOGGLE_SEL, 4'hF, 16'hFF00, 8'h00};
                check("TC9 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC10: MUX Output – channel=0x1A (CMD=0xB)
        // =====================================================================
        $display("\n[TC10] CMD_MUX_OUT (mux=0x1A)");

        fork
            send_cmd(CMD_MUX_OUT, 4'hF, 16'h0, .mux_val(5'h1A));
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_MUX_OUT, 4'hF, 11'b0, 5'h1A, 8'h00};
                check("TC10 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC11: LDAC_N / CLR_N ハードウェア制御
        // =====================================================================
        $display("\n[TC11] LDAC_N / CLR_N control via CTRL register");

        // LDAC_N assert (CTRL[2]=1)
        axi_write(REG_CTRL, 32'h4);
        repeat(3) @(posedge s_axi_aclk);
        check("LDAC_N asserted (=0)", {31'h0, ldac_n}, 32'h0);
        check("CLR_N idle (=1)",      {31'h0, clr_n},  32'h1);

        // CLR_N assert (CTRL[3]=1)
        axi_write(REG_CTRL, 32'h8);
        repeat(3) @(posedge s_axi_aclk);
        check("LDAC_N idle (=1)",     {31'h0, ldac_n}, 32'h1);
        check("CLR_N asserted (=0)",  {31'h0, clr_n},  32'h0);

        // Both deassert
        axi_write(REG_CTRL, 32'h0);
        repeat(3) @(posedge s_axi_aclk);
        check("LDAC_N deasserted (=1)", {31'h0, ldac_n}, 32'h1);
        check("CLR_N deasserted (=1)",  {31'h0, clr_n},  32'h1);

        // =====================================================================
        // TC12: STATUS register – BUSY flag during SPI transfer
        // =====================================================================
        $display("\n[TC12] STATUS BUSY flag during SPI transaction");

        axi_write(REG_CH_SEL,  32'h0);
        axi_write(REG_DAC_DATA, 32'hBEEF);
        axi_write(REG_CMD, {28'h0, CMD_WRITE_N});

        // Read STATUS immediately after triggering
        @(posedge s_axi_aclk);
        @(posedge s_axi_aclk);
        axi_read(REG_STATUS, rdata);
        check("BUSY set during transfer", (rdata & 32'h1), 32'h1);

        // Wait for completion
        wait_spi_done();
        axi_read(REG_STATUS, rdata);
        check("BUSY clear after done",    (rdata & 32'h1), 32'h0);
        check("SPI_DONE set after done",  (rdata & 32'h2), 32'h2);

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n=============================================================");
        $display(" Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("=============================================================");

        if (fail_count == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" *** SOME TESTS FAILED ***");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Timeout watchdog (5 ms simulation limit)
    // -------------------------------------------------------------------------
    initial begin
        #5_000_000;
        $display("[WATCHDOG] Simulation timeout after 5ms");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Optional: VCD dump for waveform viewer
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("ltc2668_axi_tb.vcd");
        $dumpvars(0, ltc2668_axi_tb);
    end

endmodule
