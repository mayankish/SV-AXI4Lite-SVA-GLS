// =============================================================================
//  regfile.sv  —  8 × 32-bit Configuration Register File
//  Project     : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
//
//  A simple synchronous-write, asynchronous-read register array.
//  Write byte-enables (wr_strb) let the AXI4-Lite slave do partial writes
//  without a read-modify-write cycle — identical to what real CSR blocks
//  (e.g., inside a Synopsys DesignWare peripheral) require.
// =============================================================================
`default_nettype none

module regfile #(
    parameter int NUM_REGS   = 8,
    parameter int DATA_WIDTH = 32
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Write port
    input  logic [$clog2(NUM_REGS)-1:0]  wr_addr,
    input  logic [DATA_WIDTH-1:0]         wr_data,
    input  logic [DATA_WIDTH/8-1:0]       wr_strb,   // one bit per byte lane
    input  logic                          wr_en,

    // Read port (asynchronous — registered read adds one AXI R-channel cycle)
    input  logic [$clog2(NUM_REGS)-1:0]  rd_addr,
    output logic [DATA_WIDTH-1:0]         rd_data
);

    // ── Storage ──────────────────────────────────────────────────────────────
    logic [DATA_WIDTH-1:0] mem [0:NUM_REGS-1];

    // ── Synchronous write with per-byte strobes ───────────────────────────────
    // On reset, all registers clear to 0.
    // On write, only bytes where wr_strb[b]==1 are updated — identical to
    // the AXI4 WSTRB semantics described in IHI0022G section A3.4.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_REGS; i++)
                mem[i] <= '0;
        end else if (wr_en) begin
            for (int b = 0; b < DATA_WIDTH/8; b++) begin
                if (wr_strb[b])
                    mem[wr_addr][b*8 +: 8] <= wr_data[b*8 +: 8];
            end
        end
    end

    // ── Asynchronous read ─────────────────────────────────────────────────────
    // The slave latches rd_addr before driving it here, so RDATA is stable
    // by the time RVALID is asserted on the following cycle.
    assign rd_data = mem[rd_addr];

endmodule

`default_nettype wire
