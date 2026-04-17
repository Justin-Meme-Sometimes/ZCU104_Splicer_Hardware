`timescale 1ns/1ps
// quadrant_switcher.sv
//
// Cycles VDMA MM2S start address through NUM_TILES tile positions on each
// frame_done edge. Tile grid is NUM_COLS wide; NUM_TILES = NUM_COLS * NUM_ROWS.
// Supports any even tile count: 4, 6, 8, 16, etc. -- configure via PS registers.
//
// Ports:
//   s_axi_*     : AXI-Lite slave for PS configuration
//   m_axi_*     : AXI-Lite master to write VDMA registers
//   frame_done  : connect to VDMA mm2s_introut
//
// PS registers (via s_axi):
//   0x00: CTRL       [0] = enable
//   0x04: BASE_ADDR  - framebuffer base address
//   0x08: OUT_WIDTH  - sub-frame width in pixels  (e.g. 1920)
//   0x0C: OUT_HEIGHT - sub-frame height in pixels (e.g. 1080)
//   0x10: BPP        - bytes per pixel
//   0x14: STRIDE     - full output row stride in bytes (e.g. num_cols*out_width*bpp)
//   0x18: VDMA_ADDR  - physical address of VDMA register space
//   0x1C: STATUS     (read-only)
//           [31:24] = frame_cnt
//           [23:16] = raw_cnt
//           [14]    = fd_pending
//           [13:10] = m_state
//           [4:0]   = slot  - which tile was last written
//   0x20: TRIG       write any value to manually trigger one FSM cycle (debug)
//   0x24: NUM_COLS   - columns in the tile grid (default 2)
//   0x28: NUM_TILES  - total tiles = NUM_COLS * NUM_ROWS (default 4)
//
// Fixes applied:
//   1. Added M_CALC state so `quadrant` FF settles before addresses are latched.
//      Previously, quadrant was incremented and wr_addr[]/wr_data[] were latched
//      in the same cycle, so the VDMA always received the stale (previous) start
//      address -- causing quadrant to never visibly advance and flickering.
//   2. All four write-pair addresses/data are snapshotted into registered arrays
//      (snap_addr/snap_data) in M_CALC. The FSM then iterates over these stable
//      values instead of re-evaluating the purely combinational wr_addr[]/wr_data[]
//      arrays throughout the write sequence, eliminating potential mid-sequence
//      glitches if config registers or quadrant change.
//   3. Added proper 2-FF CDC synchroniser for frame_done (300 MHz VDMA clock ->
//      100 MHz AXI clock). Edge detection now runs on fd_sync[1], the resolved
//      output, rather than the raw async signal.

module quadrant_switcher #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic resetn,

    // Frame-done from VDMA mm2s_introut (level signal, held high until IOC cleared)
    input  logic frame_done,
    output logic [4:0] slot_out,

    // AXI-Lite slave for PS configuration
    input  logic [5:0]                s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]                s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    input  logic [5:0]                s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // AXI-Lite master to VDMA
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [3:0]                m_axi_wstrb,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,
    input  logic [1:0]                m_axi_bresp,
    input  logic                      m_axi_bvalid,
    output logic                      m_axi_bready,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready
);

    // =========================================================
    // PS-configurable registers
    // =========================================================
    logic [31:0] reg_ctrl;       // 0x00
    logic [31:0] reg_base_addr;  // 0x04
    logic [31:0] reg_out_width;  // 0x08
    logic [31:0] reg_out_height; // 0x0C
    logic [31:0] reg_bpp;        // 0x10
    logic [31:0] reg_stride;     // 0x14
    logic [31:0] reg_vdma_addr;  // 0x18
    // 0x1C = STATUS (read-only)
    logic        sw_trig;        // 0x20: single-cycle pulse on write
    logic [31:0] reg_num_cols;   // 0x24: columns in tile grid (default 2)
    logic [31:0] reg_num_tiles;  // 0x28: total tiles = num_cols*num_rows (default 4)

    

    // =========================================================
    // Clock-domain crossing: frame_done is 300 MHz, clk is 100 MHz.
    // 2-FF synchroniser brings it into the 100 MHz domain before
    // any edge detection.
    //   fd_sync[0] = first stage (may be metastable, do not use)
    //   fd_sync[1] = second stage (resolved, safe to use)
    // Rising edge fires one cycle after fd_sync[1] goes high.
    // =========================================================
    logic [1:0] fd_sync;   // synchroniser chain
    logic fd_prev;         // previous value of synchronised signal
    logic fd_pending;
    logic [7:0] raw_cnt;   // counts rising edges on raw frame_done (debug)
    logic [7:0] frame_cnt; // counts rising edges on fd_sync[1] (debug)
    logic fd_raw_prev;     // previous raw frame_done for edge detect

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            fd_sync    <= 2'b0;
            fd_prev    <= 1'b0;
            fd_pending <= 1'b0;
            fd_raw_prev <= 1'b0;
            raw_cnt    <= 8'h0;
            frame_cnt  <= 8'h0;
        end else begin
            // 2-FF synchroniser (CDC: 300 MHz -> 100 MHz)
            fd_sync[0] <= frame_done;
            fd_sync[1] <= fd_sync[0];

            // Raw rising edge counter (metastable but ok for debug)
            fd_raw_prev <= frame_done;
            if (frame_done & ~fd_raw_prev) raw_cnt <= raw_cnt + 1;

            // Synced rising edge counter
            fd_prev <= fd_sync[1];
            if (fd_sync[1] & ~fd_prev) frame_cnt <= frame_cnt + 1;

            // fd_pending: rising edge or software trigger
            if ((fd_sync[1] & ~fd_prev) || sw_trig) begin
                fd_pending <= 1'b1;
            end else if (m_state == M_IDLE && reg_ctrl[0] && fd_pending) begin
                fd_pending <= 1'b0;
            end
        end
    end

    // =========================================================
    // Tile counter: slot is the flat index (0..num_tiles-1),
    // col_cnt/row_cnt are the 2D position -- avoids hardware division
    // in the address computation.
    // =========================================================
    logic [4:0] slot;
    logic [4:0] col_cnt;
    logic [4:0] row_cnt;
    assign slot_out = slot;

    // =========================================================
    // Address computation (combinational, based on col_cnt/row_cnt)
    // =========================================================
    logic [31:0] start_addr;
    logic [31:0] hsize;
    logic [31:0] vsize;

    always_comb begin
        logic [31:0] x_offset, y_offset, offset_bytes;
        x_offset     = col_cnt * reg_out_width;
        y_offset     = row_cnt * reg_out_height;
        offset_bytes = y_offset * reg_stride + x_offset * reg_bpp;
        start_addr   = reg_base_addr + offset_bytes;
        hsize        = reg_out_width * reg_bpp;
        vsize        = reg_out_height;
    end

    // =========================================================
    // VDMA register offsets (combinational)
    // =========================================================
    logic [31:0] wr_addr [5];
    logic [31:0] wr_data [5];

    always_comb begin
        // IOC clear MUST be first so mm2s_introut goes low immediately,
        // freeing it to fire again on the next frame before the FSM finishes.
        wr_addr[0] = reg_vdma_addr + 32'h04; // MM2S_VDMASR -- clear IOC (bit 12)
        wr_addr[1] = reg_vdma_addr + 32'h5C; // MM2S start addr
        wr_addr[2] = reg_vdma_addr + 32'h58; // MM2S stride
        wr_addr[3] = reg_vdma_addr + 32'h54; // MM2S hsize
        wr_addr[4] = reg_vdma_addr + 32'h50; // MM2S vsize (triggers reload)

        wr_data[0] = 32'h00001000;            // clear IOC (bit 12)
        wr_data[1] = start_addr;
        wr_data[2] = reg_stride;
        wr_data[3] = hsize;
        wr_data[4] = vsize;
    end

    // =========================================================
    // Registered snapshot arrays (FIX #2)
    // Captured in M_CALC after quadrant has settled.
    // The FSM iterates over these rather than the live comb arrays.
    // =========================================================
    logic [31:0] snap_addr [5];
    logic [31:0] snap_data [5];

    // =========================================================
    // AXI-Lite master FSM
    // =========================================================
    typedef enum logic [3:0] {
        M_IDLE,
        M_CALC,     // FIX #1: one-cycle pause for quadrant FF to settle
        M_WR_BOTH,
        M_WR_ADDR,
        M_WR_DATA,
        M_WR_RESP,
        M_NEXT,
        M_DONE
    } master_state_t;

    master_state_t m_state;
    logic [2:0]    wr_index;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            m_state       <= M_IDLE;
            wr_index      <= 3'd0;
            slot          <= 5'd0;
            col_cnt       <= 5'd0;
            row_cnt       <= 5'd0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_awaddr  <= '0;
            m_axi_wdata   <= '0;
            m_axi_wstrb   <= 4'hF;
            for (int i = 0; i < 5; i++) begin
                snap_addr[i] <= '0;
                snap_data[i] <= '0;
            end
        end else begin
            case (m_state)

                // -------------------------------------------------
                // Wait for a frame-done rising edge
                // -------------------------------------------------
                M_IDLE: begin
                    m_axi_bready <= 1'b0;
                    if (reg_ctrl[0] && fd_pending) begin
                        // Advance tile position; wrap at num_tiles boundary
                        if (slot == reg_num_tiles[4:0] - 5'd1) begin
                            slot    <= 5'd0;
                            col_cnt <= 5'd0;
                            row_cnt <= 5'd0;
                        end else begin
                            slot <= slot + 5'd1;
                            if (col_cnt == reg_num_cols[4:0] - 5'd1) begin
                                col_cnt <= 5'd0;
                                row_cnt <= row_cnt + 5'd1;
                            end else begin
                                col_cnt <= col_cnt + 5'd1;
                            end
                        end
                        wr_index <= 3'd0;
                        m_state  <= M_CALC;
                    end
                end

                // -------------------------------------------------
                // FIX #1 + FIX #2:
                //   quadrant FF has now settled.
                //   Snapshot all four address/data pairs from the
                //   now-correct combinational outputs and kick off
                //   the first AXI write.
                // -------------------------------------------------
                M_CALC: begin
                    for (int i = 0; i < 5; i++) begin
                        snap_addr[i] <= wr_addr[i];
                        snap_data[i] <= wr_data[i];
                    end
                    // Kick off first write using the live (now correct) values
                    m_axi_awaddr  <= wr_addr[0];
                    m_axi_awvalid <= 1'b1;
                    m_axi_wdata   <= wr_data[0];
                    m_axi_wvalid  <= 1'b1;
                    m_axi_wstrb   <= 4'hF;
                    m_state       <= M_WR_BOTH;
                end

                // -------------------------------------------------
                // Both address and data presented simultaneously
                // -------------------------------------------------
                M_WR_BOTH: begin
                    if (m_axi_awready && m_axi_wready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b0;
                        m_axi_bready  <= 1'b1;
                        m_state       <= M_WR_RESP;
                    end else if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_state       <= M_WR_DATA;
                    end else if (m_axi_wready) begin
                        m_axi_wvalid  <= 1'b0;
                        m_state       <= M_WR_ADDR;
                    end
                end

                // -------------------------------------------------
                // Data accepted first; waiting for address channel
                // -------------------------------------------------
                M_WR_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_bready  <= 1'b1;
                        m_state       <= M_WR_RESP;
                    end
                end

                // -------------------------------------------------
                // Address accepted first; waiting for data channel
                // -------------------------------------------------
                M_WR_DATA: begin
                    if (m_axi_wready) begin
                        m_axi_wvalid  <= 1'b0;
                        m_axi_bready  <= 1'b1;
                        m_state       <= M_WR_RESP;
                    end
                end

                // -------------------------------------------------
                // Wait for write response
                // -------------------------------------------------
                M_WR_RESP: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        m_state      <= M_NEXT;
                    end
                end

                // -------------------------------------------------
                // Advance to next register write or finish
                // FIX #2: use snap arrays instead of live comb
                // -------------------------------------------------
                M_NEXT: begin
                    if (wr_index == 3'd4) begin
                        m_state <= M_DONE;
                    end else begin
                        wr_index      <= wr_index + 3'd1;
                        m_axi_awaddr  <= snap_addr[wr_index + 3'd1];
                        m_axi_awvalid <= 1'b1;
                        m_axi_wdata   <= snap_data[wr_index + 3'd1];
                        m_axi_wvalid  <= 1'b1;
                        m_axi_wstrb   <= 4'hF;
                        m_state       <= M_WR_BOTH;
                    end
                end

                // -------------------------------------------------
                // Done -- return to idle
                // -------------------------------------------------
                M_DONE: begin
                    m_state <= M_IDLE;
                end

                default: m_state <= M_IDLE;

            endcase
        end
    end

    // Tie off unused master read channel
    assign m_axi_araddr  = '0;
    assign m_axi_arvalid = 1'b0;
    assign m_axi_rready  = 1'b1;

    // =========================================================
    // AXI-Lite slave -- PS writes configuration registers
    // =========================================================
    logic s_aw_done, s_w_done;
    logic [5:0] s_wr_addr_reg;

    // Write address channel
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_awready <= 1'b0;
            s_aw_done     <= 1'b0;
            s_wr_addr_reg <= '0;
        end else begin
            if (s_axi_awvalid && !s_aw_done) begin
                s_axi_awready <= 1'b1;
                s_aw_done     <= 1'b1;
                s_wr_addr_reg <= s_axi_awaddr;
            end else begin
                s_axi_awready <= 1'b0;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_aw_done <= 1'b0;
        end
    end

    // Write data channel
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_wready <= 1'b0;
            s_w_done     <= 1'b0;
        end else begin
            if (s_axi_wvalid && !s_w_done) begin
                s_axi_wready <= 1'b1;
                s_w_done     <= 1'b1;
            end else begin
                s_axi_wready <= 1'b0;
            end
            if (s_axi_bvalid && s_axi_bready)
                s_w_done <= 1'b0;
        end
    end

    // Write registers when both address and data are captured
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            reg_ctrl       <= '0;
            reg_base_addr  <= '0;
            reg_out_width  <= 32'd1920;
            reg_out_height <= 32'd1080;
            reg_bpp        <= 32'd1;
            reg_stride     <= 32'd3840;
            reg_vdma_addr  <= '0;
            sw_trig        <= 1'b0;
            reg_num_cols   <= 32'd2;
            reg_num_tiles  <= 32'd4;
        end else begin
            sw_trig <= 1'b0;  // self-clearing every cycle
            if (s_aw_done && s_w_done && !s_axi_bvalid) begin
                case (s_wr_addr_reg[5:2])
                    4'h0: reg_ctrl       <= s_axi_wdata;
                    4'h1: reg_base_addr  <= s_axi_wdata;
                    4'h2: reg_out_width  <= s_axi_wdata;
                    4'h3: reg_out_height <= s_axi_wdata;
                    4'h4: reg_bpp        <= s_axi_wdata;
                    4'h5: reg_stride     <= s_axi_wdata;
                    4'h6: reg_vdma_addr  <= s_axi_wdata;
                    // 4'h7 = STATUS (read-only)
                    4'h8: sw_trig        <= 1'b1;
                    4'h9: reg_num_cols   <= s_axi_wdata;
                    4'hA: reg_num_tiles  <= s_axi_wdata;
                endcase
            end
        end
    end

    // Write response
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= 2'b00;
        end else begin
            if (s_aw_done && s_w_done && !s_axi_bvalid) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
            end else if (s_axi_bready && s_axi_bvalid) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // Read channel
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= '0;
        end else begin
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                case (s_axi_araddr[5:2])
                    4'h0: s_axi_rdata <= reg_ctrl;
                    4'h1: s_axi_rdata <= reg_base_addr;
                    4'h2: s_axi_rdata <= reg_out_width;
                    4'h3: s_axi_rdata <= reg_out_height;
                    4'h4: s_axi_rdata <= reg_bpp;
                    4'h5: s_axi_rdata <= reg_stride;
                    4'h6: s_axi_rdata <= reg_vdma_addr;
                    4'h7: s_axi_rdata <= {frame_cnt, raw_cnt, 7'd0, fd_pending, m_state[3:0], 2'd0, slot};
                    // 0x20 (4'h8) = TRIG write-only, reads as 0
                    default: s_axi_rdata <= '0;
                endcase
            end else begin
                s_axi_arready <= 1'b0;
            end
            if (s_axi_rvalid && s_axi_rready)
                s_axi_rvalid <= 1'b0;
        end
    end

endmodule
