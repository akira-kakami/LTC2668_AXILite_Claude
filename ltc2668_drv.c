// =============================================================================
// ltc2668_drv.c
// C Driver for LTC2668 16-ch 16-bit DAC via AXI4-Lite
// Xilinx SDK / Vitis (Xil_Out32 / Xil_In32) 対応版
// =============================================================================
#include "ltc2668_drv.h"
#include "sleep.h"      /* usleep */

// ---------------------------------------------------------------------------
// Low-level register access — Xil_Out32 / Xil_In32 ラッパー
// ---------------------------------------------------------------------------
static inline void reg_write(ltc2668_dev_t *dev, u32 offset, u32 val)
{
    Xil_Out32(dev->base_addr + offset, val);
}

static inline u32 reg_read(ltc2668_dev_t *dev, u32 offset)
{
    return Xil_In32(dev->base_addr + offset);
}

// ---------------------------------------------------------------------------
// Send a command — assemble registers, trigger SPI via CMD write
// ---------------------------------------------------------------------------
static int send_cmd(ltc2668_dev_t *dev,
                    ltc2668_cmd_t cmd,
                    u8             ch,
                    u16            data)
{
    reg_write(dev, LTC2668_REG_CH_SEL,   (u32)(ch   & 0x0F));
    reg_write(dev, LTC2668_REG_DAC_DATA, (u32)data);
    reg_write(dev, LTC2668_REG_CMD,      (u32)(cmd  & 0x0F)); // triggers SPI
    return ltc2668_wait_done(dev);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

int ltc2668_init(ltc2668_dev_t *dev, UINTPTR base_addr)
{
    if (!dev) return -1;
    dev->base_addr = base_addr;

    // Soft reset — 1us待機後に解除 (usleep は xil_io.h 環境で使用可能)
    reg_write(dev, LTC2668_REG_CTRL, LTC2668_CTRL_SOFT_RST);
    usleep(1);
    reg_write(dev, LTC2668_REG_CTRL, 0);

    // Default SPI clock divider
    reg_write(dev, LTC2668_REG_SPI_DIV, 4);

    // Send NOP to initialize SPI bus state
    return ltc2668_nop(dev);
}

void ltc2668_set_clk_div(ltc2668_dev_t *dev, u8 div)
{
    if (div < 1) div = 1;
    reg_write(dev, LTC2668_REG_SPI_DIV, (u32)div);
}

int ltc2668_wait_done(ltc2668_dev_t *dev)
{
    // Poll BUSY bit with timeout
    const int timeout = 100000;
    for (int i = 0; i < timeout; i++) {
        u32 status = reg_read(dev, LTC2668_REG_STATUS);
        if (!(status & LTC2668_STATUS_BUSY))
            return 0;
    }
    return -1; // timeout
}

int ltc2668_write_ch(ltc2668_dev_t *dev, u8 ch, u16 code)
{
    return send_cmd(dev, LTC2668_CMD_WRITE_N, ch, code);
}

int ltc2668_write_update_ch(ltc2668_dev_t *dev, u8 ch, u16 code)
{
    return send_cmd(dev, LTC2668_CMD_WRITE_UPDATE_N, ch, code);
}

int ltc2668_update_ch(ltc2668_dev_t *dev, u8 ch)
{
    return send_cmd(dev, LTC2668_CMD_UPDATE_N, ch, 0x0000);
}

int ltc2668_update_all(ltc2668_dev_t *dev)
{
    return send_cmd(dev, LTC2668_CMD_UPDATE_ALL, 0xF, 0x0000);
}

int ltc2668_write_update_all(ltc2668_dev_t *dev, u16 code)
{
    return send_cmd(dev, LTC2668_CMD_WRITE_UPDATE_ALL, 0xF, code);
}

int ltc2668_set_span_ch(ltc2668_dev_t *dev, u8 ch, ltc2668_span_t span)
{
    reg_write(dev, LTC2668_REG_SPAN, (u32)(span & 0x07));
    return send_cmd(dev, LTC2668_CMD_SPAN_N, ch, (u16)(span & 0x07));
}

int ltc2668_set_span_all(ltc2668_dev_t *dev, ltc2668_span_t span)
{
    reg_write(dev, LTC2668_REG_GLOBAL_SPAN, (u32)(span & 0x07));
    return send_cmd(dev, LTC2668_CMD_SPAN_ALL, 0xF, (u16)(span & 0x07));
}

int ltc2668_power_down_ch(ltc2668_dev_t *dev, u8 ch)
{
    return send_cmd(dev, LTC2668_CMD_POWER_DOWN_N, ch, 0x0000);
}

int ltc2668_power_down_all(ltc2668_dev_t *dev)
{
    return send_cmd(dev, LTC2668_CMD_POWER_DOWN_ALL, 0xF, 0x0000);
}

int ltc2668_set_toggle_sel(ltc2668_dev_t *dev, u16 ch_mask)
{
    reg_write(dev, LTC2668_REG_TOGGLE_SEL, (u32)ch_mask);
    return send_cmd(dev, LTC2668_CMD_TOGGLE_SEL, 0xF, ch_mask);
}

int ltc2668_global_toggle(ltc2668_dev_t *dev)
{
    return send_cmd(dev, LTC2668_CMD_GLOBAL_TOGGLE, 0xF, 0x0000);
}

int ltc2668_set_mux(ltc2668_dev_t *dev, u8 mux_sel)
{
    reg_write(dev, LTC2668_REG_MUX_CTRL, (u32)(mux_sel & 0x1F));
    return send_cmd(dev, LTC2668_CMD_MUX_OUT, 0xF, (u16)(mux_sel & 0x1F));
}

u16 ltc2668_voltage_to_code(float voltage_v, ltc2668_span_t span)
{
    float v_min, v_max;
    switch (span) {
        case LTC2668_SPAN_0_TO_5V:      v_min =   0.0f; v_max =  5.0f; break;
        case LTC2668_SPAN_0_TO_10V:     v_min =   0.0f; v_max = 10.0f; break;
        case LTC2668_SPAN_M5_TO_5V:     v_min =  -5.0f; v_max =  5.0f; break;
        case LTC2668_SPAN_M10_TO_10V:   v_min = -10.0f; v_max = 10.0f; break;
        case LTC2668_SPAN_M2P5_TO_2P5V: v_min =  -2.5f; v_max =  2.5f; break;
        default:                         v_min =   0.0f; v_max =  5.0f; break;
    }
    if (voltage_v < v_min) voltage_v = v_min;
    if (voltage_v > v_max) voltage_v = v_max;
    float norm = (voltage_v - v_min) / (v_max - v_min);
    return (u16)(norm * 65535.0f + 0.5f);
}

float ltc2668_code_to_voltage(u16 code, ltc2668_span_t span)
{
    float v_min, v_max;
    switch (span) {
        case LTC2668_SPAN_0_TO_5V:      v_min =   0.0f; v_max =  5.0f; break;
        case LTC2668_SPAN_0_TO_10V:     v_min =   0.0f; v_max = 10.0f; break;
        case LTC2668_SPAN_M5_TO_5V:     v_min =  -5.0f; v_max =  5.0f; break;
        case LTC2668_SPAN_M10_TO_10V:   v_min = -10.0f; v_max = 10.0f; break;
        case LTC2668_SPAN_M2P5_TO_2P5V: v_min =  -2.5f; v_max =  2.5f; break;
        default:                         v_min =   0.0f; v_max =  5.0f; break;
    }
    return v_min + (v_max - v_min) * ((float)code / 65535.0f);
}

int ltc2668_nop(ltc2668_dev_t *dev)
{
    return send_cmd(dev, LTC2668_CMD_NOP, 0xF, 0x0000);
}
