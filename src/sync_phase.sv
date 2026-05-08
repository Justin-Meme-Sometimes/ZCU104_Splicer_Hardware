`timescale 1ns/1ps
// sync_phase.sv
//
// Programmable phase delay for a 1-cycle sync pulse.
// Delays pulse_in by reg_phase clock cycles to produce pulse_out.
// phase = 0 → fires same cycle as input (zero delay).
// If pulse_in arrives while counting, counter reloads (new frame takes priority).
//
// PS registers (via s_axi):
//   0x00: CTRL   [0] = bypass (pulse_out mirrors pulse_in, 1-cycle FF latency)
//   0x04: PHASE  - delay in clock cycles (20-bit, max ~10 ms at 100 MHz)
//   0x08: STATUS (read-only) [0] = counting

module sync_phase #(
    parameter AXI_DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic resetn,

    input  logic pulse_in,   // 1-cycle pulse from quadrant_switcher sync_out
    output logic pulse_out,  // phase-delayed 1-cycle pulse → glasses emitter

    // AXI-Lite slave
    input  logic [3:0]                s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]                s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    input  logic [3:0]                s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready
);

//TODO stuff
endmodule
