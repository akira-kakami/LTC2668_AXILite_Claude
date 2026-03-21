// =============================================================================
// timestamp_counter_tb.sv
// AXI VIP を使用した timestamp_counter テストベンチ
//
// 前提:
//   - Vivado 2020.1 以降
//   - AXI VIP インスタンス名: axi_vip_mst_0  (create_vip_project.tcl 参照)
//
// Test Cases:
//   TC1  : Reset 後のデフォルト値確認
//   TC2  : START / STOP 制御
//   TC3  : RESET ビット (セルフクリア, カウンタが 0 に戻ること)
//   TC4  : PRESCALE 設定によるカウント周期変更
//   TC5  : CNT_LO / CNT_HI 64-bit 連結値確認
//   TC6  : SNAP_LO/HI アトミックスナップショット
//   TC7  : STATUS.RUNNING / STATUS.LATCHED フラグ
//   TC8  : STOP → START 再開確認 (カウンタ保持)
//   TC9  : overflow_pulse モニタリング (PRESCALE=0 で高速オーバーフロー)
// =============================================================================

`timescale 1ns / 1ps

import axi_vip_pkg::*;
import axi_vip_mst_0_pkg::*;

module timestamp_counter_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam integer AXI_ADDR_WIDTH = 8;
    localparam integer AXI_DATA_WIDTH = 32;
    localparam integer CLK_PERIOD     = 10;   // 100 MHz

    // Register Addresses
    localparam xil_axi_ulong ADDR_CTRL     = 8'h00;
    localparam xil_axi_ulong ADDR_STATUS   = 8'h04;
    localparam xil_axi_ulong ADDR_CNT_LO   = 8'h08;
    localparam xil_axi_ulong ADDR_CNT_HI   = 8'h0C;
    localparam xil_axi_ulong ADDR_SNAP_LO  = 8'h10;
    localparam xil_axi_ulong ADDR_SNAP_HI  = 8'h14;
    localparam xil_axi_ulong ADDR_PRESCALE = 8'h18;

    // CTRL bit masks
    localparam logic [31:0] CTRL_START = 32'h1;
    localparam logic [31:0] CTRL_STOP  = 32'h2;
    localparam logic [31:0] CTRL_RESET = 32'h4;

    // STATUS bit masks
    localparam logic [31:0] STAT_RUNNING = 32'h1;
    localparam logic [31:0] STAT_LATCHED = 32'h2;

    // -------------------------------------------------------------------------
    // Clock / Reset
    // -------------------------------------------------------------------------
    logic aclk;
    logic aresetn;

    initial aclk = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // -------------------------------------------------------------------------
    // AXI4-Lite Bus Signals
    // -------------------------------------------------------------------------
    logic [AXI_ADDR_WIDTH-1:0] m_awaddr;
    logic [2:0]                m_awprot;
    logic                      m_awvalid;
    logic                      m_awready;
    logic [AXI_DATA_WIDTH-1:0] m_wdata;
    logic [3:0]                m_wstrb;
    logic                      m_wvalid;
    logic                      m_wready;
    logic [1:0]                m_bresp;
    logic                      m_bvalid;
    logic                      m_bready;
    logic [AXI_ADDR_WIDTH-1:0] m_araddr;
    logic [2:0]                m_arprot;
    logic                      m_arvalid;
    logic                      m_arready;
    logic [AXI_DATA_WIDTH-1:0] m_rdata;
    logic [1:0]                m_rresp;
    logic                      m_rvalid;
    logic                      m_rready;

    // -------------------------------------------------------------------------
    // Overflow pulse monitor
    // -------------------------------------------------------------------------
    logic       overflow_pulse;
    int         overflow_count = 0;
    always @(posedge aclk)
        if (overflow_pulse) overflow_count++;

    // -------------------------------------------------------------------------
    // AXI VIP Instance (Master)
    // -------------------------------------------------------------------------
    axi_vip_mst_0 axi_vip_mst_inst (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .m_axi_awaddr  (m_awaddr),
        .m_axi_awprot  (m_awprot),
        .m_axi_awvalid (m_awvalid),
        .m_axi_awready (m_awready),
        .m_axi_wdata   (m_wdata),
        .m_axi_wstrb   (m_wstrb),
        .m_axi_wvalid  (m_wvalid),
        .m_axi_wready  (m_wready),
        .m_axi_bresp   (m_bresp),
        .m_axi_bvalid  (m_bvalid),
        .m_axi_bready  (m_bready),
        .m_axi_araddr  (m_araddr),
        .m_axi_arprot  (m_arprot),
        .m_axi_arvalid (m_arvalid),
        .m_axi_arready (m_arready),
        .m_axi_rdata   (m_rdata),
        .m_axi_rresp   (m_rresp),
        .m_axi_rvalid  (m_rvalid),
        .m_axi_rready  (m_rready)
    );

    // -------------------------------------------------------------------------
    // DUT Instance
    // -------------------------------------------------------------------------
    timestamp_counter #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH)
    ) dut (
        .s_axi_aclk    (aclk),
        .s_axi_aresetn (aresetn),
        .s_axi_awaddr  (m_awaddr),
        .s_axi_awvalid (m_awvalid),
        .s_axi_awready (m_awready),
        .s_axi_wdata   (m_wdata),
        .s_axi_wstrb   (m_wstrb),
        .s_axi_wvalid  (m_wvalid),
        .s_axi_wready  (m_wready),
        .s_axi_bresp   (m_bresp),
        .s_axi_bvalid  (m_bvalid),
        .s_axi_bready  (m_bready),
        .s_axi_araddr  (m_araddr),
        .s_axi_arvalid (m_arvalid),
        .s_axi_arready (m_arready),
        .s_axi_rdata   (m_rdata),
        .s_axi_rresp   (m_rresp),
        .s_axi_rvalid  (m_rvalid),
        .s_axi_rready  (m_rready),
        .overflow_pulse(overflow_pulse)
    );

    // -------------------------------------------------------------------------
    // VIP Agent
    // -------------------------------------------------------------------------
    axi_vip_mst_0_mst_t mst_agent;

    // -------------------------------------------------------------------------
    // Test Utilities
    // -------------------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check(
        input string       name,
        input logic [63:0] got,
        input logic [63:0] exp
    );
        if (got === exp) begin
            $display("  [PASS] %-40s  got=0x%016h", name, got);
            pass_cnt++;
        end else begin
            $display("  [FAIL] %-40s  got=0x%016h  exp=0x%016h", name, got, exp);
            fail_cnt++;
        end
    endtask

    task automatic check_nonzero(
        input string       name,
        input logic [63:0] got
    );
        if (got !== '0) begin
            $display("  [PASS] %-40s  got=0x%016h (non-zero)", name, got);
            pass_cnt++;
        end else begin
            $display("  [FAIL] %-40s  expected non-zero, got=0x0", name);
            fail_cnt++;
        end
    endtask

    task automatic axil_write(
        input xil_axi_ulong           addr,
        input xil_axi_data_beat [0:0] data
    );
        xil_axi_resp_t resp;
        mst_agent.AXI4LITE_WRITE_BURST(addr, 3'b000, data, resp);
    endtask

    task automatic axil_read(
        input  xil_axi_ulong           addr,
        output xil_axi_data_beat [0:0] data
    );
        xil_axi_resp_t resp;
        mst_agent.AXI4LITE_READ_BURST(addr, 3'b000, data, resp);
    endtask

    // =========================================================================
    // Main Test
    // =========================================================================
    xil_axi_data_beat [0:0] wdata, rdata;
    logic [63:0] cnt64, snap64;
    int          cnt_before, cnt_after;

    initial begin
        // ---- 初期化 ----
        aresetn = 1'b0;
        mst_agent = new("mst_agent", axi_vip_mst_inst.inst.IF);
        mst_agent.start_master();
        repeat(10) @(posedge aclk);
        aresetn = 1'b1;
        repeat(5)  @(posedge aclk);

        $display("=============================================================");
        $display(" Timestamp Counter AXI VIP Testbench");
        $display("=============================================================");

        // =====================================================================
        // TC1: Reset 後デフォルト値
        // =====================================================================
        $display("\n[TC1] Default register values after reset");

        axil_read(ADDR_CTRL,     rdata); check("CTRL default",      rdata[0], 32'h2); // STOP=1
        axil_read(ADDR_STATUS,   rdata); check("STATUS default",    rdata[0], 32'h0);
        axil_read(ADDR_CNT_LO,   rdata); check("CNT_LO default",    rdata[0], 32'h0);
        axil_read(ADDR_CNT_HI,   rdata); check("CNT_HI default",    rdata[0], 32'h0);
        axil_read(ADDR_PRESCALE, rdata); check("PRESCALE default",  rdata[0], 32'h0);

        // =====================================================================
        // TC2: START / STOP 制御
        // =====================================================================
        $display("\n[TC2] START / STOP control");

        // カウント開始
        wdata[0] = CTRL_START;
        axil_write(ADDR_CTRL, wdata);
        repeat(2) @(posedge aclk);
        axil_read(ADDR_STATUS, rdata);
        check("STATUS.RUNNING after START", (rdata[0] & STAT_RUNNING), 32'h1);

        // 少し待ってカウンタが増えていることを確認
        repeat(20) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata);
        check_nonzero("CNT_LO increments after START", rdata[0]);

        // 停止
        wdata[0] = CTRL_STOP;
        axil_write(ADDR_CTRL, wdata);
        repeat(2) @(posedge aclk);
        axil_read(ADDR_STATUS, rdata);
        check("STATUS.RUNNING after STOP", (rdata[0] & STAT_RUNNING), 32'h0);

        // 停止後カウンタが増えないことを確認
        axil_read(ADDR_CNT_LO, rdata);
        cnt_before = int'(rdata[0]);
        repeat(20) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata);
        cnt_after = int'(rdata[0]);
        check("CNT_LO frozen after STOP",
              {32'h0, rdata[0]}, {32'h0, 32'(cnt_before)});

        // =====================================================================
        // TC3: RESET ビット (セルフクリア, カウンタ→0)
        // =====================================================================
        $display("\n[TC3] RESET bit (self-clear, counter → 0)");

        // まずカウントを進める
        wdata[0] = CTRL_START;
        axil_write(ADDR_CTRL, wdata);
        repeat(50) @(posedge aclk);

        // RESET 発行
        wdata[0] = CTRL_RESET;
        axil_write(ADDR_CTRL, wdata);
        repeat(3) @(posedge aclk);

        // カウンタが 0 付近であること
        axil_read(ADDR_CNT_LO, rdata);
        check("CNT_LO near 0 after RESET", (rdata[0] < 32'h10) ? 32'h1 : 32'h0, 32'h1);
        axil_read(ADDR_CNT_HI, rdata);
        check("CNT_HI = 0 after RESET", rdata[0], 32'h0);

        // CTRL.RESET セルフクリア確認
        axil_read(ADDR_CTRL, rdata);
        check("CTRL.RESET self-cleared", (rdata[0] & CTRL_RESET), 32'h0);

        // =====================================================================
        // TC4: PRESCALE 設定
        // =====================================================================
        $display("\n[TC4] PRESCALE setting (divide-by-N+1)");

        // 停止してリセット
        wdata[0] = CTRL_STOP;  axil_write(ADDR_CTRL, wdata);
        wdata[0] = CTRL_RESET; axil_write(ADDR_CTRL, wdata);
        repeat(3) @(posedge aclk);

        // PRESCALE=9 → 10 クロックに 1 カウント
        wdata[0] = 32'h9;
        axil_write(ADDR_PRESCALE, wdata);
        axil_read(ADDR_PRESCALE, rdata);
        check("PRESCALE readback = 9", rdata[0], 32'h9);

        wdata[0] = CTRL_START; axil_write(ADDR_CTRL, wdata);
        repeat(100) @(posedge aclk);   // 100 クロック → 約 10 カウント期待
        wdata[0] = CTRL_STOP;  axil_write(ADDR_CTRL, wdata);
        axil_read(ADDR_CNT_LO, rdata);
        begin
            int expected_min = 8;   // 若干のレイテンシを許容
            int expected_max = 12;
            int cnt_val = int'(rdata[0]);
            if (cnt_val >= expected_min && cnt_val <= expected_max) begin
                $display("  [PASS] %-40s  cnt=%0d (in [%0d,%0d])",
                         "PRESCALE=9 count in range", cnt_val, expected_min, expected_max);
                pass_cnt++;
            end else begin
                $display("  [FAIL] %-40s  cnt=%0d (exp [%0d,%0d])",
                         "PRESCALE=9 count in range", cnt_val, expected_min, expected_max);
                fail_cnt++;
            end
        end

        // PRESCALE をリセット
        wdata[0] = 32'h0; axil_write(ADDR_PRESCALE, wdata);

        // =====================================================================
        // TC5: CNT_LO / CNT_HI 64-bit 連結
        // =====================================================================
        $display("\n[TC5] 64-bit CNT_LO/CNT_HI concatenation");

        wdata[0] = CTRL_STOP;  axil_write(ADDR_CTRL, wdata);
        wdata[0] = CTRL_RESET; axil_write(ADDR_CTRL, wdata);
        repeat(3) @(posedge aclk);
        wdata[0] = CTRL_START; axil_write(ADDR_CTRL, wdata);
        repeat(200) @(posedge aclk);
        wdata[0] = CTRL_STOP;  axil_write(ADDR_CTRL, wdata);

        axil_read(ADDR_CNT_LO, rdata); cnt64[31:0]  = rdata[0];
        axil_read(ADDR_CNT_HI, rdata); cnt64[63:32] = rdata[0];
        check_nonzero("64-bit counter non-zero after run", cnt64);
        check("CNT_HI = 0 (no 32-bit overflow yet)", cnt64[63:32], 32'h0);
        $display("  INFO: 64-bit count value = %0d", cnt64);

        // =====================================================================
        // TC6: SNAP_LO/HI アトミックスナップショット
        // =====================================================================
        $display("\n[TC6] Atomic snapshot SNAP_LO / SNAP_HI");

        wdata[0] = CTRL_STOP;  axil_write(ADDR_CTRL, wdata);
        wdata[0] = CTRL_RESET; axil_write(ADDR_CTRL, wdata);
        repeat(3) @(posedge aclk);
        wdata[0] = CTRL_START; axil_write(ADDR_CTRL, wdata);
        repeat(100) @(posedge aclk);

        // SNAP_LO 読み出しでアトミックラッチ
        axil_read(ADDR_SNAP_LO, rdata);
        snap64[31:0]  = rdata[0];

        // STATUS.LATCHED 確認
        axil_read(ADDR_STATUS, rdata);
        check("STATUS.LATCHED after SNAP_LO read", (rdata[0] & STAT_LATCHED), STAT_LATCHED);

        // SNAP_HI 読み出し (上位ワード取得 + LATCHED クリア)
        axil_read(ADDR_SNAP_HI, rdata);
        snap64[63:32] = rdata[0];
        axil_read(ADDR_STATUS, rdata);
        check("STATUS.LATCHED cleared after SNAP_HI read", (rdata[0] & STAT_LATCHED), 32'h0);

        check_nonzero("Snapshot value non-zero", snap64);
        $display("  INFO: snapshot = %0d", snap64);

        // =====================================================================
        // TC7: STATUS.RUNNING / STATUS.LATCHED フラグ
        // =====================================================================
        $display("\n[TC7] STATUS flags (RUNNING / LATCHED)");

        // 停止状態
        wdata[0] = CTRL_STOP; axil_write(ADDR_CTRL, wdata);
        repeat(2) @(posedge aclk);
        axil_read(ADDR_STATUS, rdata);
        check("STATUS.RUNNING=0 when stopped",   (rdata[0] & STAT_RUNNING), 32'h0);
        check("STATUS.LATCHED=0 (cleared at TC6)",(rdata[0] & STAT_LATCHED), 32'h0);

        // 開始状態
        wdata[0] = CTRL_START; axil_write(ADDR_CTRL, wdata);
        repeat(3) @(posedge aclk);
        axil_read(ADDR_STATUS, rdata);
        check("STATUS.RUNNING=1 when running",   (rdata[0] & STAT_RUNNING), STAT_RUNNING);

        wdata[0] = CTRL_STOP; axil_write(ADDR_CTRL, wdata);

        // =====================================================================
        // TC8: STOP → START 再開 (カウンタ保持)
        // =====================================================================
        $display("\n[TC8] STOP -> START resume (counter preserved)");

        wdata[0] = CTRL_STOP;  axil_write(ADDR_CTRL, wdata);
        wdata[0] = CTRL_RESET; axil_write(ADDR_CTRL, wdata);
        repeat(3) @(posedge aclk);
        wdata[0] = CTRL_START; axil_write(ADDR_CTRL, wdata);
        repeat(50) @(posedge aclk);

        // 停止してカウンタ値を記録
        wdata[0] = CTRL_STOP; axil_write(ADDR_CTRL, wdata);
        repeat(2) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata);
        cnt_before = int'(rdata[0]);

        // 少し待ってもカウンタが変わらない
        repeat(30) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata);
        check("Counter frozen during STOP",
              {32'h0, rdata[0]}, {32'h0, 32'(cnt_before)});

        // 再開後カウンタが増える
        wdata[0] = CTRL_START; axil_write(ADDR_CTRL, wdata);
        repeat(30) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata);
        if (int'(rdata[0]) > cnt_before) begin
            $display("  [PASS] %-40s  was=%0d now=%0d",
                     "Counter resumes after re-START", cnt_before, int'(rdata[0]));
            pass_cnt++;
        end else begin
            $display("  [FAIL] %-40s  was=%0d now=%0d",
                     "Counter resumes after re-START", cnt_before, int'(rdata[0]));
            fail_cnt++;
        end

        wdata[0] = CTRL_STOP; axil_write(ADDR_CTRL, wdata);

        // =====================================================================
        // TC9: overflow_pulse (PRESCALE=0, 64-bit で 2^32 超え)
        // =====================================================================
        $display("\n[TC9] overflow_pulse monitoring (fast counter)");

        // 64-bit カウンタが 0xFFFFFFFF を超えるにはクロックが膨大に必要なため、
        // RTL 初期値を書き換えず, overflow_count が 0 のままであることを確認
        // (実機検証ではより長い実行時間が必要)
        $display("  INFO: overflow_count so far = %0d (expected 0 in short sim)", overflow_count);
        check("No spurious overflow during test", overflow_count, 0);

        // =====================================================================
        // Summary
        // =====================================================================
        $display("\n=============================================================");
        $display(" Results: %0d PASSED, %0d FAILED", pass_cnt, fail_cnt);
        $display("=============================================================");
        if (fail_cnt == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" *** SOME TESTS FAILED ***");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Watchdog (5 ms)
    // -------------------------------------------------------------------------
    initial begin
        #5_000_000;
        $display("[WATCHDOG] Simulation timeout after 5ms");
        $finish;
    end

    // -------------------------------------------------------------------------
    // VCD Dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("timestamp_counter_tb.vcd");
        $dumpvars(0, timestamp_counter_tb);
    end

endmodule
