// =============================================================================
// ltc2668_axi.sv
// LTC2668 16-ch 16-bit DAC Controller with AXI4-Lite Interface
//
// Register Map (32-bit, word-addressed):
//   0x00  CTRL       [0]=GLOBAL_UPDATE [1]=SOFT_RESET
//   0x04  CH_SEL     [3:0] channel select (0-15)
//   0x08  DAC_DATA   [15:0] 16-bit DAC value
//   0x0C  SPAN       [2:0] span code per LTC2668 spec
//   0x10  CMD        [3:0] command: write/update/power-down etc.
//   0x14  STATUS     [0]=BUSY [1]=SPI_DONE (read-only)
//   0x18  SPI_CLK_DIV[7:0] SPI clock divider (default=4 → 25MHz @ 100MHz)
//   0x1C  TOGGLE_SEL [15:0] toggle select register
//   0x20  MUX_CTRL   [4:0] MUX output select
//   0x24  GLOBAL_SPAN[2:0] span for all channels
// =============================================================================

`timescale 1ns / 1ps

module ltc2668_axi #(
    parameter integer AXI_ADDR_WIDTH = 8,
    parameter integer AXI_DATA_WIDTH = 32,
    parameter integer SPI_CLK_DIV_DEFAULT = 4
)(
    // AXI4-Lite Slave Interface
    input  logic                      s_axi_aclk,
    input  logic                      s_axi_aresetn,

    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]                s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,

    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // LTC2668 SPI Interface
    output logic                      spi_sck,
    output logic                      spi_sdi,   // MOSI (to DAC)
    input  logic                      spi_sdo,   // MISO (from DAC, unused by LTC2668 but kept for completeness)
    output logic                      spi_cs_n,

    // Optional: hardware LDAC / CLR
    output logic                      ldac_n,
    output logic                      clr_n
);

    // -------------------------------------------------------------------------
    // Register File
    // -------------------------------------------------------------------------
    localparam REG_CTRL       = 8'h00;
    localparam REG_CH_SEL     = 8'h04;
    localparam REG_DAC_DATA   = 8'h08;
    localparam REG_SPAN       = 8'h0C;
    localparam REG_CMD        = 8'h10;
    localparam REG_STATUS     = 8'h14;
    localparam REG_SPI_DIV    = 8'h18;
    localparam REG_TOGGLE_SEL = 8'h1C;
    localparam REG_MUX_CTRL   = 8'h20;
    localparam REG_GLOBAL_SPAN= 8'h24;

    logic [31:0] reg_ctrl;
    logic [31:0] reg_ch_sel;
    logic [31:0] reg_dac_data;
    logic [31:0] reg_span;
    logic [31:0] reg_cmd;
    logic [31:0] reg_spi_div;
    logic [31:0] reg_toggle_sel;
    logic [31:0] reg_mux_ctrl;
    logic [31:0] reg_global_span;

    // -------------------------------------------------------------------------
    // LTC2668 Command Codes (Table 1 in datasheet)
    // -------------------------------------------------------------------------
    localparam CMD_WRITE_N          = 4'h0;
    localparam CMD_UPDATE_N         = 4'h1;
    localparam CMD_WRITE_UPDATE_N   = 4'h3;
    localparam CMD_POWER_DOWN_N     = 4'h4;
    localparam CMD_POWER_DOWN_ALL   = 4'h5;
    localparam CMD_SPAN_N           = 4'h6;
    localparam CMD_SPAN_ALL         = 4'h7;
    localparam CMD_UPDATE_ALL       = 4'h8; // Code 8 – global DAC update (all)
    localparam CMD_WRITE_UPDATE_ALL = 4'hA;
    localparam CMD_MUX_OUT          = 4'hB;
    localparam CMD_TOGGLE_SEL       = 4'hC;
    localparam CMD_GLOBAL_TOGGLE    = 4'hD;
    localparam CMD_NOP              = 4'hF;

    // -------------------------------------------------------------------------
    // AXI Write State Machine
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        WR_IDLE   = 2'd0,
        WR_DATA   = 2'd1,
        WR_RESP   = 2'd2
    } wr_state_t;

    wr_state_t wr_state;
    logic [AXI_ADDR_WIDTH-1:0] wr_addr_lat;
    logic [AXI_DATA_WIDTH-1:0] wr_data_lat;
    logic                       wr_trigger;  // pulse to start SPI transaction

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            wr_state      <= WR_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            wr_trigger    <= 1'b0;
            reg_ctrl       <= '0;
            reg_ch_sel     <= '0;
            reg_dac_data   <= '0;
            reg_span       <= '0;
            reg_cmd        <= '0;
            reg_spi_div    <= SPI_CLK_DIV_DEFAULT;
            reg_toggle_sel <= '0;
            reg_mux_ctrl   <= '0;
            reg_global_span<= '0;
        end else begin
            wr_trigger <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    s_axi_awready <= 1'b1;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr_lat   <= s_axi_awaddr;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WR_DATA;
                    end
                end
                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_data_lat  <= s_axi_wdata;
                        s_axi_wready <= 1'b0;
                        // Register write
                        case (wr_addr_lat[7:0])
                            REG_CTRL:        reg_ctrl        <= s_axi_wdata;
                            REG_CH_SEL:      reg_ch_sel      <= s_axi_wdata;
                            REG_DAC_DATA:    reg_dac_data    <= s_axi_wdata;
                            REG_SPAN:        reg_span        <= s_axi_wdata;
                            REG_CMD:         begin
                                reg_cmd  <= s_axi_wdata;
                                wr_trigger <= 1'b1;  // CMD write triggers SPI
                            end
                            REG_SPI_DIV:     reg_spi_div     <= s_axi_wdata;
                            REG_TOGGLE_SEL:  reg_toggle_sel  <= s_axi_wdata;
                            REG_MUX_CTRL:    reg_mux_ctrl    <= s_axi_wdata;
                            REG_GLOBAL_SPAN: reg_global_span <= s_axi_wdata;
                            default: ;
                        endcase
                        s_axi_bvalid <= 1'b1;
                        s_axi_bresp  <= 2'b00;
                        wr_state     <= WR_RESP;
                    end
                end
                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // AXI Read State Machine
    // -------------------------------------------------------------------------
    logic        spi_busy;
    logic        spi_done;

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= 2'b00;
        end else begin
            s_axi_arready <= 1'b1;
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                case (s_axi_araddr[7:0])
                    REG_CTRL:        s_axi_rdata <= reg_ctrl;
                    REG_CH_SEL:      s_axi_rdata <= reg_ch_sel;
                    REG_DAC_DATA:    s_axi_rdata <= reg_dac_data;
                    REG_SPAN:        s_axi_rdata <= reg_span;
                    REG_CMD:         s_axi_rdata <= reg_cmd;
                    REG_STATUS:      s_axi_rdata <= {30'b0, spi_done, spi_busy};
                    REG_SPI_DIV:     s_axi_rdata <= reg_spi_div;
                    REG_TOGGLE_SEL:  s_axi_rdata <= reg_toggle_sel;
                    REG_MUX_CTRL:    s_axi_rdata <= reg_mux_ctrl;
                    REG_GLOBAL_SPAN: s_axi_rdata <= reg_global_span;
                    default:         s_axi_rdata <= 32'hDEADBEEF;
                endcase
            end
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // SPI Master (Mode 1: CPOL=0, CPHA=1 – LTC2668 requires data on falling
    // edge of SCK, sampled on rising edge → CPOL=0 CPHA=0 actually,
    // but LTC2668 latches on rising SCK → standard SPI Mode 0)
    // Sends 32 bits: [31:28]=CMD [27:24]=ADDR [23:8]=DATA [7:0]=dont care
    // -------------------------------------------------------------------------
    logic [7:0]  spi_clk_cnt;
    logic [5:0]  spi_bit_cnt;     // 0..31
    logic [31:0] spi_shift_reg;
    logic        spi_clk_en;
    logic        sck_reg;

    typedef enum logic [2:0] {
        SPI_IDLE    = 3'd0,
        SPI_CS_LOW  = 3'd1,
        SPI_SHIFT   = 3'd2,
        SPI_CS_HIGH = 3'd3,
        SPI_DONE_ST = 3'd4
    } spi_state_t;

    spi_state_t spi_state;

    // Build 32-bit SPI word from registers
    // LTC2668 frame: CMD[3:0] | ADDR[3:0] | DATA[15:0] | X[7:0]
    function automatic logic [31:0] build_spi_word(
        input logic [3:0] cmd,
        input logic [3:0] addr,
        input logic [15:0] data
    );
        return {cmd, addr, data, 8'h00};
    endfunction

    logic [31:0] spi_word;
    always_comb begin
        case (reg_cmd[3:0])
            CMD_SPAN_ALL, CMD_UPDATE_ALL, CMD_WRITE_UPDATE_ALL,
            CMD_POWER_DOWN_ALL, CMD_GLOBAL_TOGGLE:
                spi_word = build_spi_word(reg_cmd[3:0], 4'hF,
                           (reg_cmd[3:0] == CMD_SPAN_ALL) ? {13'b0, reg_global_span[2:0]}
                           : 16'h0000);
            CMD_TOGGLE_SEL:
                spi_word = build_spi_word(CMD_TOGGLE_SEL, 4'hF, reg_toggle_sel[15:0]);
            CMD_MUX_OUT:
                spi_word = build_spi_word(CMD_MUX_OUT, 4'hF,
                           {11'b0, reg_mux_ctrl[4:0]});
            CMD_SPAN_N:
                spi_word = build_spi_word(CMD_SPAN_N, reg_ch_sel[3:0],
                           {13'b0, reg_span[2:0]});
            default:
                spi_word = build_spi_word(reg_cmd[3:0], reg_ch_sel[3:0],
                           reg_dac_data[15:0]);
        endcase
    end

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            spi_state    <= SPI_IDLE;
            spi_busy     <= 1'b0;
            spi_done     <= 1'b0;
            spi_cs_n     <= 1'b1;
            sck_reg      <= 1'b0;
            spi_sdi      <= 1'b0;
            spi_clk_cnt  <= '0;
            spi_bit_cnt  <= '0;
            spi_shift_reg<= '0;
            ldac_n       <= 1'b1;
            clr_n        <= 1'b1;
        end else begin
            spi_done <= 1'b0;

            // LDAC / CLR from CTRL register
            ldac_n <= ~reg_ctrl[2];
            clr_n  <= ~reg_ctrl[3];

            case (spi_state)
                SPI_IDLE: begin
                    spi_busy    <= 1'b0;
                    spi_cs_n    <= 1'b1;
                    sck_reg     <= 1'b0;
                    spi_clk_cnt <= '0;
                    if (wr_trigger && !spi_busy) begin
                        spi_shift_reg <= spi_word;
                        spi_bit_cnt   <= 6'd31;
                        spi_busy      <= 1'b1;
                        spi_state     <= SPI_CS_LOW;
                    end
                end

                SPI_CS_LOW: begin
                    spi_cs_n <= 1'b0;
                    spi_sdi  <= spi_word[31];  // pre-load MSB
                    spi_state<= SPI_SHIFT;
                    spi_clk_cnt <= '0;
                end

                SPI_SHIFT: begin
                    if (spi_clk_cnt == reg_spi_div[7:0] - 1) begin
                        spi_clk_cnt <= '0;
                        sck_reg     <= ~sck_reg;
                        if (sck_reg) begin
                            // Falling edge: shift out next bit
                            if (spi_bit_cnt == 0) begin
                                spi_state <= SPI_CS_HIGH;
                            end else begin
                                spi_bit_cnt  <= spi_bit_cnt - 1;
                                spi_shift_reg<= {spi_shift_reg[30:0], 1'b0};
                                spi_sdi      <= spi_shift_reg[30];
                            end
                        end
                    end else begin
                        spi_clk_cnt <= spi_clk_cnt + 1;
                    end
                end

                SPI_CS_HIGH: begin
                    // Wait for last SCK high
                    if (!sck_reg) begin
                        spi_cs_n  <= 1'b1;
                        spi_state <= SPI_DONE_ST;
                    end else begin
                        if (spi_clk_cnt == reg_spi_div[7:0] - 1) begin
                            spi_clk_cnt <= '0;
                            sck_reg     <= 1'b0;
                        end else begin
                            spi_clk_cnt <= spi_clk_cnt + 1;
                        end
                    end
                end

                SPI_DONE_ST: begin
                    spi_done  <= 1'b1;
                    spi_busy  <= 1'b0;
                    spi_state <= SPI_IDLE;
                end
            endcase
        end
    end

    assign spi_sck = sck_reg & ~spi_cs_n;  // gate clock when CS inactive

endmodule
