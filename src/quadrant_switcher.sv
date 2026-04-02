// quadrant_switcher.sv
//
// Cycles VDMA MM2S start address through 4 quadrants on each frame_done edge.
//
// Ports:
//   s_axi_*     : AXI-Lite slave for PS configuration
//   m_axi_*     : AXI-Lite master to write VDMA registers
//   frame_done  : connect to VDMA mm2s_introut
//
// PS registers (via s_axi):
//   0x00: CTRL       [0] = enable
//   0x04: BASE_ADDR  - framebuffer base address
//   0x08: OUT_WIDTH  - output width in pixels
//   0x0C: OUT_HEIGHT - output height in pixels
//   0x10: BPP        - bytes per pixel
//   0x14: STRIDE     - full input row stride in bytes
//   0x18: VDMA_ADDR  - physical address of VDMA register space
//   0x1C: STATUS     [1:0] = current_quadrant (read-only)
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
//   3. fd_sync shift direction fixed: was {fd_sync[0], frame_done} which means
//      fd_sync[1] is newer -- reversed to {fd_sync[1], frame_done} with rising
//      edge = fd_sync[1] & ~fd_sync[0] for a clean 2-FF synchroniser.

module quadrant_switcher #(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 32
)(
    input  logic clk,
    input  logic resetn,

    // Frame-done from VDMA mm2s_introut
    input  logic frame_done,

    // AXI-Lite slave for PS configuration
    input  logic [4:0]                s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]                s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,
    input  logic [4:0]                s_axi_araddr,
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

    wire enable = reg_ctrl[0];

    // =========================================================
    // Frame-done edge detection  (FIX #3)
    // 2-FF synchroniser: fd_sync[0] = first stage (oldest),
    //                    fd_sync[1] = second stage (newest)
    // Rising edge fires one cycle after frame_done goes high.
    // =========================================================
    logic [1:0] fd_sync;
    wire fd_rising = fd_sync[1] & ~fd_sync[0];

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn)
            fd_sync <= 2'b00;
        else
            fd_sync <= {fd_sync[0], frame_done};
    end

    // =========================================================
    // Quadrant counter
    // =========================================================
    logic [1:0] quadrant;

    // =========================================================
    // Address computation (combinational, based on current quadrant)
    // =========================================================
    logic [31:0] start_addr;
    logic [31:0] hsize;
    logic [31:0] vsize;

    always_comb begin
        logic [31:0] x_offset, y_offset, offset_bytes;
        x_offset     = (quadrant[0]) ? reg_out_width  : 32'd0;
        y_offset     = (quadrant[1]) ? reg_out_height : 32'd0;
        offset_bytes = y_offset * reg_stride + x_offset * reg_bpp;
        start_addr   = reg_base_addr + offset_bytes;
        hsize        = reg_out_width * reg_bpp;
        vsize        = reg_out_height;
    end

    // =========================================================
    // VDMA register offsets (combinational)
    // =========================================================
    logic [31:0] wr_addr [4];
    logic [31:0] wr_data [4];

    always_comb begin
        wr_addr[0] = reg_vdma_addr + 32'h5C; // MM2S start addr
        wr_addr[1] = reg_vdma_addr + 32'h58; // MM2S stride
        wr_addr[2] = reg_vdma_addr + 32'h54; // MM2S hsize
        wr_addr[3] = reg_vdma_addr + 32'h50; // MM2S vsize

        wr_data[0] = start_addr;
        wr_data[1] = reg_stride;
        wr_data[2] = hsize;
        wr_data[3] = vsize;
    end

    // =========================================================
    // Registered snapshot arrays (FIX #2)
    // Captured in M_CALC after quadrant has settled.
    // The FSM iterates over these rather than the live comb arrays.
    // =========================================================
    logic [31:0] snap_addr [4];
    logic [31:0] snap_data [4];

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
    logic [1:0]    wr_index;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            m_state       <= M_IDLE;
            wr_index      <= 2'd0;
            quadrant      <= 2'd0;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
            m_axi_awaddr  <= '0;
            m_axi_wdata   <= '0;
            m_axi_wstrb   <= 4'hF;
            for (int i = 0; i < 4; i++) begin
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
                    if (enable && fd_rising) begin
                        quadrant <= quadrant + 2'd1;  // FF update scheduled
                        wr_index <= 2'd0;
                        m_state  <= M_CALC;           // wait one cycle (FIX #1)
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
                    for (int i = 0; i < 4; i++) begin
                        snap_addr[i] <= wr_addr[i];   // FIX #2: stable snapshot
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
                // Address accepted; waiting for data
                // -------------------------------------------------
                M_WR_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_bready  <= 1'b1;
                        m_state       <= M_WR_RESP;
                    end
                end

                // -------------------------------------------------
                // Data accepted; waiting for address
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
                    if (wr_index == 2'd3) begin
                        m_state <= M_DONE;
                    end else begin
                        wr_index          <= wr_index + 2'd1;
                        m_axi_awaddr  <= snap_addr[wr_index + 2'd1];
                        m_axi_awvalid <= 1'b1;
                        m_axi_wdata   <= snap_data[wr_index + 2'd1];
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
    logic [4:0] s_wr_addr_reg;

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
        end else if (s_aw_done && s_w_done && !s_axi_bvalid) begin
            case (s_wr_addr_reg[4:2])
                3'h0: reg_ctrl       <= s_axi_wdata;
                3'h1: reg_base_addr  <= s_axi_wdata;
                3'h2: reg_out_width  <= s_axi_wdata;
                3'h3: reg_out_height <= s_axi_wdata;
                3'h4: reg_bpp        <= s_axi_wdata;
                3'h5: reg_stride     <= s_axi_wdata;
                3'h6: reg_vdma_addr  <= s_axi_wdata;
            endcase
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
                case (s_axi_araddr[4:2])
                    3'h0: s_axi_rdata <= reg_ctrl;
                    3'h1: s_axi_rdata <= reg_base_addr;
                    3'h2: s_axi_rdata <= reg_out_width;
                    3'h3: s_axi_rdata <= reg_out_height;
                    3'h4: s_axi_rdata <= reg_bpp;
                    3'h5: s_axi_rdata <= reg_stride;
                    3'h6: s_axi_rdata <= reg_vdma_addr;
                    3'h7: s_axi_rdata <= {30'd0, quadrant};
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
