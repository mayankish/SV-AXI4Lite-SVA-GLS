// =============================================================================
//  axi_master_bfm.sv  —  AXI4-Lite Master Bus Functional Model
//  Project : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
//
//  Provides clocking-accurate tasks that drive AXI4-Lite write and read
//  transactions, exactly as a master IP would.  The BFM is instantiated
//  inside the testbench and connected to the DUT via port connections.
//
//  Public tasks:
//    axi_write (addr, data, strb, exp_resp)
//      — Drive AWVALID + WVALID simultaneously, wait for both handshakes,
//        wait for BVALID, check BRESP against exp_resp.
//
//    axi_write_split (addr, data, strb, exp_resp, aw_first)
//      — Drive AW then W (or W then AW) in separate cycles to test
//        the slave's GOT_ADDR / GOT_DATA states.
//
//    axi_read (addr, rdata, exp_resp)
//      — Drive ARVALID, wait for ARREADY, wait for RVALID, capture RDATA,
//        check RRESP against exp_resp.
// =============================================================================
`default_nettype none

module axi_master_bfm
    import axi4lite_pkg::*;
#(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
) (
    input  logic                    clk,
    input  logic                    rst_n,

    // Write Address Channel
    output logic [ADDR_WIDTH-1:0]   m_awaddr,
    output logic [2:0]              m_awprot,
    output logic                    m_awvalid,
    input  logic                    m_awready,

    // Write Data Channel
    output logic [DATA_WIDTH-1:0]   m_wdata,
    output logic [DATA_WIDTH/8-1:0] m_wstrb,
    output logic                    m_wvalid,
    input  logic                    m_wready,

    // Write Response Channel
    input  logic [1:0]              m_bresp,
    input  logic                    m_bvalid,
    output logic                    m_bready,

    // Read Address Channel
    output logic [ADDR_WIDTH-1:0]   m_araddr,
    output logic [2:0]              m_arprot,
    output logic                    m_arvalid,
    input  logic                    m_arready,

    // Read Data Channel
    input  logic [DATA_WIDTH-1:0]   m_rdata,
    input  logic [1:0]              m_rresp,
    input  logic                    m_rvalid,
    output logic                    m_rready
);

    // ── Idle defaults ─────────────────────────────────────────────────────────
    initial begin
        m_awaddr  = '0;  m_awprot = '0;  m_awvalid = 1'b0;
        m_wdata   = '0;  m_wstrb  = '0;  m_wvalid  = 1'b0;
        m_bready  = 1'b1;   // Master always ready to accept B response
        m_araddr  = '0;  m_arprot = '0;  m_arvalid = 1'b0;
        m_rready  = 1'b1;   // Master always ready to accept R data
    end

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: axi_write
    // Drives AW and W simultaneously (most common master behaviour)
    // ─────────────────────────────────────────────────────────────────────────
    task automatic axi_write (
        input  logic [ADDR_WIDTH-1:0]   addr,
        input  logic [DATA_WIDTH-1:0]   data,
        input  logic [DATA_WIDTH/8-1:0] strb,
        input  logic [1:0]              exp_resp = RESP_OKAY
    );
        int aw_done = 0, w_done = 0, b_done = 0;
        int timeout = 0;

        // Assert both channels simultaneously
        @(posedge clk);
        m_awaddr  <= addr;
        m_awprot  <= 3'b000;
        m_awvalid <= 1'b1;
        m_wdata   <= data;
        m_wstrb   <= strb;
        m_wvalid  <= 1'b1;

        // Wait for both handshakes (they may complete on different cycles)
        while (!aw_done || !w_done) begin
            @(posedge clk);
            if (m_awvalid && m_awready) begin
                m_awvalid <= 1'b0;
                aw_done = 1;
            end
            if (m_wvalid && m_wready) begin
                m_wvalid <= 1'b0;
                w_done = 1;
            end
            if (++timeout > TIMEOUT_CYC) begin
                $error("[BFM] axi_write TIMEOUT waiting for AW/W handshake at addr=0x%08h", addr);
                return;
            end
        end

        // Wait for write response
        timeout = 0;
        while (!b_done) begin
            @(posedge clk);
            if (m_bvalid && m_bready) begin
                if (m_bresp !== exp_resp)
                    $error("[BFM] BRESP mismatch at addr=0x%08h: got=%0b exp=%0b",
                           addr, m_bresp, exp_resp);
                b_done = 1;
            end
            if (++timeout > TIMEOUT_CYC) begin
                $error("[BFM] axi_write TIMEOUT waiting for BVALID at addr=0x%08h", addr);
                return;
            end
        end
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: axi_write_split
    // Drives AW and W in separate cycles — tests GOT_ADDR / GOT_DATA states
    //   aw_first=1 : AW before W (slave enters WR_GOT_ADDR)
    //   aw_first=0 : W before AW (slave enters WR_GOT_DATA)
    // ─────────────────────────────────────────────────────────────────────────
    task automatic axi_write_split (
        input  logic [ADDR_WIDTH-1:0]   addr,
        input  logic [DATA_WIDTH-1:0]   data,
        input  logic [DATA_WIDTH/8-1:0] strb,
        input  logic [1:0]              exp_resp = RESP_OKAY,
        input  bit                      aw_first = 1'b1
    );
        int timeout = 0;

        @(posedge clk);

        if (aw_first) begin
            // ── Drive AW first ────────────────────────────────────────────
            m_awaddr  <= addr;
            m_awprot  <= 3'b000;
            m_awvalid <= 1'b1;

            // Wait for AW handshake
            timeout = 0;
            @(posedge clk);
            while (!(m_awvalid && m_awready)) begin
                @(posedge clk);
                if (++timeout > TIMEOUT_CYC) begin
                    $error("[BFM] axi_write_split TIMEOUT on AW"); return;
                end
            end
            m_awvalid <= 1'b0;

            // Inject a 2-cycle gap before W (to stress GOT_ADDR state)
            repeat(2) @(posedge clk);

            // ── Drive W ───────────────────────────────────────────────────
            m_wdata  <= data;
            m_wstrb  <= strb;
            m_wvalid <= 1'b1;
            timeout = 0;
            @(posedge clk);
            while (!(m_wvalid && m_wready)) begin
                @(posedge clk);
                if (++timeout > TIMEOUT_CYC) begin
                    $error("[BFM] axi_write_split TIMEOUT on W"); return;
                end
            end
            m_wvalid <= 1'b0;

        end else begin
            // ── Drive W first ─────────────────────────────────────────────
            m_wdata  <= data;
            m_wstrb  <= strb;
            m_wvalid <= 1'b1;
            timeout = 0;
            @(posedge clk);
            while (!(m_wvalid && m_wready)) begin
                @(posedge clk);
                if (++timeout > TIMEOUT_CYC) begin
                    $error("[BFM] axi_write_split TIMEOUT on W-first"); return;
                end
            end
            m_wvalid <= 1'b0;

            // 2-cycle gap before AW
            repeat(2) @(posedge clk);

            // ── Drive AW ──────────────────────────────────────────────────
            m_awaddr  <= addr;
            m_awprot  <= 3'b000;
            m_awvalid <= 1'b1;
            timeout = 0;
            @(posedge clk);
            while (!(m_awvalid && m_awready)) begin
                @(posedge clk);
                if (++timeout > TIMEOUT_CYC) begin
                    $error("[BFM] axi_write_split TIMEOUT on AW-second"); return;
                end
            end
            m_awvalid <= 1'b0;
        end

        // Wait for B response
        timeout = 0;
        @(posedge clk);
        while (!(m_bvalid && m_bready)) begin
            @(posedge clk);
            if (++timeout > TIMEOUT_CYC) begin
                $error("[BFM] axi_write_split TIMEOUT on BVALID"); return;
            end
        end
        if (m_bresp !== exp_resp)
            $error("[BFM] BRESP mismatch addr=0x%08h: got=%0b exp=%0b",
                   addr, m_bresp, exp_resp);
    endtask

    // ─────────────────────────────────────────────────────────────────────────
    // TASK: axi_read
    // Returns RDATA via output argument; checks RRESP
    // ─────────────────────────────────────────────────────────────────────────
    task automatic axi_read (
        input  logic [ADDR_WIDTH-1:0]   addr,
        output logic [DATA_WIDTH-1:0]   rdata,
        input  logic [1:0]              exp_resp = RESP_OKAY
    );
        int timeout = 0;

        @(posedge clk);
        m_araddr  <= addr;
        m_arprot  <= 3'b000;
        m_arvalid <= 1'b1;

        // Wait for AR handshake
        @(posedge clk);
        while (!(m_arvalid && m_arready)) begin
            @(posedge clk);
            if (++timeout > TIMEOUT_CYC) begin
                $error("[BFM] axi_read TIMEOUT on ARREADY at addr=0x%08h", addr);
                return;
            end
        end
        m_arvalid <= 1'b0;

        // Wait for R data
        timeout = 0;
        @(posedge clk);
        while (!(m_rvalid && m_rready)) begin
            @(posedge clk);
            if (++timeout > TIMEOUT_CYC) begin
                $error("[BFM] axi_read TIMEOUT on RVALID at addr=0x%08h", addr);
                return;
            end
        end
        rdata = m_rdata;
        if (m_rresp !== exp_resp)
            $error("[BFM] RRESP mismatch at addr=0x%08h: got=%0b exp=%0b",
                   addr, m_rresp, exp_resp);
    endtask

endmodule

`default_nettype wire
