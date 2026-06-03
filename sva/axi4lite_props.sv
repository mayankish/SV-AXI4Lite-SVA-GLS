// =============================================================================
//  axi4lite_props.sv  —  Formal SVA Property Module
//  Project   : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
//  Standard  : AMBA AXI4-Lite IHI0022G
//  Simulator : Synopsys VCS + VC Formal, Mentor Questa Formal, Cadence JasperGold
//
//  This module contains concurrent SVA (SystemVerilog Assertions) that
//  formally specify the AXI4-Lite protocol invariants a compliant slave must
//  satisfy.  The properties are written to be bound to the DUT:
//
//    bind axi4lite_slave axi4lite_props #(...) u_props (.clk(clk), ...);
//
//  Each property carries a reference to the AMBA spec clause it enforces.
//
//  Property categories:
//   STABILITY — VALID channels must not deassert before READY (A3.2.1)
//   DATA      — Channel signals must not change while VALID && !READY (A3.2.2)
//   RESPONSE  — BRESP/RRESP must be legal values while VALID (A3.4.4)
//   LIVENESS  — Accepted transactions must eventually produce a response
//   RESET     — Response outputs must be 0 immediately out of reset
//   COVER     — Reachability witnesses for each FSM state and path type
// =============================================================================
`default_nettype none

module axi4lite_props
    import axi4lite_pkg::*;
#(
    parameter int                    DATA_WIDTH = 32,
    parameter int                    ADDR_WIDTH = 32,
    parameter int                    NUM_REGS   = 8,
    parameter logic [ADDR_WIDTH-1:0] BASE_ADDR  = '0,
    parameter int                    MAX_WAIT   = 16   // max cycles for liveness
) (
    input logic                      clk,
    input logic                      rst_n,

    input logic [ADDR_WIDTH-1:0]     awaddr,
    input logic                      awvalid, awready,

    input logic [DATA_WIDTH-1:0]     wdata,
    input logic [DATA_WIDTH/8-1:0]   wstrb,
    input logic                      wvalid, wready,

    input logic [1:0]                bresp,
    input logic                      bvalid, bready,

    input logic [ADDR_WIDTH-1:0]     araddr,
    input logic                      arvalid, arready,

    input logic [DATA_WIDTH-1:0]     rdata,
    input logic [1:0]                rresp,
    input logic                      rvalid, rready
);

    // ── Default clocking / disable iff ───────────────────────────────────────
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    // =========================================================================
    // STABILITY PROPERTIES  (IHI0022G Section A3.2.1)
    // "A source is not permitted to change the information it is providing on a
    //  channel until the handshake has been accepted."
    // =========================================================================

    // PROP-S01: AWVALID must not deassert before AWREADY
    // Formal: (awvalid && !awready) |=> awvalid
    property p_awvalid_stable;
        (awvalid && !awready) |=> awvalid;
    endproperty
    AST_AWVALID_STABLE: assert property (p_awvalid_stable)
        else $error("[SVA-S01] AWVALID deasserted before AWREADY");

    // PROP-S02: WVALID must not deassert before WREADY
    property p_wvalid_stable;
        (wvalid && !wready) |=> wvalid;
    endproperty
    AST_WVALID_STABLE: assert property (p_wvalid_stable)
        else $error("[SVA-S02] WVALID deasserted before WREADY");

    // PROP-S03: ARVALID must not deassert before ARREADY
    property p_arvalid_stable;
        (arvalid && !arready) |=> arvalid;
    endproperty
    AST_ARVALID_STABLE: assert property (p_arvalid_stable)
        else $error("[SVA-S03] ARVALID deasserted before ARREADY");

    // PROP-S04: BVALID (slave output) must not deassert before BREADY
    // This ensures the slave correctly holds its response until acknowledged.
    property p_bvalid_stable;
        (bvalid && !bready) |=> bvalid;
    endproperty
    AST_BVALID_STABLE: assert property (p_bvalid_stable)
        else $error("[SVA-S04] BVALID deasserted before BREADY");

    // PROP-S05: RVALID (slave output) must not deassert before RREADY
    property p_rvalid_stable;
        (rvalid && !rready) |=> rvalid;
    endproperty
    AST_RVALID_STABLE: assert property (p_rvalid_stable)
        else $error("[SVA-S05] RVALID deasserted before RREADY");

    // =========================================================================
    // DATA STABILITY PROPERTIES  (IHI0022G Section A3.2.2)
    // "The source must keep the channel stable when it asserts VALID."
    // =========================================================================

    // PROP-D01: AWADDR must remain stable while AWVALID && !AWREADY
    property p_awaddr_stable;
        (awvalid && !awready) |=> $stable(awaddr);
    endproperty
    AST_AWADDR_STABLE: assert property (p_awaddr_stable)
        else $error("[SVA-D01] AWADDR changed while AWVALID=1, AWREADY=0");

    // PROP-D02: WDATA must remain stable while WVALID && !WREADY
    property p_wdata_stable;
        (wvalid && !wready) |=> $stable(wdata);
    endproperty
    AST_WDATA_STABLE: assert property (p_wdata_stable)
        else $error("[SVA-D02] WDATA changed while WVALID=1, WREADY=0");

    // PROP-D03: WSTRB must remain stable while WVALID && !WREADY
    property p_wstrb_stable;
        (wvalid && !wready) |=> $stable(wstrb);
    endproperty
    AST_WSTRB_STABLE: assert property (p_wstrb_stable)
        else $error("[SVA-D03] WSTRB changed while WVALID=1, WREADY=0");

    // PROP-D04: ARADDR must remain stable while ARVALID && !ARREADY
    property p_araddr_stable;
        (arvalid && !arready) |=> $stable(araddr);
    endproperty
    AST_ARADDR_STABLE: assert property (p_araddr_stable)
        else $error("[SVA-D04] ARADDR changed while ARVALID=1, ARREADY=0");

    // PROP-D05: BRESP must be stable while BVALID && !BREADY (slave must hold)
    property p_bresp_stable;
        (bvalid && !bready) |=> $stable(bresp);
    endproperty
    AST_BRESP_STABLE: assert property (p_bresp_stable)
        else $error("[SVA-D05] BRESP changed while BVALID=1, BREADY=0");

    // PROP-D06: RDATA must be stable while RVALID && !RREADY
    property p_rdata_stable;
        (rvalid && !rready) |=> $stable(rdata);
    endproperty
    AST_RDATA_STABLE: assert property (p_rdata_stable)
        else $error("[SVA-D06] RDATA changed while RVALID=1, RREADY=0");

    // =========================================================================
    // RESPONSE CODE PROPERTIES  (IHI0022G Table A3-4)
    // AXI4-Lite supports only OKAY (2'b00) and DECERR (2'b11).
    // EXOKAY (exclusive access) and SLVERR are not used.
    // =========================================================================

    // PROP-R01: BRESP must be OKAY or DECERR while BVALID
    property p_bresp_legal;
        bvalid |-> (bresp == 2'b00 || bresp == 2'b11);
    endproperty
    AST_BRESP_LEGAL: assert property (p_bresp_legal)
        else $error("[SVA-R01] Illegal BRESP=0x%0x while BVALID=1", bresp);

    // PROP-R02: RRESP must be OKAY or DECERR while RVALID
    property p_rresp_legal;
        rvalid |-> (rresp == 2'b00 || rresp == 2'b11);
    endproperty
    AST_RRESP_LEGAL: assert property (p_rresp_legal)
        else $error("[SVA-R02] Illegal RRESP=0x%0x while RVALID=1", rresp);

    // =========================================================================
    // LIVENESS PROPERTIES
    // A slave must eventually respond to an accepted transaction.
    // MAX_WAIT bounds the response latency for bounded model checking.
    // =========================================================================

    // PROP-L01: After AWVALID+AWREADY handshake, BVALID must appear within MAX_WAIT cycles
    // Note: This is a simplified liveness property.  It requires W to also be received.
    //       A stronger version would track both AW and W acceptance independently.
    property p_write_response_liveness;
        (awvalid && awready) |-> ##[1:MAX_WAIT] bvalid;
    endproperty
    AST_WRITE_LIVENESS: assert property (p_write_response_liveness)
        else $error("[SVA-L01] No BVALID within %0d cycles of AW handshake", MAX_WAIT);

    // PROP-L02: After ARVALID+ARREADY handshake, RVALID must appear within MAX_WAIT cycles
    property p_read_response_liveness;
        (arvalid && arready) |-> ##[1:MAX_WAIT] rvalid;
    endproperty
    AST_READ_LIVENESS: assert property (p_read_response_liveness)
        else $error("[SVA-L02] No RVALID within %0d cycles of AR handshake", MAX_WAIT);

    // =========================================================================
    // RESET PROPERTIES
    // Response outputs must deassert synchronously with reset.
    // =========================================================================

    // PROP-RST01: BVALID must be 0 immediately after reset is released
    property p_bvalid_after_reset;
        $rose(rst_n) |-> !bvalid;
    endproperty
    AST_BVALID_RESET: assert property (p_bvalid_after_reset)
        else $error("[SVA-RST01] BVALID asserted on first cycle out of reset");

    // PROP-RST02: RVALID must be 0 immediately after reset is released
    property p_rvalid_after_reset;
        $rose(rst_n) |-> !rvalid;
    endproperty
    AST_RVALID_RESET: assert property (p_rvalid_after_reset)
        else $error("[SVA-RST02] RVALID asserted on first cycle out of reset");

    // =========================================================================
    // COVER PROPERTIES  (reachability witnesses — formal completeness checks)
    // =========================================================================

    // COV-01: A normal write (OKAY response) is reachable
    COV_WRITE_OKAY: cover property ((bvalid && bready && bresp == 2'b00));

    // COV-02: A write DECERR is reachable
    COV_WRITE_DECERR: cover property ((bvalid && bready && bresp == 2'b11));

    // COV-03: A normal read (OKAY response) is reachable
    COV_READ_OKAY: cover property ((rvalid && rready && rresp == 2'b00));

    // COV-04: A read DECERR is reachable
    COV_READ_DECERR: cover property ((rvalid && rready && rresp == 2'b11));

    // COV-05: AW accepted before W (GOT_ADDR path reachable)
    COV_AW_BEFORE_W: cover property (
        (awvalid && awready && !wvalid) ##[1:8] (wvalid && wready)
    );

    // COV-06: W accepted before AW (GOT_DATA path reachable)
    COV_W_BEFORE_AW: cover property (
        (wvalid && wready && !awvalid) ##[1:8] (awvalid && awready)
    );

    // COV-07: BREADY held low while BVALID (backpressure on B channel)
    COV_B_BACKPRESSURE: cover property (
        $rose(bvalid) ##1 (bvalid && !bready) [*3]
    );

endmodule

`default_nettype wire
