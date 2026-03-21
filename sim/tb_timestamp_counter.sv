// =============================================================================
// tb_timestamp_counter.sv
// timestamp_counter スタンドアロンテストベンチ
//
// Vivado AXI VIP 不要。AXI4-Lite 信号を直接ドライブ。
// ModelSim / Questa / VCS / Cadence Xcelium / Vivado XSIM で動作。
//
// DUT Parameters (テストベンチ側で一致させること):
//   CLK_FREQ_HZ = 100_000_000  (100 MHz)
//   NS_PER_TICK = 100          (100 ns/tick → PRESCALE_DEFAULT = 9)
//
// Test Cases:
//   TC1  : リセット後デフォルト値 (CTRL / STATUS / CNT / PRESCALE / NS_PER_TICK)
//   TC2  : START / STOP 制御
//   TC3  : RESET ビット (セルフクリア・カウンタ → 0)
//   TC4  : PRESCALE=0 高速カウント精度検証
//   TC5  : 64-bit CNT_LO / CNT_HI 連結値確認
//   TC6  : SNAP_LO / SNAP_HI アトミックスナップショット
//   TC7  : STATUS.RUNNING / STATUS.LATCHED フラグ
//   TC8  : STOP → START 再開 (カウンタ保持)
//   TC9  : NS_PER_TICK 読み出し専用レジスタ (書き込み無効確認)
//   TC10 : PRESCALE 変更後リセットでデフォルト値に復元
//   TC11 : overflow_pulse 短時間シミュレーション中に誤発生しないこと
// =============================================================================

