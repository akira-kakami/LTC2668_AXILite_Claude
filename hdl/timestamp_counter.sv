// =============================================================================
// timestamp_counter.sv
// 64-bit Timestamp Counter with AXI4-Lite Interface
//
// Register Map (AXI_ADDR_WIDTH=8, 32-bit registers, word-addressed):
//
//   0x00  CTRL (W/R)
//           [0] START  : 1 = カウント開始 (STOP=0 の間は保持)
//           [1] STOP   : 1 = カウント停止 (START より優先)
//           [2] RESET  : 1 = カウンタを 0 にリセット (セルフクリア)
//   0x04  STATUS (RO)
//           [0] RUNNING : 1 = カウント中
//           [1] LATCHED : 1 = スナップショット取得済み (SNAP_LO 読み出しでクリア)
//   0x08  CNT_LO (RO) : カウンタ下位 32-bit (ライブ値)
//   0x0C  CNT_HI (RO) : カウンタ上位 32-bit (ライブ値)
//   0x10  SNAP_LO (RO): スナップショット下位 32-bit
//                        読み出しトリガ: CNT_LO/CNT_HI をアトミックにラッチ
//   0x14  SNAP_HI (RO): スナップショット上位 32-bit
//   0x18  PRESCALE (W/R): [31:0] クロック分周値 (0=毎クロック, N=N+1 クロックに1カウント)
//
// 動作概要:
//   - CTRL.START=1 を書くとカウント開始
//   - CTRL.STOP=1  を書くとカウント停止
//   - CTRL.RESET=1 を書くとカウンタを 0 に同期リセット (START/STOP 状態は保持)
//   - SNAP_LO を読むと 64-bit カウンタをアトミックにラッチし STATUS.LATCHED=1 をセット
//   - SNAP_HI を読むと STATUS.LATCHED をクリア
//   - aresetn = 0 で全レジスタを初期化
// =============================================================================

