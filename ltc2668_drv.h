// =============================================================================
// ltc2668_drv.h
// C Driver for LTC2668 16-ch 16-bit DAC via AXI4-Lite
// Xilinx SDK / Vitis (Xil_Out32 / Xil_In32) 対応版
// =============================================================================
#ifndef LTC2668_DRV_H
#define LTC2668_DRV_H

#include "xil_io.h"     /* Xil_Out32, Xil_In32, UINTPTR */
#include "xil_types.h"  /* u8, u16, u32 etc. */

// ---------------------------------------------------------------------------
// Register Offsets (byte address from base)
// ---------------------------------------------------------------------------
#define LTC2668_REG_CTRL        0x00
#define LTC2668_REG_CH_SEL      0x04
#define LTC2668_REG_DAC_DATA    0x08
#define LTC2668_REG_SPAN        0x0C
#define LTC2668_REG_CMD         0x10
#define LTC2668_REG_STATUS      0x14
#define LTC2668_REG_SPI_DIV     0x18
#define LTC2668_REG_TOGGLE_SEL  0x1C
#define LTC2668_REG_MUX_CTRL    0x20
#define LTC2668_REG_GLOBAL_SPAN 0x24

// CTRL register bits
#define LTC2668_CTRL_SOFT_RST   (1 << 1)
#define LTC2668_CTRL_LDAC_LOW   (1 << 2)   // assert hardware LDAC (active-low)
#define LTC2668_CTRL_CLR_LOW    (1 << 3)   // assert hardware CLR  (active-low)

// STATUS register bits
#define LTC2668_STATUS_BUSY     (1 << 0)
#define LTC2668_STATUS_SPI_DONE (1 << 1)

// ---------------------------------------------------------------------------
// LTC2668 Command Codes (matches datasheet Table 1)
// ---------------------------------------------------------------------------
typedef enum {
    LTC2668_CMD_WRITE_N          = 0x0,  // Write to input register N
    LTC2668_CMD_UPDATE_N         = 0x1,  // Update (LDAC) DAC register N
    LTC2668_CMD_WRITE_UPDATE_N   = 0x3,  // Write and update N
    LTC2668_CMD_POWER_DOWN_N     = 0x4,  // Power down channel N
    LTC2668_CMD_POWER_DOWN_ALL   = 0x5,  // Power down all channels
    LTC2668_CMD_SPAN_N           = 0x6,  // Set output span for N
    LTC2668_CMD_SPAN_ALL         = 0x7,  // Set output span for all
    LTC2668_CMD_UPDATE_ALL       = 0x8,  // Update all DAC registers
    LTC2668_CMD_WRITE_UPDATE_ALL = 0xA,  // Write and update all
    LTC2668_CMD_MUX_OUT          = 0xB,  // MUX output control
    LTC2668_CMD_TOGGLE_SEL       = 0xC,  // Toggle select
    LTC2668_CMD_GLOBAL_TOGGLE    = 0xD,  // Global toggle update
    LTC2668_CMD_NOP              = 0xF,  // No operation
} ltc2668_cmd_t;

// ---------------------------------------------------------------------------
// Output Span Codes (Table 2 in datasheet)
// ---------------------------------------------------------------------------
typedef enum {
    LTC2668_SPAN_0_TO_5V      = 0x0,  //  0 to  +5 V
    LTC2668_SPAN_0_TO_10V     = 0x1,  //  0 to +10 V
    LTC2668_SPAN_M5_TO_5V     = 0x2,  // -5 to  +5 V
    LTC2668_SPAN_M10_TO_10V   = 0x3,  // -10 to +10 V
    LTC2668_SPAN_M2P5_TO_2P5V = 0x4,  // -2.5 to +2.5 V
} ltc2668_span_t;

// ---------------------------------------------------------------------------
// MUX output select codes
// ---------------------------------------------------------------------------
#define LTC2668_MUX_CH(n)       ((n) & 0x0F)       // monitor DAC channel n
#define LTC2668_MUX_VREF        0x10                // monitor internal VREF

// ---------------------------------------------------------------------------
// Device context
// ---------------------------------------------------------------------------
typedef struct {
    UINTPTR base_addr;  // Base address of AXI peripheral (Xil_Out32 compatible)
} ltc2668_dev_t;

// ---------------------------------------------------------------------------
// API
// ---------------------------------------------------------------------------
#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Initialize device context and reset the IP core.
 */
int  ltc2668_init(ltc2668_dev_t *dev, UINTPTR base_addr);

/**
 * @brief Set SPI clock divider. f_sck = f_axi / (2 * div). Default div=4.
 */
void ltc2668_set_clk_div(ltc2668_dev_t *dev, u8 div);
int  ltc2668_wait_done(ltc2668_dev_t *dev);
int  ltc2668_write_ch(ltc2668_dev_t *dev, u8 ch, u16 code);
int  ltc2668_write_update_ch(ltc2668_dev_t *dev, u8 ch, u16 code);
int  ltc2668_update_ch(ltc2668_dev_t *dev, u8 ch);
int  ltc2668_update_all(ltc2668_dev_t *dev);
int  ltc2668_write_update_all(ltc2668_dev_t *dev, u16 code);
int  ltc2668_set_span_ch(ltc2668_dev_t *dev, u8 ch, ltc2668_span_t span);
int  ltc2668_set_span_all(ltc2668_dev_t *dev, ltc2668_span_t span);
int  ltc2668_power_down_ch(ltc2668_dev_t *dev, u8 ch);
int  ltc2668_power_down_all(ltc2668_dev_t *dev);
int  ltc2668_set_toggle_sel(ltc2668_dev_t *dev, u16 ch_mask);
int  ltc2668_global_toggle(ltc2668_dev_t *dev);
int  ltc2668_set_mux(ltc2668_dev_t *dev, u8 mux_sel);
u16  ltc2668_voltage_to_code(float voltage_v, ltc2668_span_t span);
float ltc2668_code_to_voltage(u16 code, ltc2668_span_t span);
int  ltc2668_nop(ltc2668_dev_t *dev);

#ifdef __cplusplus
}
#endif

#endif /* LTC2668_DRV_H */
