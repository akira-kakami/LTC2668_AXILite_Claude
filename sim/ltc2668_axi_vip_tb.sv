// =============================================================================
// ltc2668_axi_vip_tb.sv
// AXI VIP (Xilinx Verification IP) を使用したテストベンチ
// LTC2668 AXI4-Lite DAC Controller
//
// 前提:
//   - Vivado 2020.1 以降
//   - AXI VIP IP (axi_vip) を Master モードで設定したインスタンス名: axi_vip_mst_0
//     INTERFACE_MODE : MASTER
//     PROTOCOL       : AXI4LITE
//     DATA_WIDTH     : 32
//     ADDR_WIDTH     : 8
//   - create_vip_project.tcl で IP を生成すること
//
// Test Cases:
//   TC1  : Reset / デフォルト値確認
//   TC2  : SPI_CLK_DIV 書き込み・読み返し
//   TC3  : CMD_WRITE_N          – SPI フレーム検証
//   TC4  : CMD_WRITE_UPDATE_N   – SPI フレーム検証
//   TC5  : CMD_UPDATE_ALL       – SPI フレーム検証
//   TC6  : CMD_SPAN_N           – SPI フレーム検証
//   TC7  : CMD_SPAN_ALL         – SPI フレーム検証
//   TC8  : CMD_POWER_DOWN_N     – SPI フレーム検証
//   TC9  : CMD_TOGGLE_SEL       – SPI フレーム検証
//   TC10 : CMD_MUX_OUT          – SPI フレーム検証
//   TC11 : LDAC_N / CLR_N ハードウェア制御
//   TC12 : STATUS.BUSY / SPI_DONE フラグ確認
// =============================================================================

