// =============================================================================
// ltc2668_example.c
// Usage examples for ltc2668_drv
// =============================================================================
#include <stdio.h>
#include "ltc2668_drv.h"

// ---------------------------------------------------------------------------
// Platform-specific memory map (bare-metal example)
// Replace with mmap() or your RTOS equivalent for Linux/Xenomai
// ---------------------------------------------------------------------------
#define LTC2668_BASE_ADDR   0x43C00000UL  // AXI peripheral base address

int main(void)
{
    ltc2668_dev_t dac;
    int ret;

    // 1. Initialize
    ret = ltc2668_init(&dac, LTC2668_BASE_ADDR);
    if (ret) { printf("Init failed\n"); return -1; }

    // 2. Set SPI clock: f_sck = 100MHz / (2*4) = 12.5 MHz
    ltc2668_set_clk_div(&dac, 4);

    // 3. Set ±10V span for all channels
    ret = ltc2668_set_span_all(&dac, LTC2668_SPAN_M10_TO_10V);
    if (ret) { printf("set_span_all failed\n"); return -1; }

    // 4. Output 2.5V on channel 0 (write + immediate update)
    uint16_t code = ltc2668_voltage_to_code(2.5f, LTC2668_SPAN_M10_TO_10V);
    printf("2.5V → code: 0x%04X\n", code);
    ret = ltc2668_write_update_ch(&dac, 0, code);
    if (ret) { printf("write_update_ch failed\n"); return -1; }

    // 5. Load input registers of ch1–ch3, then update all simultaneously
    ltc2668_write_ch(&dac, 1, ltc2668_voltage_to_code( 5.0f, LTC2668_SPAN_M10_TO_10V));
    ltc2668_write_ch(&dac, 2, ltc2668_voltage_to_code(-5.0f, LTC2668_SPAN_M10_TO_10V));
    ltc2668_write_ch(&dac, 3, ltc2668_voltage_to_code( 0.0f, LTC2668_SPAN_M10_TO_10V));
    ltc2668_update_all(&dac);  // simultaneous output update

    // 6. Set up toggle: ch0 and ch1 toggle between A and B registers
    //    (Write A value first, then configure toggle)
    ltc2668_set_toggle_sel(&dac, 0x0003);   // toggle ch0, ch1

    // 7. Power down unused channels (ch 4–15)
    for (int ch = 4; ch < 16; ch++) {
        ltc2668_power_down_ch(&dac, (uint8_t)ch);
    }

    // 8. Monitor ch0 via MUX output
    ltc2668_set_mux(&dac, LTC2668_MUX_CH(0));

    // 9. Code ↔ voltage conversion demo
    for (uint16_t c = 0; c <= 0xFFFF; c += 0x1000) {
        float v = ltc2668_code_to_voltage(c, LTC2668_SPAN_M10_TO_10V);
        printf("code=0x%04X → %.4f V\n", c, v);
    }

    printf("Done.\n");
    return 0;
}
