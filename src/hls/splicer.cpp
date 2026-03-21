// quadrant_switcher.cpp
#include <ap_int.h>

#define VDMA_MM2S_START_ADDR    (0x5C / 4)
#define VDMA_MM2S_FRMDLY_STRIDE (0x58 / 4)
#define VDMA_MM2S_HSIZE         (0x54 / 4)
#define VDMA_MM2S_VSIZE         (0x50 / 4)

void quadrant_switcher(
    ap_uint<1>  enable,
    ap_uint<1>  frame_done,
    ap_uint<32> base_addr,
    ap_uint<32> out_width,
    ap_uint<32> out_height,
    ap_uint<32> bpp,
    ap_uint<32> stride,
    volatile ap_uint<32> *vdma_regs,
    ap_uint<2>  &current_quadrant
) {
#pragma HLS INTERFACE ap_none   port=frame_done
#pragma HLS INTERFACE ap_none   port=enable
#pragma HLS INTERFACE s_axilite port=base_addr        bundle=ctrl
#pragma HLS INTERFACE s_axilite port=out_width        bundle=ctrl
#pragma HLS INTERFACE s_axilite port=out_height       bundle=ctrl
#pragma HLS INTERFACE s_axilite port=bpp              bundle=ctrl
#pragma HLS INTERFACE s_axilite port=stride           bundle=ctrl
#pragma HLS INTERFACE s_axilite port=current_quadrant bundle=ctrl
#pragma HLS INTERFACE m_axi     port=vdma_regs depth=32 offset=slave bundle=vdma
#pragma HLS INTERFACE s_axilite port=return           bundle=ctrl

    static ap_uint<2> quadrant = 0;
    static ap_uint<1> prev = 0;

    while (1) {
#pragma HLS PIPELINE II=1
        ap_uint<1> curr = frame_done;

        if (enable && curr && !prev) {
            quadrant = quadrant + 1;

            ap_uint<32> x_offset = (quadrant % 2) * out_width;
            ap_uint<32> y_offset = (quadrant / 2) * out_height;
            ap_uint<32> offset_bytes = y_offset * stride + x_offset * bpp;

            vdma_regs[VDMA_MM2S_START_ADDR]    = base_addr + offset_bytes;
            vdma_regs[VDMA_MM2S_FRMDLY_STRIDE] = stride;
            vdma_regs[VDMA_MM2S_HSIZE]         = out_width * bpp;
            vdma_regs[VDMA_MM2S_VSIZE]         = out_height;

            current_quadrant = quadrant;
        }

        prev = curr;
    }
}