`timescale 1ns / 1ps

// AXI VIP パッケージ (Vivado によって自動生成)
import axi_vip_pkg::*;
import axi_vip_mst_0_pkg::*;

module ltc2668_axi_vip_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam integer AXI_ADDR_WIDTH      = 8;
    localparam integer AXI_DATA_WIDTH      = 32;
    localparam integer SPI_CLK_DIV_DEFAULT = 4;
    localparam integer CLK_PERIOD          = 10;  // 100 MHz

    // Register offsets
    localparam xil_axi_ulong REG_CTRL        = 8'h00;
    localparam xil_axi_ulong REG_CH_SEL      = 8'h04;
    localparam xil_axi_ulong REG_DAC_DATA    = 8'h08;
    localparam xil_axi_ulong REG_SPAN        = 8'h0C;
    localparam xil_axi_ulong REG_CMD         = 8'h10;
    localparam xil_axi_ulong REG_STATUS      = 8'h14;
    localparam xil_axi_ulong REG_SPI_CLK_DIV = 8'h18;
    localparam xil_axi_ulong REG_TOGGLE_SEL  = 8'h1C;
    localparam xil_axi_ulong REG_MUX_CTRL    = 8'h20;
    localparam xil_axi_ulong REG_GLOBAL_SPAN = 8'h24;

    // LTC2668 コマンドコード
    localparam logic [3:0] CMD_WRITE_N          = 4'h0;
    localparam logic [3:0] CMD_UPDATE_N         = 4'h1;
    localparam logic [3:0] CMD_WRITE_UPDATE_N   = 4'h3;
    localparam logic [3:0] CMD_POWER_DOWN_N     = 4'h4;
    localparam logic [3:0] CMD_POWER_DOWN_ALL   = 4'h5;
    localparam logic [3:0] CMD_SPAN_N           = 4'h6;
    localparam logic [3:0] CMD_SPAN_ALL         = 4'h7;
    localparam logic [3:0] CMD_UPDATE_ALL       = 4'h8;
    localparam logic [3:0] CMD_WRITE_UPDATE_ALL = 4'hA;
    localparam logic [3:0] CMD_MUX_OUT          = 4'hB;
    localparam logic [3:0] CMD_TOGGLE_SEL       = 4'hC;
    localparam logic [3:0] CMD_NOP              = 4'hF;

    // -------------------------------------------------------------------------
    // クロック / リセット
    // -------------------------------------------------------------------------
    logic aclk;
    logic aresetn;

    initial aclk = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // -------------------------------------------------------------------------
    // AXI4-Lite バス信号
    // -------------------------------------------------------------------------
    // Write Address Channel
    logic [AXI_ADDR_WIDTH-1:0] m_awaddr;
    logic [2:0]                m_awprot;
    logic                      m_awvalid;
    logic                      m_awready;
    // Write Data Channel
    logic [AXI_DATA_WIDTH-1:0] m_wdata;
    logic [3:0]                m_wstrb;
    logic                      m_wvalid;
    logic                      m_wready;
    // Write Response Channel
    logic [1:0]                m_bresp;
    logic                      m_bvalid;
    logic                      m_bready;
    // Read Address Channel
    logic [AXI_ADDR_WIDTH-1:0] m_araddr;
    logic [2:0]                m_arprot;
    logic                      m_arvalid;
    logic                      m_arready;
    // Read Data Channel
    logic [AXI_DATA_WIDTH-1:0] m_rdata;
    logic [1:0]                m_rresp;
    logic                      m_rvalid;
    logic                      m_rready;

    // -------------------------------------------------------------------------
    // SPI / 制御信号
    // -------------------------------------------------------------------------
    logic spi_sck;
    logic spi_sdi;
    logic spi_sdo;
    logic spi_cs_n;
    logic ldac_n;
    logic clr_n;

    assign spi_sdo = 1'b0;

    // -------------------------------------------------------------------------
    // AXI VIP インスタンス (Master モード)
    // ※ create_vip_project.tcl で生成された IP を使用
    // -------------------------------------------------------------------------
    axi_vip_mst_0 axi_vip_mst_inst (
        .aclk          (aclk),
        .aresetn       (aresetn),
        // Write Address
        .m_axi_awaddr  (m_awaddr),
        .m_axi_awprot  (m_awprot),
        .m_axi_awvalid (m_awvalid),
        .m_axi_awready (m_awready),
        // Write Data
        .m_axi_wdata   (m_wdata),
        .m_axi_wstrb   (m_wstrb),
        .m_axi_wvalid  (m_wvalid),
        .m_axi_wready  (m_wready),
        // Write Response
        .m_axi_bresp   (m_bresp),
        .m_axi_bvalid  (m_bvalid),
        .m_axi_bready  (m_bready),
        // Read Address
        .m_axi_araddr  (m_araddr),
        .m_axi_arprot  (m_arprot),
        .m_axi_arvalid (m_arvalid),
        .m_axi_arready (m_arready),
        // Read Data
        .m_axi_rdata   (m_rdata),
        .m_axi_rresp   (m_rresp),
        .m_axi_rvalid  (m_rvalid),
        .m_axi_rready  (m_rready)
    );

    // -------------------------------------------------------------------------
    // DUT インスタンス
    // -------------------------------------------------------------------------
    ltc2668_axi #(
        .AXI_ADDR_WIDTH      (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH      (AXI_DATA_WIDTH),
        .SPI_CLK_DIV_DEFAULT (SPI_CLK_DIV_DEFAULT)
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
        .spi_sck       (spi_sck),
        .spi_sdi       (spi_sdi),
        .spi_sdo       (spi_sdo),
        .spi_cs_n      (spi_cs_n),
        .ldac_n        (ldac_n),
        .clr_n         (clr_n)
    );

    // -------------------------------------------------------------------------
    // AXI VIP エージェント
    // -------------------------------------------------------------------------
    axi_vip_mst_0_mst_t mst_agent;

    // -------------------------------------------------------------------------
    // SPI フレームモニター
    // posedge spi_sck で 1 ビットずつキャプチャし、32 ビット揃ったら valid を上げる
    // -------------------------------------------------------------------------
    logic [31:0] spi_rx_frame;
    logic        spi_frame_valid;
    int          spi_bit_idx;

    always @(negedge spi_cs_n) begin
        spi_rx_frame    = 32'h0;
        spi_frame_valid = 1'b0;
        spi_bit_idx     = 31;
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
    // テスト結果カウンタ
    // -------------------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check(
        input string        name,
        input logic [63:0]  got,
        input logic [63:0]  exp
    );
        if (got === exp) begin
            $display("  [PASS] %s  got=0x%0h", name, got);
            pass_cnt++;
        end else begin
            $display("  [FAIL] %s  got=0x%0h  exp=0x%0h", name, got, exp);
            fail_cnt++;
        end
    endtask

    // -------------------------------------------------------------------------
    // VIP ラッパー: AXI4-Lite Write
    // -------------------------------------------------------------------------
    task automatic vip_write(
        input xil_axi_ulong           addr,
        input xil_axi_data_beat [0:0] data
    );
        xil_axi_resp_t resp;
        mst_agent.AXI4LITE_WRITE_BURST(addr, 3'b000, data, resp);
        if (resp !== XIL_AXI_RESP_OKAY)
            $display("  [WARN] Write to 0x%0h returned resp=%0b", addr, resp);
    endtask

    // -------------------------------------------------------------------------
    // VIP ラッパー: AXI4-Lite Read
    // -------------------------------------------------------------------------
    task automatic vip_read(
        input  xil_axi_ulong           addr,
        output xil_axi_data_beat [0:0] data
    );
        xil_axi_resp_t resp;
        mst_agent.AXI4LITE_READ_BURST(addr, 3'b000, data, resp);
        if (resp !== XIL_AXI_RESP_OKAY)
            $display("  [WARN] Read from 0x%0h returned resp=%0b", addr, resp);
    endtask

    // -------------------------------------------------------------------------
    // SPI 完了待ち (STATUS.BUSY ポーリング)
    // -------------------------------------------------------------------------
    task automatic wait_spi_done;
        xil_axi_data_beat [0:0] rdata;
        int timeout = 0;
        do begin
            vip_read(REG_STATUS, rdata);
            timeout++;
            if (timeout > 20000) begin
                $display("  [FAIL] wait_spi_done: timeout");
                fail_cnt++;
                return;
            end
        end while (rdata[0][0]);  // STATUS[0] = BUSY
    endtask

    // -------------------------------------------------------------------------
    // LTC2668 コマンド送信ヘルパー
    // -------------------------------------------------------------------------
    task automatic send_cmd(
        input logic [3:0]  cmd,
        input logic [3:0]  ch,
        input logic [15:0] dat,
        input logic [2:0]  span_val   = 3'h0,
        input logic [4:0]  mux_val    = 5'h0,
        input logic [15:0] toggle_val = 16'h0
    );
        xil_axi_data_beat [0:0] wdata;

        wdata[0] = {28'h0, ch};    vip_write(REG_CH_SEL,   wdata);
        wdata[0] = {16'h0, dat};   vip_write(REG_DAC_DATA, wdata);

        case (cmd)
            CMD_SPAN_N:     begin wdata[0] = {29'h0, span_val};   vip_write(REG_SPAN,        wdata); end
            CMD_SPAN_ALL:   begin wdata[0] = {29'h0, span_val};   vip_write(REG_GLOBAL_SPAN, wdata); end
            CMD_MUX_OUT:    begin wdata[0] = {27'h0, mux_val};    vip_write(REG_MUX_CTRL,    wdata); end
            CMD_TOGGLE_SEL: begin wdata[0] = {16'h0, toggle_val}; vip_write(REG_TOGGLE_SEL,  wdata); end
            default: ;
        endcase

        wdata[0] = {28'h0, cmd};
        vip_write(REG_CMD, wdata);
        wait_spi_done();
    endtask

    // =========================================================================
    // メインテスト
    // =========================================================================
    xil_axi_data_beat [0:0] rdata;
    logic [31:0]             rdata32;
    logic [31:0]             expected_frame;

    initial begin
        // ---- 初期化 ----
        aresetn = 1'b0;

        // VIP エージェント生成・起動
        mst_agent = new("mst_agent", axi_vip_mst_inst.inst.IF);
        mst_agent.start_master();

        repeat(10) @(posedge aclk);
        aresetn = 1'b1;
        repeat(5)  @(posedge aclk);

        $display("=============================================================");
        $display(" LTC2668 AXI VIP Testbench");
        $display("=============================================================");

        // =====================================================================
        // TC1: リセット後デフォルト値確認
        // =====================================================================
        $display("\n[TC1] Reset / Default register values");

        vip_read(REG_CTRL,        rdata); check("CTRL default",       rdata[0], 32'h0);
        vip_read(REG_CH_SEL,      rdata); check("CH_SEL default",     rdata[0], 32'h0);
        vip_read(REG_DAC_DATA,    rdata); check("DAC_DATA default",   rdata[0], 32'h0);
        vip_read(REG_SPAN,        rdata); check("SPAN default",       rdata[0], 32'h0);
        vip_read(REG_SPI_CLK_DIV, rdata); check("SPI_CLK_DIV default",rdata[0], 32'(SPI_CLK_DIV_DEFAULT));
        vip_read(REG_STATUS,      rdata); check("STATUS default",     rdata[0], 32'h0);
        vip_read(REG_TOGGLE_SEL,  rdata); check("TOGGLE_SEL default", rdata[0], 32'h0);
        vip_read(REG_MUX_CTRL,    rdata); check("MUX_CTRL default",   rdata[0], 32'h0);
        vip_read(REG_GLOBAL_SPAN, rdata); check("GLOBAL_SPAN default",rdata[0], 32'h0);

        // =====================================================================
        // TC2: SPI_CLK_DIV 書き込み・読み返し
        // =====================================================================
        $display("\n[TC2] SPI_CLK_DIV write/readback");
        begin
            xil_axi_data_beat [0:0] wdata;
            wdata[0] = 32'h0A;
            vip_write(REG_SPI_CLK_DIV, wdata);
            vip_read (REG_SPI_CLK_DIV, rdata);
            check("SPI_CLK_DIV=10", rdata[0], 32'hA);
            // 元に戻す
            wdata[0] = 32'(SPI_CLK_DIV_DEFAULT);
            vip_write(REG_SPI_CLK_DIV, wdata);
        end

        // =====================================================================
        // TC3: CMD_WRITE_N – CH5, DATA=0xABCD
        // =====================================================================
        $display("\n[TC3] CMD_WRITE_N (ch=5, data=0xABCD)");
        fork
            send_cmd(CMD_WRITE_N, 4'h5, 16'hABCD);
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_WRITE_N, 4'h5, 16'hABCD, 8'h00};
                check("TC3 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC4: CMD_WRITE_UPDATE_N – CH0, DATA=0x1234
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
        // TC5: CMD_UPDATE_ALL
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
        // TC6: CMD_SPAN_N – CH3, SPAN=2 (±5V)
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
        // TC7: CMD_SPAN_ALL – SPAN=3 (±10V)
        // =====================================================================
        $display("\n[TC7] CMD_SPAN_ALL (span=3)");
        fork
            begin
                xil_axi_data_beat [0:0] wdata;
                wdata[0] = 32'h3;
                vip_write(REG_GLOBAL_SPAN, wdata);
                wdata[0] = {28'h0, CMD_SPAN_ALL};
                vip_write(REG_CMD, wdata);
                wait_spi_done();
            end
            begin
                @(posedge spi_frame_valid);
                expected_frame = {CMD_SPAN_ALL, 4'hF, 13'b0, 3'h3, 8'h00};
                check("TC7 SPI frame", spi_rx_frame, expected_frame);
            end
        join

        // =====================================================================
        // TC8: CMD_POWER_DOWN_N – CH7
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
        // TC9: CMD_TOGGLE_SEL – mask=0xFF00
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
        // TC10: CMD_MUX_OUT – channel=0x1A
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
        begin
            xil_axi_data_beat [0:0] wdata;

            // LDAC_N アサート (CTRL[2]=1)
            wdata[0] = 32'h4;
            vip_write(REG_CTRL, wdata);
            repeat(3) @(posedge aclk);
            check("LDAC_N asserted (=0)", {63'h0, ldac_n}, 64'h0);
            check("CLR_N idle    (=1)",   {63'h0, clr_n},  64'h1);

            // CLR_N アサート (CTRL[3]=1)
            wdata[0] = 32'h8;
            vip_write(REG_CTRL, wdata);
            repeat(3) @(posedge aclk);
            check("LDAC_N idle    (=1)", {63'h0, ldac_n}, 64'h1);
            check("CLR_N asserted (=0)", {63'h0, clr_n},  64'h0);

            // 両方デアサート
            wdata[0] = 32'h0;
            vip_write(REG_CTRL, wdata);
            repeat(3) @(posedge aclk);
            check("LDAC_N deasserted (=1)", {63'h0, ldac_n}, 64'h1);
            check("CLR_N deasserted  (=1)", {63'h0, clr_n},  64'h1);
        end

        // =====================================================================
        // TC12: STATUS.BUSY / SPI_DONE フラグ
        // =====================================================================
        $display("\n[TC12] STATUS BUSY/SPI_DONE flags during SPI transaction");
        begin
            xil_axi_data_beat [0:0] wdata;

            wdata[0] = 32'h2;        vip_write(REG_CH_SEL,   wdata);
            wdata[0] = 32'hDEAD;     vip_write(REG_DAC_DATA, wdata);
            wdata[0] = {28'h0, CMD_WRITE_N};
            vip_write(REG_CMD, wdata);

            // 送信直後: BUSY=1 を確認
            @(posedge aclk); @(posedge aclk);
            vip_read(REG_STATUS, rdata);
            check("BUSY set during transfer",    (rdata[0] & 32'h1), 32'h1);

            // 完了後: BUSY=0, SPI_DONE=1 を確認
            wait_spi_done();
            vip_read(REG_STATUS, rdata);
            check("BUSY clear after done",       (rdata[0] & 32'h1), 32'h0);
            check("SPI_DONE set after done",     (rdata[0] & 32'h2), 32'h2);
        end

        // =====================================================================
        // 結果サマリー
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
    // タイムアウトウォッチドッグ (10 ms)
    // -------------------------------------------------------------------------
    initial begin
        #10_000_000;
        $display("[WATCHDOG] Simulation timeout after 10ms");
        $finish;
    end

    // -------------------------------------------------------------------------
    // VCD ダンプ (波形ビューア用)
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("ltc2668_axi_vip_tb.vcd");
        $dumpvars(0, ltc2668_axi_vip_tb);
    end

endmodule
