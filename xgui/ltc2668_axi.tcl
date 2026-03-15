# ==============================================================================
# ltc2668_axi.tcl
# Vivado IP Customization GUI for LTC2668 AXI DAC Controller
#
# This file is automatically loaded by Vivado when the IP is instantiated
# in the IP Integrator (Block Design) or the IP Catalog.
# ==============================================================================

# ------------------------------------------------------------------------------
# Procedure: init_gui
# Called once when the IP customization GUI is opened.
# ------------------------------------------------------------------------------
proc init_gui { IPINST } {

    ipgui::add_param $IPINST -name "Component_Name"

    # -------------------------------------------------------------------------
    # Page: Main Configuration
    # -------------------------------------------------------------------------
    set Page0 [ipgui::add_page $IPINST \
        -name "Page 0" \
        -display_name "Main Configuration"]

    # --- AXI Settings group ---
    set AXI_Group [ipgui::add_group $IPINST \
        -name "AXI Settings" \
        -parent ${Page0} \
        -display_name "AXI4-Lite Interface Settings"]

    ipgui::add_param $IPINST \
        -name "AXI_ADDR_WIDTH" \
        -parent ${AXI_Group} \
        -display_name "AXI Address Width (bits)" \
        -widget comboBox

    ipgui::add_param $IPINST \
        -name "AXI_DATA_WIDTH" \
        -parent ${AXI_Group} \
        -display_name "AXI Data Width (bits)" \
        -widget comboBox

    # --- SPI Settings group ---
    set SPI_Group [ipgui::add_group $IPINST \
        -name "SPI Settings" \
        -parent ${Page0} \
        -display_name "SPI Master Settings"]

    ipgui::add_param $IPINST \
        -name "SPI_CLK_DIV_DEFAULT" \
        -parent ${SPI_Group} \
        -display_name "SPI Clock Divider (default)" \
        -widget textEdit

    # SPI clock frequency note (read-only text)
    ipgui::add_static_text $IPINST \
        -name "spi_clk_note" \
        -parent ${SPI_Group} \
        -text "SPI clock = AXI clock / (2 x Divider)\nExample: 100 MHz / (2 x 4) = 12.5 MHz"

    # -------------------------------------------------------------------------
    # Page: Register Map
    # -------------------------------------------------------------------------
    set Page1 [ipgui::add_page $IPINST \
        -name "Page 1" \
        -display_name "Register Map"]

    ipgui::add_static_text $IPINST \
        -name "reg_map_text" \
        -parent ${Page1} \
        -text {Register Map (32-bit word-addressed):
  0x00  CTRL        [1]=SOFT_RESET [2]=LDAC_N [3]=CLR_N
  0x04  CH_SEL      [3:0] channel select (0-15)
  0x08  DAC_DATA    [15:0] 16-bit DAC code
  0x0C  SPAN        [2:0] span code (0=0-5V, 1=0-10V, 2=±5V, 3=±10V, 4=±2.5V)
  0x10  CMD         [3:0] command code (write triggers SPI)
  0x14  STATUS      [0]=BUSY [1]=SPI_DONE  (read-only)
  0x18  SPI_CLK_DIV [7:0] SPI clock divider
  0x1C  TOGGLE_SEL  [15:0] per-channel toggle select mask
  0x20  MUX_CTRL    [4:0] MUX output channel select
  0x24  GLOBAL_SPAN [2:0] span applied to all channels}
}


# ------------------------------------------------------------------------------
# Procedure: update_PARAM_VALUE.*
# Called when a parameter changes; used for cross-parameter validation.
# ------------------------------------------------------------------------------

proc update_PARAM_VALUE.AXI_ADDR_WIDTH { PARAM_VALUE.AXI_ADDR_WIDTH } {
    # No dependency – accept as-is
}

proc update_PARAM_VALUE.AXI_DATA_WIDTH { PARAM_VALUE.AXI_DATA_WIDTH } {
    # Fixed to 32 for AXI4-Lite compliance; no user action needed
}

proc update_PARAM_VALUE.SPI_CLK_DIV_DEFAULT { PARAM_VALUE.SPI_CLK_DIV_DEFAULT } {
    # Clamp to [2, 255] – enforced by component.xml min/max
}


# ------------------------------------------------------------------------------
# Procedure: validate_PARAM_VALUE.*
# Optional: return error/warning strings.
# ------------------------------------------------------------------------------

proc validate_PARAM_VALUE.SPI_CLK_DIV_DEFAULT { PARAM_VALUE.SPI_CLK_DIV_DEFAULT } {
    set val [get_property value ${PARAM_VALUE.SPI_CLK_DIV_DEFAULT}]
    if { $val < 2 } {
        return "ERROR: SPI_CLK_DIV_DEFAULT must be >= 2 to generate a valid SPI clock."
    }
    if { $val > 255 } {
        return "ERROR: SPI_CLK_DIV_DEFAULT must be <= 255 (8-bit divider register)."
    }
    return ""
}

proc validate_PARAM_VALUE.AXI_ADDR_WIDTH { PARAM_VALUE.AXI_ADDR_WIDTH } {
    set val [get_property value ${PARAM_VALUE.AXI_ADDR_WIDTH}]
    if { $val < 6 } {
        return "ERROR: AXI_ADDR_WIDTH must be >= 6 to address all 10 registers (0x00-0x24)."
    }
    return ""
}


# ------------------------------------------------------------------------------
# Procedure: update_MODELPARAM_VALUE.*
# Propagate GUI parameter values to the HDL module parameters.
# ------------------------------------------------------------------------------

proc update_MODELPARAM_VALUE.AXI_ADDR_WIDTH { MODELPARAM_VALUE.AXI_ADDR_WIDTH PARAM_VALUE.AXI_ADDR_WIDTH } {
    set_property value [get_property value ${PARAM_VALUE.AXI_ADDR_WIDTH}] \
        ${MODELPARAM_VALUE.AXI_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.AXI_DATA_WIDTH { MODELPARAM_VALUE.AXI_DATA_WIDTH PARAM_VALUE.AXI_DATA_WIDTH } {
    set_property value [get_property value ${PARAM_VALUE.AXI_DATA_WIDTH}] \
        ${MODELPARAM_VALUE.AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.SPI_CLK_DIV_DEFAULT { MODELPARAM_VALUE.SPI_CLK_DIV_DEFAULT PARAM_VALUE.SPI_CLK_DIV_DEFAULT } {
    set_property value [get_property value ${PARAM_VALUE.SPI_CLK_DIV_DEFAULT}] \
        ${MODELPARAM_VALUE.SPI_CLK_DIV_DEFAULT}
}
