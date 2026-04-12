# Copyright (C) 2022 Xilinx, Inc
# SPDX-License-Identifier: BSD-3-Clause

set_property PACKAGE_PIN M11 [get_ports reset]
set_property IOSTANDARD LVCMOS33 [get_ports reset]

set_false_path -from [get_clocks clk_pl_1] \
               -to   [get_pins base_i/quadrant_switcher_1/inst/fd_sync_reg[0]/D]

# Glasses sync outputs -- pmod1[4:7] pins repurposed for header[0:3]
set_property PACKAGE_PIN L10 [get_ports {header[0]}]
set_property PACKAGE_PIN M10 [get_ports {header[1]}]
set_property PACKAGE_PIN M8  [get_ports {header[2]}]
set_property PACKAGE_PIN M9  [get_ports {header[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {header[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {header[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {header[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {header[3]}]

# header[7:4] unused -- pmod1[0:3] pins
set_property PACKAGE_PIN J9 [get_ports {header[4]}]
set_property PACKAGE_PIN K9 [get_ports {header[5]}]
set_property PACKAGE_PIN K8 [get_ports {header[6]}]
set_property PACKAGE_PIN L8 [get_ports {header[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {header[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {header[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {header[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {header[7]}]


# HDMI RX
set_property PACKAGE_PIN R10 [get_ports HDMI_RX_CLK_P_IN]; #revB

set_property PACKAGE_PIN U10 [get_ports {DRU_CLK_IN_clk_p}]

set_property PACKAGE_PIN F6 [get_ports {RX_HPD_OUT}]
set_property IOSTANDARD LVCMOS33 [get_ports {RX_HPD_OUT}]

set_property PACKAGE_PIN D2 [get_ports RX_DDC_OUT_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports RX_DDC_OUT_scl_io]
set_property PULLUP true [get_ports RX_DDC_OUT_scl_io]

set_property PACKAGE_PIN E2 [get_ports RX_DDC_OUT_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports RX_DDC_OUT_sda_io]
set_property PULLUP true [get_ports RX_DDC_OUT_sda_io]

set_property PACKAGE_PIN F22 [get_ports RX_REFCLK_P_OUT]
set_property IOSTANDARD LVDS [get_ports RX_REFCLK_P_OUT]

set_property PACKAGE_PIN E5 [get_ports RX_DET_IN]
set_property IOSTANDARD LVCMOS33 [get_ports RX_DET_IN]

# HDMI TX
set_property PACKAGE_PIN T8 [get_ports TX_REFCLK_P_IN]

# rev B
set_property PACKAGE_PIN G21 [get_ports {HDMI_TX_CLK_P_OUT}]
set_property IOSTANDARD LVDS [get_ports {HDMI_TX_CLK_P_OUT}]

set_property PACKAGE_PIN E3 [get_ports TX_HPD_IN]
set_property IOSTANDARD LVCMOS33 [get_ports TX_HPD_IN]

set_property PACKAGE_PIN B1 [get_ports TX_DDC_OUT_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports TX_DDC_OUT_scl_io]

set_property PACKAGE_PIN C1 [get_ports TX_DDC_OUT_sda_io]
set_property IOSTANDARD LVCMOS33 [get_ports TX_DDC_OUT_sda_io]

# I2C
set_property IOSTANDARD LVCMOS33 [get_ports fmch_iic_scl_io]
set_property PACKAGE_PIN D1 [get_ports fmch_iic_scl_io]
set_property IOSTANDARD LVCMOS33 [get_ports fmch_iic_sda_io]
set_property PACKAGE_PIN E1 [get_ports fmch_iic_sda_io]

# GPIO_LED_0_LS
set_property PACKAGE_PIN M12 [get_ports IDT_8T49N241_RST_OUT]
set_property IOSTANDARD LVCMOS33 [get_ports IDT_8T49N241_RST_OUT]

set_property PACKAGE_PIN N11 [get_ports IDT_8T49N241_LOL_IN]
set_property IOSTANDARD LVCMOS33 [get_ports IDT_8T49N241_LOL_IN]

set_property PACKAGE_PIN A2 [get_ports TX_EN_OUT]
set_property IOSTANDARD LVCMOS33 [get_ports TX_EN_OUT]

set_property PACKAGE_PIN C2 [get_ports HDMI_RX_LS_OE]
set_property IOSTANDARD LVCMOS33 [get_ports HDMI_RX_LS_OE]

# Pmod0 -- all 8 bits
set_property PACKAGE_PIN G8 [get_ports {pmod0[0]}]
set_property PACKAGE_PIN H8 [get_ports {pmod0[1]}]
set_property PACKAGE_PIN G7 [get_ports {pmod0[2]}]
set_property PACKAGE_PIN H7 [get_ports {pmod0[3]}]
set_property PACKAGE_PIN G6 [get_ports {pmod0[4]}]
set_property PACKAGE_PIN H6 [get_ports {pmod0[5]}]
set_property PACKAGE_PIN J6 [get_ports {pmod0[6]}]
set_property PACKAGE_PIN J7 [get_ports {pmod0[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod0[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod0[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod0[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod0[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod0[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod0[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod0[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {pmod0[7]}]
set_property PULLUP true [get_ports {pmod0[2]}]
set_property PULLUP true [get_ports {pmod0[3]}]
set_property PULLUP true [get_ports {pmod0[6]}]
set_property PULLUP true [get_ports {pmod0[7]}]


set_property PACKAGE_PIN D5 [get_ports {leds[0]}]
set_property PACKAGE_PIN D6 [get_ports {leds[1]}]
set_property PACKAGE_PIN A5 [get_ports {leds[2]}]
set_property PACKAGE_PIN B5 [get_ports {leds[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {leds[3]}]

# DIP Switches
set_property PACKAGE_PIN E4 [get_ports {switches[0]}]
set_property PACKAGE_PIN D4 [get_ports {switches[1]}]
set_property PACKAGE_PIN F5 [get_ports {switches[2]}]
set_property PACKAGE_PIN F4 [get_ports {switches[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {switches[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {switches[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {switches[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {switches[3]}]
