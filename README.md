# ZCU104 VDMA Quadrant Splicer

Vivado block design for the ZCU104 HDMI base overlay with a custom `quadrant_switcher` HLS IP for flicker-free quadrant video switching.

## Requirements

- **Vivado 2024.2**
- **Vitis HLS 2024.2** — required to synthesize the `quadrant_switcher` IP before sourcing the block design TCL
- PYNQ ZCU104 board files installed

## IP Dependencies

The block design requires the following IPs. Standard Xilinx IPs will resolve automatically from the Vivado catalog. The custom/HLS IPs listed below must be present in your IP repository paths before sourcing the TCL.

### Custom / HLS IPs (must be built or added manually)
| IP | Source |
|----|--------|
| `xilinx.com:hls:quadrant_switcher:1.0` | Build from `src/hls/splicer.cpp` using Vitis HLS |
| `user.org:user:address_remap:1.0` | PYNQ boards IP repo |
| `xilinx.com:user:dff_en_reset_vector:1.0` | PYNQ boards IP repo |
| `xilinx.com:user:io_switch:1.1` | PYNQ boards IP repo |

### Standard Xilinx IPs (resolved automatically)
- `xilinx.com:ip:axi_intc:4.1`
- `xilinx.com:ip:axi_iic:2.1`
- `xilinx.com:ip:axi_gpio:2.0`
- `xilinx.com:ip:xlslice:1.0`
- `xilinx.com:ip:mdm:3.2`
- `xilinx.com:ip:util_ds_buf:2.2`
- `xilinx.com:ip:proc_sys_reset:5.0`
- `xilinx.com:ip:zynq_ultra_ps_e:3.5`
- `xilinx.com:ip:dfx_axi_shutdown_manager:1.0`
- `xilinx.com:ip:xlconstant:1.1`
- `xilinx.com:ip:xlconcat:2.1`
- `xilinx.com:ip:smartconnect:1.0`
- `xilinx.com:ip:microblaze:11.0`
- `xilinx.com:ip:axi_bram_ctrl:4.1`
- `xilinx.com:ip:axi_quad_spi:3.2`
- `xilinx.com:ip:axi_timer:2.0`
- `xilinx.com:ip:axi_vdma:6.3`
- `xilinx.com:ip:lmb_v10:3.0`
- `xilinx.com:ip:blk_mem_gen:8.4`
- `xilinx.com:ip:lmb_bram_if_cntlr:4.0`
- `xilinx.com:hls:color_convert_2:1.0`
- `xilinx.com:ip:v_hdmi_rx_ss:3.2`
- `xilinx.com:hls:pixel_pack_2:1.0`
- `xilinx.com:ip:axis_subset_converter:1.1`
- `xilinx.com:ip:axis_register_slice:1.1`
- `xilinx.com:ip:v_hdmi_tx_ss:3.2`
- `xilinx.com:hls:pixel_unpack_2:1.0`
- `xilinx.com:ip:vid_phy_controller:2.2`

## Build Instructions

### 1. Generate the quadrant_switcher HLS IP

Open Vitis HLS 2024.2 and create a project targeting part `xczu7ev-ffvc1156-2-e`. Add `src/hls/splicer.cpp` as the source and `src/hls/splicer_test.cpp` as the testbench. Use `src/hls/hls_config.cfg` for synthesis settings. Run C Synthesis and Export RTL as a Vivado IP. Note the path to the exported `ip` directory.

### 2. Clone the PYNQ repo for board IPs

The block design also depends on IPs from the PYNQ boards repository. The TCL expects them at `$origin_dir/PYNQ/boards/ip`. Clone it alongside this repo:

```bash
git clone https://github.com/Xilinx/PYNQ.git
```

### 3. Source the TCL in Vivado

Open Vivado 2024.2 and in the Tcl console:

```tcl
set origin_dir_loc /path/to/this/repo
source /path/to/this/repo/scripts/base.tcl
```

The TCL expects the HLS IP at `$origin_dir/../vitis_ws/splicer/splicer/hls/impl/ip`. Adjust `origin_dir_loc` or the IP repo path in the TCL if your directory layout differs.

## Repo Structure

```
splicer_proj_vivado/
├── scripts/
│   └── working_script.tcl          # Vivado project restore script
├── src/
│   
│     ├── splicer.sv        # quadrant_switcher sv source
│     ├── frame_assembler.sv        # quadrant_switcher sv source
│    
│    
└── README.md
```
