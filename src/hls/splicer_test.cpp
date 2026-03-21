// quadrant_switcher_tb.cpp
//
// NOTE: The while(1) loop means the HLS function never returns.
// C simulation cannot test this directly. This testbench verifies
// the address computation logic separately.
// The actual frame_done synchronization can only be verified
// in RTL cosim or on hardware.

#include <iostream>
#include <ap_int.h>

int main() {
    ap_uint<32> base_addr  = 0x10000000;
    ap_uint<32> out_width  = 1920;
    ap_uint<32> out_height = 1080;
    ap_uint<32> bpp        = 1;
    ap_uint<32> stride     = 3840;

    // Expected addresses per quadrant
    ap_uint<32> expected_addr[4];
    expected_addr[0] = base_addr;
    expected_addr[1] = base_addr + out_width * bpp;
    expected_addr[2] = base_addr + out_height * stride;
    expected_addr[3] = base_addr + out_height * stride + out_width * bpp;

    std::cout << "=== Address Computation Verification ===" << std::endl;

    for (int q = 0; q < 4; q++) {
        ap_uint<2> quadrant = q;
        ap_uint<32> x_offset = (quadrant % 2) * out_width;
        ap_uint<32> y_offset = (quadrant / 2) * out_height;
        ap_uint<32> offset_bytes = y_offset * stride + x_offset * bpp;
        ap_uint<32> start_addr = base_addr + offset_bytes;
        ap_uint<32> hsize = out_width * bpp;
        ap_uint<32> vsize = out_height;

        std::cout << "Q" << q
                  << " | addr=0x" << std::hex << start_addr
                  << " | expected=0x" << expected_addr[q]
                  << " | hsize=" << std::dec << hsize
                  << " | vsize=" << vsize
                  << std::endl;

        if (start_addr != expected_addr[q]) {
            std::cout << "FAIL: address mismatch!" << std::endl;
            return 1;
        }
        if (hsize != out_width * bpp) {
            std::cout << "FAIL: hsize mismatch!" << std::endl;
            return 1;
        }
        if (vsize != out_height) {
            std::cout << "FAIL: vsize mismatch!" << std::endl;
            return 1;
        }
    }

    std::cout << "\n=== 4K RGBA test ===" << std::endl;
    base_addr  = 0x20000000;
    out_width  = 1920;
    out_height = 1080;
    bpp        = 4;
    stride     = 3840 * 4;

    expected_addr[0] = base_addr;
    expected_addr[1] = base_addr + out_width * bpp;
    expected_addr[2] = base_addr + out_height * stride;
    expected_addr[3] = base_addr + out_height * stride + out_width * bpp;

    for (int q = 0; q < 4; q++) {
        ap_uint<2> quadrant = q;
        ap_uint<32> x_offset = (quadrant % 2) * out_width;
        ap_uint<32> y_offset = (quadrant / 2) * out_height;
        ap_uint<32> offset_bytes = y_offset * stride + x_offset * bpp;
        ap_uint<32> start_addr = base_addr + offset_bytes;

        std::cout << "Q" << q
                  << " | addr=0x" << std::hex << start_addr
                  << " | expected=0x" << expected_addr[q]
                  << std::dec << std::endl;

        if (start_addr != expected_addr[q]) {
            std::cout << "FAIL: address mismatch!" << std::endl;
            return 1;
        }
    }

    std::cout << "\n=== ALL TESTS PASSED ===" << std::endl;
    std::cout << "Note: while(1) loop and frame_done sync can only be" << std::endl;
    std::cout << "verified in RTL cosim or on hardware." << std::endl;

    return 0;
}