`timescale 1ns / 1ps

module timestamp_counter #(
    parameter integer AXI_ADDR_WIDTH = 8,
    parameter integer AXI_DATA_WIDTH = 32
)(
    // AXI4-Lite Slave Interface
    input  logic                      s_axi_aclk,
    input  logic                      s_axi_aresetn,

    // Write Address Channel
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    // Write Data Channel
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]                s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,

    // Write Response Channel
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    // Read Address Channel
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    // Read Data Channel
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // Optional external pulse output (1 クロック幅, オーバーフロー時)
    output logic                      overflow_pulse
);

    // -------------------------------------------------------------------------
    // Register Addresses
    // -------------------------------------------------------------------------
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CTRL     = 8'h00;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_STATUS   = 8'h04;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CNT_LO   = 8'h08;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_CNT_HI   = 8'h0C;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_SNAP_LO  = 8'h10;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_SNAP_HI  = 8'h14;
    localparam logic [AXI_ADDR_WIDTH-1:0] ADDR_PRESCALE = 8'h18;

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    logic        reg_start;        // CTRL[0]
    logic        reg_stop;         // CTRL[1]
    logic        reg_reset_req;    // CTRL[2] セルフクリア
    logic [31:0] reg_prescale;     // PRESCALE

    logic        stat_running;     // STATUS[0]
    logic        stat_latched;     // STATUS[1]

    logic [63:0] counter;          // 64-bit メインカウンタ
    logic [63:0] snapshot;         // アトミックスナップショット
    logic [31:0] prescale_cnt;     // 分周カウンタ

    // -------------------------------------------------------------------------
    // AXI Handshake State
    // -------------------------------------------------------------------------
    logic [AXI_ADDR_WIDTH-1:0] aw_addr_latch;
    logic                      aw_active;
    logic [AXI_ADDR_WIDTH-1:0] ar_addr_latch;

    // =========================================================================
    // AXI4-Lite Write Logic
    // =========================================================================

    // --- Write Address Handshake ---
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_awready <= 1'b0;
            aw_addr_latch <= '0;
            aw_active     <= 1'b0;
        end else begin
            if (s_axi_awvalid && !aw_active) begin
                s_axi_awready <= 1'b1;
                aw_addr_latch <= s_axi_awaddr;
                aw_active     <= 1'b1;
            end else begin
                s_axi_awready <= 1'b0;
            end
        end
    end

    // --- Write Data Handshake & Register Update ---
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            aw_active      <= 1'b0;
            reg_start      <= 1'b0;
            reg_stop       <= 1'b1;   // 初期状態: 停止
            reg_reset_req  <= 1'b0;
            reg_prescale   <= 32'h0;
        end else begin
            // セルフクリアビット
            reg_reset_req <= 1'b0;

            s_axi_wready <= 1'b0;

            if (s_axi_wvalid && aw_active) begin
                s_axi_wready <= 1'b1;
                aw_active    <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;

                case (aw_addr_latch)
                    ADDR_CTRL: begin
                        if (s_axi_wstrb[0]) begin
                            if (s_axi_wdata[1]) begin
                                // STOP 優先
                                reg_stop  <= 1'b1;
                                reg_start <= 1'b0;
                            end else if (s_axi_wdata[0]) begin
                                reg_start <= 1'b1;
                                reg_stop  <= 1'b0;
                            end
                            reg_reset_req <= s_axi_wdata[2];
                        end
                    end
                    ADDR_PRESCALE: begin
                        if (s_axi_wstrb[0]) reg_prescale[ 7: 0] <= s_axi_wdata[ 7: 0];
                        if (s_axi_wstrb[1]) reg_prescale[15: 8] <= s_axi_wdata[15: 8];
                        if (s_axi_wstrb[2]) reg_prescale[23:16] <= s_axi_wdata[23:16];
                        if (s_axi_wstrb[3]) reg_prescale[31:24] <= s_axi_wdata[31:24];
                    end
                    default: ; // RO レジスタへの書き込みは無視 (OKAY 返却)
                endcase
            end

            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    // =========================================================================
    // 64-bit Counter Logic
    // =========================================================================
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            counter       <= 64'h0;
            prescale_cnt  <= 32'h0;
            stat_running  <= 1'b0;
            overflow_pulse<= 1'b0;
        end else begin
            overflow_pulse <= 1'b0;

            // RESET はカウンタをゼロに (START/STOP 状態保持)
            if (reg_reset_req) begin
                counter      <= 64'h0;
                prescale_cnt <= 32'h0;
            end

            // 動作状態更新
            if (reg_start && !reg_stop)
                stat_running <= 1'b1;
            else if (reg_stop)
                stat_running <= 1'b0;

            // カウントアップ
            if (stat_running && !reg_reset_req) begin
                if (prescale_cnt == reg_prescale) begin
                    prescale_cnt <= 32'h0;
                    if (counter == 64'hFFFF_FFFF_FFFF_FFFF) begin
                        counter        <= 64'h0;
                        overflow_pulse <= 1'b1;
                    end else begin
                        counter <= counter + 1'b1;
                    end
                end else begin
                    prescale_cnt <= prescale_cnt + 1'b1;
                end
            end
        end
    end

    // =========================================================================
    // Snapshot Logic (アトミックラッチ)
    // SNAP_LO 読み出しで 64-bit をラッチ, SNAP_HI 読み出しで LATCHED クリア
    // =========================================================================
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            snapshot    <= 64'h0;
            stat_latched<= 1'b0;
        end else begin
            // SNAP_LO リードアクセスでスナップショット取得
            if (s_axi_arvalid && (s_axi_araddr == ADDR_SNAP_LO)) begin
                snapshot     <= counter;
                stat_latched <= 1'b1;
            end
            // SNAP_HI リードアクセスで LATCHED クリア
            if (s_axi_arvalid && (s_axi_araddr == ADDR_SNAP_HI)) begin
                stat_latched <= 1'b0;
            end
        end
    end

    // =========================================================================
    // AXI4-Lite Read Logic
    // =========================================================================
    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'h0;
            s_axi_rresp   <= 2'b00;
            ar_addr_latch <= '0;
        end else begin
            s_axi_arready <= 1'b0;

            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                ar_addr_latch <= s_axi_araddr;

                case (s_axi_araddr)
                    ADDR_CTRL    : s_axi_rdata <= {29'h0, reg_reset_req, reg_stop, reg_start};
                    ADDR_STATUS  : s_axi_rdata <= {30'h0, stat_latched, stat_running};
                    ADDR_CNT_LO  : s_axi_rdata <= counter[31:0];
                    ADDR_CNT_HI  : s_axi_rdata <= counter[63:32];
                    ADDR_SNAP_LO : s_axi_rdata <= counter[31:0];    // ラッチトリガ (上記 always_ff 参照)
                    ADDR_SNAP_HI : s_axi_rdata <= snapshot[63:32];  // ラッチ済み上位ワード
                    ADDR_PRESCALE: s_axi_rdata <= reg_prescale;
                    default      : s_axi_rdata <= 32'hDEAD_BEEF;
                endcase
            end

            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end

endmodule
