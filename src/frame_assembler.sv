`timescale 1ns/1ps
// frame_assembler.sv
//
// Inverse of quadrant_switcher.sv.
// Cycles the VDMA S2MM destination address through 4 quadrant positions
// in a large (e.g. 4K) framebuffer, assembling one full frame from 4
// sequential incoming sub-frames (e.g. 4x 1080p -> 4K).
//
// Each time S2MM completes a frame (s2mm_introut rises), the FSM:
//   1. Clears S2MM IOC (write 0x1000 to S2MM_VDMASR 0x34)
//   2. Writes the next quadrant's destination address to S2MM start addr (0xAC)
//   3. Writes stride (full output row, e.g. 3840*bpp) to 0xA8
//   4. Writes hsize (input width * bpp, e.g. 1920*bpp) to 0xA4
//   5. Writes vsize (input height, e.g. 1080) to 0xA0 -- triggers next capture
//
// Quadrant layout in the output framebuffer:
//   +-------+-------+
//   |  Q0   |  Q1   |
//   +-------+-------+
//   |  Q2   |  Q3   |
//   +-------+-------+
//
//   Q0 start = base_addr
//   Q1 start = base_addr + in_width  * bpp
//   Q2 start = base_addr + in_height * stride
//   Q3 start = base_addr + in_height * stride + in_width * bpp
//
// PS registers (via s_axi):
//   0x00: CTRL       [0] = enable
//   0x04: BASE_ADDR  - output framebuffer base (4K buffer)
//   0x08: IN_WIDTH   - sub-frame width  (e.g. 1920)
//   0x0C: IN_HEIGHT  - sub-frame height (e.g. 1080)
//   0x10: BPP        - bytes per pixel
//   0x14: STRIDE     - full output row stride in bytes (e.g. 3840 * bpp)
//   0x18: VDMA_ADDR  - physical base address of VDMA register space
//   0x1C: STATUS     (read-only)
//           [31:24] = frame_cnt  - synced S2MM frame edge count
//           [23:16] = raw_cnt    - raw  S2MM frame edge count
//           [8]     = fd_pending
//           [7:4]   = m_state
//           [1:0]   = quadrant   - which quadrant was last written
//   0x20: TRIG       - write any value to manually trigger one FSM cycle

module frame_assembler #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic resetn,

    // Frame-done from VDMA s2mm_introut (level, held until IOC cleared)
    // Must be synchronised from 300 MHz VDMA clock via pulse_stretch if needed.
    input  logic frame_done,

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
    logic [31:0] reg_ctrl;
    logic [31:0] reg_base_addr;
    logic [31:0] reg_in_width;
    logic [31:0] reg_in_height;
    logic [31:0] reg_bpp;
    logic [31:0] reg_stride;      // full output row stride (e.g. 3840 * bpp)
    logic [31:0] reg_vdma_addr;
    logic        sw_trig;

    // =========================================================
    // CDC: frame_done (300 MHz) -> clk (100 MHz)
    // =========================================================
    logic [1:0] fd_sync;
    logic       fd_prev;
    logic       fd_pending;
    logic [7:0] raw_cnt;
    logic [7:0] frame_cnt;
    logic       fd_raw_prev;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            fd_sync     <= 2'b0;
            fd_prev     <= 1'b0;
            fd_pending  <= 1'b0;
            fd_raw_prev <= 1'b0;
            raw_cnt     <= 8'h0;
            frame_cnt   <= 8'h0;
        end else begin
            fd_sync[0] <= frame_done;
            fd_sync[1] <= fd_sync[0];

            fd_raw_prev <= frame_done;
            if (frame_done & ~fd_raw_prev) raw_cnt <= raw_cnt + 1;

            fd_prev <= fd_sync[1];
            if (fd_sync[1] & ~fd_prev) frame_cnt <= frame_cnt + 1;

            if ((fd_sync[1] & ~fd_prev) || sw_trig) begin
                fd_pending <= 1'b1;
            end else if (m_state == M_IDLE && reg_ctrl[0] && fd_pending) begin
                fd_pending <= 1'b0;
            end
        end
    end

    // =========================================================
    // Quadrant counter + destination address computation
    // =========================================================
    logic [1:0] quadrant;
    logic [31:0] dest_addr;
    logic [31:0] hsize;
    logic [31:0] vsize;

    always_comb begin
        logic [31:0] x_offset, y_offset;
        // Pixel offset of this quadrant's top-left corner in the output frame
        x_offset  = (quadrant[0]) ? reg_in_width  : 32'd0;
        y_offset  = (quadrant[1]) ? reg_in_height : 32'd0;
        // Byte offset: y rows of full output stride + x pixels * bpp
        dest_addr = reg_base_addr + y_offset * reg_stride + x_offset * reg_bpp;
        hsize     = reg_in_width  * reg_bpp;   // bytes per input row
        vsize     = reg_in_height;             // rows in input frame
    end

    // =========================================================
    // VDMA S2MM register write plan
    // Write order: IOC clear first, then addr, stride, hsize, vsize
    // =========================================================
    logic [31:0] wr_addr [5];
    logic [31:0] wr_data [5];

    always_comb begin
        wr_addr[0] = reg_vdma_addr + 32'h34; // S2MM_VDMASR -- clear S2MM IOC
        wr_addr[1] = reg_vdma_addr + 32'hAC; // S2MM start addr
        wr_addr[2] = reg_vdma_addr + 32'hA8; // S2MM stride
        wr_addr[3] = reg_vdma_addr + 32'hA4; // S2MM hsize
        wr_addr[4] = reg_vdma_addr + 32'hA0; // S2MM vsize (triggers capture)

        wr_data[0] = 32'h00001000;            // clear S2MM IOC (bit 12)
        wr_data[1] = dest_addr;
        wr_data[2] = reg_stride;
        wr_data[3] = hsize;
        wr_data[4] = vsize;
    end

    logic [31:0] snap_addr [5];
    logic [31:0] snap_data [5];

    // =========================================================
    // AXI-Lite master FSM
    // =========================================================
    typedef enum logic [3:0] {
        M_IDLE,
        M_CALC,
        M_WR_BOTH,
        M_WR_ADDR,
        M_WR_DATA,
        M_WR_RESP,
        M_NEXT,
        M_DONE
    } master_state_t;

    master_state_t m_state;
    logic [2:0] wr_index;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            m_state       <= M_IDLE;
            wr_index      <= 3'd0;
            quadrant      <= 2'd0;
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

                M_IDLE: begin
                    m_axi_bready <= 1'b0;
                    if (reg_ctrl[0] && fd_pending) begin
                        quadrant <= quadrant + 2'd1;
                        wr_index <= 3'd0;
                        m_state  <= M_CALC;
                    end
                end

                // quadrant FF has settled; snapshot and kick off first write
                M_CALC: begin
                    for (int i = 0; i < 5; i++) begin
                        snap_addr[i] <= wr_addr[i];
                        snap_data[i] <= wr_data[i];
                    end
                    m_axi_awaddr  <= wr_addr[0];
                    m_axi_awvalid <= 1'b1;
                    m_axi_wdata   <= wr_data[0];
                    m_axi_wvalid  <= 1'b1;
                    m_axi_wstrb   <= 4'hF;
                    m_state       <= M_WR_BOTH;
                end

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

                M_WR_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_bready  <= 1'b1;
                        m_state       <= M_WR_RESP;
                    end
                end

                M_WR_DATA: begin
                    if (m_axi_wready) begin
                        m_axi_wvalid  <= 1'b0;
                        m_axi_bready  <= 1'b1;
                        m_state       <= M_WR_RESP;
                    end
                end

                M_WR_RESP: begin
                    if (m_axi_bvalid) begin
                        m_axi_bready <= 1'b0;
                        m_state      <= M_NEXT;
                    end
                end

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

                // Wait for S2MM IOC to deassert before going idle
                // (confirms VDMA accepted the new frame parameters)
                M_DONE: begin
                    if (~fd_sync[1]) begin
                        m_state <= M_IDLE;
                    end
                end

                default: m_state <= M_IDLE;
            endcase
        end
    end

    assign m_axi_araddr  = '0;
    assign m_axi_arvalid = 1'b0;
    assign m_axi_rready  = 1'b1;

    // =========================================================
    // AXI-Lite slave
    // =========================================================
    logic s_aw_done, s_w_done;
    logic [5:0] s_wr_addr_reg;

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

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            reg_ctrl       <= '0;
            reg_base_addr  <= '0;
            reg_in_width   <= 32'd1920;
            reg_in_height  <= 32'd1080;
            reg_bpp        <= 32'd1;
            reg_stride     <= 32'd3840;   // default: 2*in_width*1bpp
            reg_vdma_addr  <= '0;
            sw_trig        <= 1'b0;
        end else begin
            sw_trig <= 1'b0;
            if (s_aw_done && s_w_done && !s_axi_bvalid) begin
                case (s_wr_addr_reg[5:2])
                    4'h0: reg_ctrl      <= s_axi_wdata;
                    4'h1: reg_base_addr <= s_axi_wdata;
                    4'h2: reg_in_width  <= s_axi_wdata;
                    4'h3: reg_in_height <= s_axi_wdata;
                    4'h4: reg_bpp       <= s_axi_wdata;
                    4'h5: reg_stride    <= s_axi_wdata;
                    4'h6: reg_vdma_addr <= s_axi_wdata;
                    // 4'h7 = STATUS read-only
                    4'h8: sw_trig       <= 1'b1;
                endcase
            end
        end
    end

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
                    4'h2: s_axi_rdata <= reg_in_width;
                    4'h3: s_axi_rdata <= reg_in_height;
                    4'h4: s_axi_rdata <= reg_bpp;
                    4'h5: s_axi_rdata <= reg_stride;
                    4'h6: s_axi_rdata <= reg_vdma_addr;
                    4'h7: s_axi_rdata <= {frame_cnt, raw_cnt, 7'd0, fd_pending,
                                          m_state[3:0], 2'd0, quadrant};
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
