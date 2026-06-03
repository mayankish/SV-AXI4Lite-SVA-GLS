// =============================================================================
//  axi4lite_checker.sv  —  Runtime Protocol Checker (iverilog-compatible)
//  Project : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
//
//  This module implements the same protocol rules as axi4lite_props.sv but
//  using procedural always blocks instead of concurrent SVA assertions, so
//  they execute correctly under Icarus Verilog (which does not simulate
//  concurrent SVA at runtime).
//
//  For formal verification or Questa/VCS co-simulation, use axi4lite_props.sv.
//  This checker is instantiated directly inside axi4lite_tb.sv.
//
//  Rules implemented (from AMBA AXI4-Lite spec IHI0022G):
//   CHK-01  AWVALID stability — once asserted, must not deassert before AWREADY
//   CHK-02  WVALID stability  — once asserted, must not deassert before WREADY
//   CHK-03  ARVALID stability — once asserted, must not deassert before ARREADY
//   CHK-04  BVALID stability  — must remain asserted until BREADY
//   CHK-05  RVALID stability  — must remain asserted until RREADY
//   CHK-06  AWADDR stability  — must not change while AWVALID && !AWREADY
//   CHK-07  WDATA stability   — must not change while WVALID && !WREADY
//   CHK-08  ARADDR stability  — must not change while ARVALID && !ARREADY
//   CHK-09  BRESP validity    — only OKAY or DECERR are valid in AXI4-Lite
//   CHK-10  RRESP validity    — only OKAY or DECERR are valid in AXI4-Lite
//   CHK-11  No BVALID before reset releases
//   CHK-12  No RVALID before reset releases
// =============================================================================
`default_nettype none

module axi4lite_checker
    import axi4lite_pkg::*;
#(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 32
) (
    input logic                    clk,
    input logic                    rst_n,

    // Write Address
    input logic [ADDR_WIDTH-1:0]   awaddr,
    input logic                    awvalid,
    input logic                    awready,

    // Write Data
    input logic [DATA_WIDTH-1:0]   wdata,
    input logic [DATA_WIDTH/8-1:0] wstrb,
    input logic                    wvalid,
    input logic                    wready,

    // Write Response
    input logic [1:0]              bresp,
    input logic                    bvalid,
    input logic                    bready,

    // Read Address
    input logic [ADDR_WIDTH-1:0]   araddr,
    input logic                    arvalid,
    input logic                    arready,

    // Read Data
    input logic [DATA_WIDTH-1:0]   rdata,
    input logic [1:0]              rresp,
    input logic                    rvalid,
    input logic                    rready
);

    // ── Previous-cycle registers (for edge-sensitive checks) ──────────────────
    logic                    awvalid_d, wvalid_d, arvalid_d;
    logic                    bvalid_d,  rvalid_d;
    logic [ADDR_WIDTH-1:0]   awaddr_d,  araddr_d;
    logic [DATA_WIDTH-1:0]   wdata_d;
    logic [DATA_WIDTH/8-1:0] wstrb_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awvalid_d <= 1'b0; wvalid_d  <= 1'b0; arvalid_d <= 1'b0;
            bvalid_d  <= 1'b0; rvalid_d  <= 1'b0;
            awaddr_d  <= '0;   araddr_d  <= '0;
            wdata_d   <= '0;   wstrb_d   <= '0;
        end else begin
            awvalid_d <= awvalid; wvalid_d  <= wvalid;  arvalid_d <= arvalid;
            bvalid_d  <= bvalid;  rvalid_d  <= rvalid;
            awaddr_d  <= awaddr;  araddr_d  <= araddr;
            wdata_d   <= wdata;   wstrb_d   <= wstrb;
        end
    end

    // ── Runtime checks ────────────────────────────────────────────────────────
    always @(posedge clk) begin
        if (rst_n) begin   // All checks disabled during / immediately after reset

            // CHK-01: AWVALID must not drop without AWREADY
            // Rule: (awvalid && !awready) |=> awvalid
            if (awvalid_d && !awready && !awvalid)
                $error("[CHK-01] AWVALID deasserted without AWREADY at time %0t", $time);

            // CHK-02: WVALID must not drop without WREADY
            if (wvalid_d && !wready && !wvalid)
                $error("[CHK-02] WVALID deasserted without WREADY at time %0t", $time);

            // CHK-03: ARVALID must not drop without ARREADY
            if (arvalid_d && !arready && !arvalid)
                $error("[CHK-03] ARVALID deasserted without ARREADY at time %0t", $time);

            // CHK-04: BVALID must stay high until BREADY
            if (bvalid_d && !bready && !bvalid)
                $error("[CHK-04] BVALID deasserted without BREADY at time %0t", $time);

            // CHK-05: RVALID must stay high until RREADY
            if (rvalid_d && !rready && !rvalid)
                $error("[CHK-05] RVALID deasserted without RREADY at time %0t", $time);

            // CHK-06: AWADDR must remain stable while AWVALID && !AWREADY
            if (awvalid_d && !awready && awvalid && (awaddr !== awaddr_d))
                $error("[CHK-06] AWADDR changed while AWVALID=1, AWREADY=0 at time %0t", $time);

            // CHK-07: WDATA/WSTRB must remain stable while WVALID && !WREADY
            if (wvalid_d && !wready && wvalid) begin
                if (wdata !== wdata_d)
                    $error("[CHK-07a] WDATA changed while WVALID=1, WREADY=0 at time %0t", $time);
                if (wstrb !== wstrb_d)
                    $error("[CHK-07b] WSTRB changed while WVALID=1, WREADY=0 at time %0t", $time);
            end

            // CHK-08: ARADDR must remain stable while ARVALID && !ARREADY
            if (arvalid_d && !arready && arvalid && (araddr !== araddr_d))
                $error("[CHK-08] ARADDR changed while ARVALID=1, ARREADY=0 at time %0t", $time);

            // CHK-09: BRESP must be OKAY or DECERR while BVALID
            // AXI4-Lite does not use EXOKAY or SLVERR
            if (bvalid && !(bresp == 2'b00 || bresp == 2'b11))
                $error("[CHK-09] Invalid BRESP=%0b while BVALID=1 at time %0t", bresp, $time);

            // CHK-10: RRESP must be OKAY or DECERR while RVALID
            if (rvalid && !(rresp == 2'b00 || rresp == 2'b11))
                $error("[CHK-10] Invalid RRESP=%0b while RVALID=1 at time %0t", rresp, $time);

        end else begin
            // CHK-11: BVALID must be 0 during reset
            if (bvalid)
                $error("[CHK-11] BVALID asserted during reset at time %0t", $time);

            // CHK-12: RVALID must be 0 during reset
            if (rvalid)
                $error("[CHK-12] RVALID asserted during reset at time %0t", $time);
        end
    end

    // ── Statistics ────────────────────────────────────────────────────────────
    // Optionally: count protocol events for coverage visibility
    int aw_txn_count = 0;
    int w_txn_count  = 0;
    int b_txn_count  = 0;
    int ar_txn_count = 0;
    int r_txn_count  = 0;

    always @(posedge clk) begin
        if (rst_n) begin
            if (awvalid && awready) aw_txn_count++;
            if (wvalid  && wready)  w_txn_count++;
            if (bvalid  && bready)  b_txn_count++;
            if (arvalid && arready) ar_txn_count++;
            if (rvalid  && rready)  r_txn_count++;
        end
    end

    final begin
        $display("\n[CHECKER] Protocol event counts:");
        $display("  AW handshakes : %0d", aw_txn_count);
        $display("  W  handshakes : %0d", w_txn_count);
        $display("  B  handshakes : %0d", b_txn_count);
        $display("  AR handshakes : %0d", ar_txn_count);
        $display("  R  handshakes : %0d", r_txn_count);
    end

endmodule

`default_nettype wire