`timescale 1ns / 1ps

module tb_timestamp_counter;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam integer AXI_ADDR_WIDTH = 8;
    localparam integer AXI_DATA_WIDTH = 32;
    localparam integer CLK_PERIOD     = 10;       // 10 ns = 100 MHz

    // DUT と一致させるパラメータ
    localparam longint CLK_FREQ_HZ   = 100_000_000;
    localparam longint NS_PER_TICK   = 100;       // 100 ns/tick

    // PRESCALE 期待デフォルト値
    localparam int PRESCALE_DEFAULT  =
        int'(NS_PER_TICK * CLK_FREQ_HZ / 1_000_000_000) - 1; // = 9

    // レジスタアドレス
    localparam [7:0] ADDR_CTRL        = 8'h00;
    localparam [7:0] ADDR_STATUS      = 8'h04;
    localparam [7:0] ADDR_CNT_LO      = 8'h08;
    localparam [7:0] ADDR_CNT_HI      = 8'h0C;
    localparam [7:0] ADDR_SNAP_LO     = 8'h10;
    localparam [7:0] ADDR_SNAP_HI     = 8'h14;
    localparam [7:0] ADDR_PRESCALE    = 8'h18;
    localparam [7:0] ADDR_NS_PER_TICK = 8'h1C;

    // CTRL ビット
    localparam [31:0] CTRL_START = 32'h1;
    localparam [31:0] CTRL_STOP  = 32'h2;
    localparam [31:0] CTRL_RESET = 32'h4;

    // STATUS ビット
    localparam [31:0] STAT_RUNNING = 32'h1;
    localparam [31:0] STAT_LATCHED = 32'h2;

    // =========================================================================
    // Clock / Reset
    // =========================================================================
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;

    always #(CLK_PERIOD / 2) aclk = ~aclk;

    // =========================================================================
    // AXI4-Lite Interface Signals
    // =========================================================================
    logic [7:0]  s_awaddr  = '0;
    logic        s_awvalid = 1'b0;
    logic        s_awready;

    logic [31:0] s_wdata   = '0;
    logic [3:0]  s_wstrb   = 4'h0;
    logic        s_wvalid  = 1'b0;
    logic        s_wready;

    logic [1:0]  s_bresp;
    logic        s_bvalid;
    logic        s_bready  = 1'b0;

    logic [7:0]  s_araddr  = '0;
    logic        s_arvalid = 1'b0;
    logic        s_arready;

    logic [31:0] s_rdata;
    logic [1:0]  s_rresp;
    logic        s_rvalid;
    logic        s_rready  = 1'b0;

    logic        overflow_pulse;

    // =========================================================================
    // DUT Instance
    // =========================================================================
    timestamp_counter #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .NS_PER_TICK    (NS_PER_TICK)
    ) dut (
        .s_axi_aclk    (aclk),
        .s_axi_aresetn (aresetn),
        .s_axi_awaddr  (s_awaddr),
        .s_axi_awvalid (s_awvalid),
        .s_axi_awready (s_awready),
        .s_axi_wdata   (s_wdata),
        .s_axi_wstrb   (s_wstrb),
        .s_axi_wvalid  (s_wvalid),
        .s_axi_wready  (s_wready),
        .s_axi_bresp   (s_bresp),
        .s_axi_bvalid  (s_bvalid),
        .s_axi_bready  (s_bready),
        .s_axi_araddr  (s_araddr),
        .s_axi_arvalid (s_arvalid),
        .s_axi_arready (s_arready),
        .s_axi_rdata   (s_rdata),
        .s_axi_rresp   (s_rresp),
        .s_axi_rvalid  (s_rvalid),
        .s_axi_rready  (s_rready),
        .overflow_pulse(overflow_pulse)
    );

    // =========================================================================
    // overflow_pulse カウンタ
    // =========================================================================
    int overflow_count = 0;
    always @(posedge aclk)
        if (overflow_pulse) overflow_count++;

    // =========================================================================
    // Test Utilities
    // =========================================================================
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check32(
        input string name,
        input [31:0] got,
        input [31:0] exp
    );
        if (got === exp)
            $display("  [PASS] %-46s  got=0x%08h", name, got);
        else
            $display("  [FAIL] %-46s  got=0x%08h  exp=0x%08h", name, got, exp);
        if (got === exp) pass_cnt++; else fail_cnt++;
    endtask

    task automatic check_nonzero32(input string name, input [31:0] got);
        if (got !== '0)
            $display("  [PASS] %-46s  got=0x%08h (non-zero)", name, got);
        else
            $display("  [FAIL] %-46s  expected non-zero, got=0", name);
        if (got !== '0) pass_cnt++; else fail_cnt++;
    endtask

    task automatic check_range(
        input string name,
        input int    got,
        input int    lo,
        input int    hi
    );
        if (got >= lo && got <= hi)
            $display("  [PASS] %-46s  got=%0d (in [%0d,%0d])", name, got, lo, hi);
        else
            $display("  [FAIL] %-46s  got=%0d  exp=[%0d,%0d]", name, got, lo, hi);
        if (got >= lo && got <= hi) pass_cnt++; else fail_cnt++;
    endtask

    task automatic check_int(input string name, input int got, input int exp);
        check32(name, 32'(got), 32'(exp));
    endtask

    // =========================================================================
    // AXI4-Lite Master Tasks
    // =========================================================================

    // ライトトランザクション
    // awaddr/wdata を同時にアサート → awready 待ち → wready 待ち → bvalid 待ち
    task automatic axil_write(
        input [7:0]  addr,
        input [31:0] data,
        input [3:0]  strb = 4'hF
    );
        // posedge 直後の安定タイミングで駆動
        @(posedge aclk); #1;
        s_awaddr  = addr;
        s_awvalid = 1'b1;
        s_wdata   = data;
        s_wstrb   = strb;
        s_wvalid  = 1'b1;

        // awready 待ち (DUT は awvalid アサートの次サイクルに 1 クロック幅でアサート)
        @(posedge aclk);
        while (!s_awready) @(posedge aclk);
        #1;
        s_awvalid = 1'b0;

        // wready 待ち (DUT は aw_active=1 かつ wvalid=1 のサイクルにアサート)
        @(posedge aclk);
        while (!s_wready) @(posedge aclk);
        #1;
        s_wvalid = 1'b0;
        s_wstrb  = 4'h0;

        // bvalid 待ち → bready でハンドシェイク
        s_bready = 1'b1;
        @(posedge aclk);
        while (!s_bvalid) @(posedge aclk);
        #1;
        s_bready = 1'b0;

        @(posedge aclk); // セトリングサイクル
    endtask

    // リードトランザクション
    task automatic axil_read(
        input  [7:0]  addr,
        output [31:0] data
    );
        @(posedge aclk); #1;
        s_araddr  = addr;
        s_arvalid = 1'b1;

        // arready 待ち (DUT は arvalid かつ !rvalid のサイクルにアサート)
        @(posedge aclk);
        while (!s_arready) @(posedge aclk);
        #1;
        s_arvalid = 1'b0;

        // rvalid 待ち → データ取得 → rready ハンドシェイク
        s_rready = 1'b1;
        @(posedge aclk);
        while (!s_rvalid) @(posedge aclk);
        data = s_rdata;
        #1;
        s_rready = 1'b0;

        @(posedge aclk); // セトリングサイクル
    endtask

    // 停止 & カウンタリセットのショートカット
    task automatic stop_and_reset();
        axil_write(ADDR_CTRL, CTRL_STOP);
        axil_write(ADDR_CTRL, CTRL_RESET);
        repeat(3) @(posedge aclk);
    endtask

    // =========================================================================
    // Main Test
    // =========================================================================
    logic [31:0] rdata;
    logic [63:0] cnt64, snap64;
    int          cnt_before, cnt_after;

    initial begin
        // ----- リセットシーケンス -----
        aresetn = 1'b0;
        repeat(10) @(posedge aclk);
        aresetn = 1'b1;
        repeat(5)  @(posedge aclk);

        $display("=================================================================");
        $display(" tb_timestamp_counter  (standalone, no VIP)");
        $display("=================================================================");
        $display(" CLK_FREQ_HZ  = %0d Hz", CLK_FREQ_HZ);
        $display(" NS_PER_TICK  = %0d ns", NS_PER_TICK);
        $display(" PRESCALE_DEF = %0d  (1 tick = %0d clock cycles)",
                 PRESCALE_DEFAULT, PRESCALE_DEFAULT + 1);
        $display("=================================================================");

        // =================================================================
        // TC1: リセット後デフォルト値
        // =================================================================
        $display("\n[TC1] Default register values after reset");

        axil_read(ADDR_CTRL,        rdata);
        check32("CTRL default (STOP=1)",       rdata, 32'h2);

        axil_read(ADDR_STATUS,      rdata);
        check32("STATUS default (all=0)",      rdata, 32'h0);

        axil_read(ADDR_CNT_LO,      rdata);
        check32("CNT_LO default = 0",          rdata, 32'h0);

        axil_read(ADDR_CNT_HI,      rdata);
        check32("CNT_HI default = 0",          rdata, 32'h0);

        axil_read(ADDR_PRESCALE,    rdata);
        check32("PRESCALE default = NS/CLK-1", rdata, 32'(PRESCALE_DEFAULT));

        axil_read(ADDR_NS_PER_TICK, rdata);
        check32("NS_PER_TICK = parameter",     rdata, 32'(NS_PER_TICK));

        // =================================================================
        // TC2: START / STOP 制御
        // =================================================================
        $display("\n[TC2] START / STOP control");

        // ---- カウント開始 ----
        axil_write(ADDR_CTRL, CTRL_START);
        repeat(3) @(posedge aclk);

        axil_read(ADDR_STATUS, rdata);
        check32("STATUS.RUNNING=1 after START",
                rdata & STAT_RUNNING, STAT_RUNNING);

        // PRESCALE_DEFAULT 設定で (PRESCALE_DEFAULT+1)*5 + 余裕 サイクル待つ
        repeat((PRESCALE_DEFAULT + 1) * 5 + 5) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata);
        check_nonzero32("CNT_LO increments after START", rdata);

        // ---- 停止 ----
        axil_write(ADDR_CTRL, CTRL_STOP);
        repeat(3) @(posedge aclk);

        axil_read(ADDR_STATUS, rdata);
        check32("STATUS.RUNNING=0 after STOP",
                rdata & STAT_RUNNING, 32'h0);

        // 停止後カウンタが変化しないことを確認
        axil_read(ADDR_CNT_LO, rdata); cnt_before = int'(rdata);
        repeat(20) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata); cnt_after  = int'(rdata);
        check_int("CNT_LO frozen after STOP", cnt_after, cnt_before);

        // =================================================================
        // TC3: RESET ビット (セルフクリア・カウンタ → 0)
        // =================================================================
        $display("\n[TC3] RESET bit (self-clear, counter → 0)");

        // カウンタを進める
        axil_write(ADDR_CTRL, CTRL_START);
        repeat((PRESCALE_DEFAULT + 1) * 10) @(posedge aclk);

        // RESET 発行
        axil_write(ADDR_CTRL, CTRL_RESET);
        repeat(4) @(posedge aclk);

        axil_read(ADDR_CNT_LO, rdata);
        check_range("CNT_LO near 0 after RESET (< 32)", int'(rdata), 0, 31);

        axil_read(ADDR_CNT_HI, rdata);
        check32("CNT_HI = 0 after RESET", rdata, 32'h0);

        // セルフクリア確認
        axil_read(ADDR_CTRL, rdata);
        check32("CTRL.RESET self-cleared", rdata & CTRL_RESET, 32'h0);

        // =================================================================
        // TC4: PRESCALE=0 高速カウント精度
        // =================================================================
        $display("\n[TC4] PRESCALE=0 (count every clock cycle)");

        stop_and_reset();

        axil_write(ADDR_PRESCALE, 32'h0);
        axil_read(ADDR_PRESCALE, rdata);
        check32("PRESCALE readback = 0", rdata, 32'h0);

        axil_write(ADDR_CTRL, CTRL_START);
        repeat(100) @(posedge aclk);
        axil_write(ADDR_CTRL, CTRL_STOP);
        repeat(2) @(posedge aclk);

        axil_read(ADDR_CNT_LO, rdata);
        // 100 クロックで 100 tick 期待 (AXI オーバーヘッド数クロック分を許容)
        check_range("PRESCALE=0: ~100 ticks in 100 clocks",
                    int'(rdata), 85, 105);

        // PRESCALE をデフォルトに戻す
        axil_write(ADDR_PRESCALE, 32'(PRESCALE_DEFAULT));

        // =================================================================
        // TC5: 64-bit CNT_LO / CNT_HI 連結値
        // =================================================================
        $display("\n[TC5] 64-bit CNT_LO/CNT_HI concatenation");

        stop_and_reset();

        axil_write(ADDR_CTRL, CTRL_START);
        // 十分な tick 数が溜まるまで待つ
        repeat((PRESCALE_DEFAULT + 1) * 20 + 10) @(posedge aclk);
        axil_write(ADDR_CTRL, CTRL_STOP);

        axil_read(ADDR_CNT_LO, rdata); cnt64[31:0]  = rdata;
        axil_read(ADDR_CNT_HI, rdata); cnt64[63:32] = rdata;

        check_nonzero32("CNT_LO non-zero after run", cnt64[31:0]);
        check32("CNT_HI = 0 (no 32-bit overflow yet)", cnt64[63:32], 32'h0);
        $display("  INFO: 64-bit counter = %0d ticks", cnt64);

        // =================================================================
        // TC6: アトミックスナップショット (SNAP_LO / SNAP_HI)
        // =================================================================
        $display("\n[TC6] Atomic snapshot SNAP_LO / SNAP_HI");

        stop_and_reset();

        axil_write(ADDR_CTRL, CTRL_START);
        repeat((PRESCALE_DEFAULT + 1) * 10 + 5) @(posedge aclk);

        // SNAP_LO 読み出しでアトミックラッチ
        axil_read(ADDR_SNAP_LO, rdata); snap64[31:0] = rdata;

        // STATUS.LATCHED = 1 を確認
        axil_read(ADDR_STATUS, rdata);
        check32("STATUS.LATCHED=1 after SNAP_LO read",
                rdata & STAT_LATCHED, STAT_LATCHED);

        // SNAP_HI 読み出し → 上位ワード + LATCHED クリア
        axil_read(ADDR_SNAP_HI, rdata); snap64[63:32] = rdata;

        axil_read(ADDR_STATUS, rdata);
        check32("STATUS.LATCHED=0 after SNAP_HI read",
                rdata & STAT_LATCHED, 32'h0);

        check_nonzero32("Snapshot LO non-zero", snap64[31:0]);
        $display("  INFO: snapshot = %0d ticks", snap64);

        // スナップショット中カウンタが動き続けていること
        axil_read(ADDR_CNT_LO, rdata);
        $display("  INFO: live CNT_LO at snap time vs now: snap=%0d live=%0d",
                 snap64[31:0], rdata);

        axil_write(ADDR_CTRL, CTRL_STOP);

        // =================================================================
        // TC7: STATUS フラグ (RUNNING / LATCHED)
        // =================================================================
        $display("\n[TC7] STATUS flags detail");

        // STOP 状態
        axil_write(ADDR_CTRL, CTRL_STOP);
        repeat(2) @(posedge aclk);
        axil_read(ADDR_STATUS, rdata);
        check32("STATUS.RUNNING=0 when stopped",    rdata & STAT_RUNNING, 32'h0);
        check32("STATUS.LATCHED=0 (cleared in TC6)", rdata & STAT_LATCHED, 32'h0);

        // START 後 RUNNING=1
        axil_write(ADDR_CTRL, CTRL_START);
        repeat(3) @(posedge aclk);
        axil_read(ADDR_STATUS, rdata);
        check32("STATUS.RUNNING=1 when running",    rdata & STAT_RUNNING, STAT_RUNNING);

        // SNAP_LO を読んで LATCHED=1
        axil_read(ADDR_SNAP_LO, rdata);
        axil_read(ADDR_STATUS,  rdata);
        check32("STATUS.LATCHED=1 after snap",       rdata & STAT_LATCHED, STAT_LATCHED);

        axil_write(ADDR_CTRL, CTRL_STOP);
        // SNAP_HI で LATCHED クリア
        axil_read(ADDR_SNAP_HI, rdata);
        axil_read(ADDR_STATUS,  rdata);
        check32("STATUS.LATCHED=0 after SNAP_HI",    rdata & STAT_LATCHED, 32'h0);

        // =================================================================
        // TC8: STOP → START 再開 (カウンタ保持)
        // =================================================================
        $display("\n[TC8] STOP -> START resume (counter preserved)");

        stop_and_reset();

        axil_write(ADDR_CTRL, CTRL_START);
        repeat((PRESCALE_DEFAULT + 1) * 8 + 5) @(posedge aclk);

        axil_write(ADDR_CTRL, CTRL_STOP);
        repeat(2) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata); cnt_before = int'(rdata);
        $display("  INFO: counter at STOP = %0d", cnt_before);

        // STOP 中は変化しない
        repeat(30) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata);
        check_int("Counter frozen during STOP", int'(rdata), cnt_before);

        // 再開後に増加する
        axil_write(ADDR_CTRL, CTRL_START);
        repeat((PRESCALE_DEFAULT + 1) * 5 + 5) @(posedge aclk);
        axil_read(ADDR_CNT_LO, rdata);
        if (int'(rdata) > cnt_before) begin
            $display("  [PASS] %-46s  was=%0d now=%0d",
                     "Counter resumes after re-START", cnt_before, int'(rdata));
            pass_cnt++;
        end else begin
            $display("  [FAIL] %-46s  was=%0d now=%0d",
                     "Counter resumes after re-START", cnt_before, int'(rdata));
            fail_cnt++;
        end

        axil_write(ADDR_CTRL, CTRL_STOP);

        // =================================================================
        // TC9: NS_PER_TICK 読み出し専用レジスタ
        // =================================================================
        $display("\n[TC9] NS_PER_TICK read-only register");

        axil_read(ADDR_NS_PER_TICK, rdata);
        check32("NS_PER_TICK = parameter value",    rdata, 32'(NS_PER_TICK));

        // 書き込んでも変化しない (RO)
        axil_write(ADDR_NS_PER_TICK, 32'hDEAD_BEEF);
        axil_read(ADDR_NS_PER_TICK, rdata);
        check32("NS_PER_TICK unchanged after write", rdata, 32'(NS_PER_TICK));

        $display("  INFO: effective resolution = %0d ns/tick  (PRESCALE=%0d)",
                 (PRESCALE_DEFAULT + 1) * 1_000_000_000 / int'(CLK_FREQ_HZ),
                 PRESCALE_DEFAULT);

        // =================================================================
        // TC10: PRESCALE 変更後リセットでデフォルト値に復元
        // =================================================================
        $display("\n[TC10] PRESCALE restored to default after reset");

        // PRESCALE を任意の値に書き換え
        axil_write(ADDR_PRESCALE, 32'hFF);
        axil_read(ADDR_PRESCALE, rdata);
        check32("PRESCALE written = 0xFF", rdata, 32'hFF);

        // リセット後にデフォルト値 (NS_PER_TICK 由来) に戻ること
        axil_write(ADDR_CTRL, CTRL_RESET);
        repeat(3) @(posedge aclk);
        axil_read(ADDR_PRESCALE, rdata);
        check32("PRESCALE restored = PRESCALE_DEFAULT after reset",
                rdata, 32'(PRESCALE_DEFAULT));

        // =================================================================
        // TC11: overflow_pulse 誤発生なし (短時間シミュレーション)
        // =================================================================
        $display("\n[TC11] No spurious overflow_pulse in short simulation");

        $display("  INFO: overflow_count = %0d (expected 0)", overflow_count);
        check_int("No overflow_pulse during test", overflow_count, 0);

        // =================================================================
        // Summary
        // =================================================================
        $display("\n=================================================================");
        $display(" Results: %0d PASSED,  %0d FAILED", pass_cnt, fail_cnt);
        $display("=================================================================");
        if (fail_cnt == 0)
            $display(" ALL TESTS PASSED");
        else
            $display(" *** SOME TESTS FAILED ***");

        $finish;
    end

    // =========================================================================
    // Watchdog (5 ms)
    // =========================================================================
    initial begin
        #5_000_000;
        $display("[WATCHDOG] Simulation timeout at 5 ms");
        $finish;
    end

    // =========================================================================
    // VCD Dump (--vcd オプション付きシミュレータで自動利用)
    // =========================================================================
    initial begin
        $dumpfile("tb_timestamp_counter.vcd");
        $dumpvars(0, tb_timestamp_counter);
    end

endmodule
