// =============================================================================
//  axi4lite_slave.sv  —  AXI4-Lite Slave with Config Register File
//  Project   : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
//  Standard  : AMBA AXI4-Lite (IHI0022G)
//
//  ADDRESS MAP  (BASE_ADDR + offset):
//    0x00 – 0x1C : 8 × 32-bit read/write configuration registers
//    Any other   : DECERR (BRESP/RRESP = 2'b11)
//
//  WRITE FLOW   (AW and W channels accepted in any order per spec):
//    Master asserts AWVALID (address) and WVALID (data) in any order.
//    Slave accepts each independently, then performs the register write
//    and asserts BVALID. BVALID stays high until BREADY is seen.
//
//    Write FSM: IDLE → GOT_ADDR → RESPOND   (if AW before W)
//               IDLE → GOT_DATA → RESPOND   (if W before AW)
//               IDLE →            RESPOND   (if simultaneous)
//
//  READ FLOW:
//    Master asserts ARVALID. Slave pulses ARREADY, latches address,
//    and asserts RVALID on the following cycle with RDATA and RRESP.
//    RVALID stays high until RREADY is seen.
//
//    Read FSM: IDLE → DATA
//
//  DECERR policy:
//    Addresses that are not word-aligned OR fall outside
//    [BASE_ADDR, BASE_ADDR + NUM_REGS*4) receive DECERR.
//    The register file is not written on a DECERR write.
//    RDATA is driven to 0 on a DECERR read.
// =============================================================================
`default_nettype none

module axi4lite_slave #(
    parameter int                    DATA_WIDTH = 32,
    parameter int                    ADDR_WIDTH = 32,
    parameter int                    NUM_REGS   = 8,
    parameter logic [ADDR_WIDTH-1:0] BASE_ADDR  = '0
) (
    input  logic                      clk,
    input  logic                      rst_n,

    // ── Write Address Channel ─────────────────────────────────────────────
    input  logic [ADDR_WIDTH-1:0]     s_awaddr,
    input  logic [2:0]                s_awprot,
    input  logic                      s_awvalid,
    output logic                      s_awready,

    // ── Write Data Channel ────────────────────────────────────────────────
    input  logic [DATA_WIDTH-1:0]     s_wdata,
    input  logic [DATA_WIDTH/8-1:0]   s_wstrb,
    input  logic                      s_wvalid,
    output logic                      s_wready,

    // ── Write Response Channel ────────────────────────────────────────────
    output logic [1:0]                s_bresp,
    output logic                      s_bvalid,
    input  logic                      s_bready,

    // ── Read Address Channel ──────────────────────────────────────────────
    input  logic [ADDR_WIDTH-1:0]     s_araddr,
    input  logic [2:0]                s_arprot,
    input  logic                      s_arvalid,
    output logic                      s_arready,

    // ── Read Data Channel ─────────────────────────────────────────────────
    output logic [DATA_WIDTH-1:0]     s_rdata,
    output logic [1:0]                s_rresp,
    output logic                      s_rvalid,
    input  logic                      s_rready
);

    // ── Localparams ───────────────────────────────────────────────────────────
    localparam int  REG_BITS = $clog2(NUM_REGS);              // 3 for 8 regs
    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_DECERR = 2'b11;
    localparam logic [ADDR_WIDTH-1:0] REG_SPACE = ADDR_WIDTH'(NUM_REGS * 4);

    // ─────────────────────────────────────────────────────────────────────────
    // ADDRESS HELPER FUNCTIONS
    // ─────────────────────────────────────────────────────────────────────────

    // True if addr is a valid, word-aligned register address
    function automatic logic addr_in_range (input logic [ADDR_WIDTH-1:0] addr);
        logic [ADDR_WIDTH-1:0] offset;
        offset = addr - BASE_ADDR;
        return (addr[1:0] == 2'b00) && (offset < REG_SPACE);
    endfunction

    // Register index from address (bits [REG_BITS+1:2] of offset)
    function automatic logic [REG_BITS-1:0] addr_to_idx (input logic [ADDR_WIDTH-1:0] addr);
        return REG_BITS'((addr - BASE_ADDR) >> 2);
    endfunction

    // ─────────────────────────────────────────────────────────────────────────
    // WRITE FSM
    // ─────────────────────────────────────────────────────────────────────────
    typedef enum logic [1:0] {
        WR_IDLE     = 2'b00,   // Ready — AWREADY=1, WREADY=1
        WR_GOT_ADDR = 2'b01,   // AW latched, awaiting W  (WREADY=1)
        WR_GOT_DATA = 2'b10,   // W latched, awaiting AW  (AWREADY=1)
        WR_RESPOND  = 2'b11    // BVALID=1, awaiting BREADY
    } wr_state_t;

    wr_state_t wr_state, wr_next;

    // Latched write-channel data
    logic [ADDR_WIDTH-1:0]   aw_addr_r;
    logic [DATA_WIDTH-1:0]   w_data_r;
    logic [DATA_WIDTH/8-1:0] w_strb_r;

    // Effective write values: mux between latched and live signals
    // (depends on which channel arrived first)
    logic [ADDR_WIDTH-1:0]   eff_wr_addr;
    logic [DATA_WIDTH-1:0]   eff_wr_data;
    logic [DATA_WIDTH/8-1:0] eff_wr_strb;

    // One-cycle pulse: perform the register write and move to BVALID
    logic wr_do_write;

    // ── Write handshake outputs (combinatorial from state) ────────────────────
    assign s_awready = (wr_state == WR_IDLE) || (wr_state == WR_GOT_DATA);
    assign s_wready  = (wr_state == WR_IDLE) || (wr_state == WR_GOT_ADDR);

    // ── Write FSM next-state ──────────────────────────────────────────────────
    always_comb begin
        wr_next = wr_state;
        unique case (wr_state)
            WR_IDLE: begin
                if      (s_awvalid && s_wvalid)     wr_next = WR_RESPOND;
                else if (s_awvalid)                  wr_next = WR_GOT_ADDR;
                else if (s_wvalid)                   wr_next = WR_GOT_DATA;
            end
            WR_GOT_ADDR: if (s_wvalid)              wr_next = WR_RESPOND;
            WR_GOT_DATA: if (s_awvalid)             wr_next = WR_RESPOND;
            WR_RESPOND:  if (s_bvalid && s_bready)  wr_next = WR_IDLE;
            default:                                 wr_next = WR_IDLE;
        endcase
    end

    // Pulse when entering WR_RESPOND
    assign wr_do_write = (wr_next == WR_RESPOND) && (wr_state != WR_RESPOND);

    // ── Effective write operands ──────────────────────────────────────────────
    always_comb begin
        unique case (wr_state)
            WR_IDLE: begin        // Both arriving simultaneously — use live signals
                eff_wr_addr = s_awaddr;
                eff_wr_data = s_wdata;
                eff_wr_strb = s_wstrb;
            end
            WR_GOT_ADDR: begin    // AW already latched; W arriving now
                eff_wr_addr = aw_addr_r;
                eff_wr_data = s_wdata;
                eff_wr_strb = s_wstrb;
            end
            WR_GOT_DATA: begin    // W already latched; AW arriving now
                eff_wr_addr = s_awaddr;
                eff_wr_data = w_data_r;
                eff_wr_strb = w_strb_r;
            end
            default: begin
                eff_wr_addr = aw_addr_r;
                eff_wr_data = w_data_r;
                eff_wr_strb = w_strb_r;
            end
        endcase
    end

    // ── Write FSM state register + latch logic ────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state  <= WR_IDLE;
            aw_addr_r <= '0;
            w_data_r  <= '0;
            w_strb_r  <= '0;
            s_bvalid  <= 1'b0;
            s_bresp   <= RESP_OKAY;
        end else begin
            wr_state <= wr_next;

            // Latch AW channel when handshake occurs
            if (s_awvalid && s_awready)
                aw_addr_r <= s_awaddr;

            // Latch W channel when handshake occurs
            if (s_wvalid && s_wready) begin
                w_data_r <= s_wdata;
                w_strb_r <= s_wstrb;
            end

            // Assert BVALID and capture response code
            if (wr_do_write) begin
                s_bvalid <= 1'b1;
                s_bresp  <= addr_in_range(eff_wr_addr) ? RESP_OKAY : RESP_DECERR;
            end

            // Deassert BVALID when master acknowledges
            if (s_bvalid && s_bready)
                s_bvalid <= 1'b0;
        end
    end

    // ── Register file write interface ─────────────────────────────────────────
    logic [REG_BITS-1:0]    rf_wr_addr;
    logic [DATA_WIDTH-1:0]  rf_wr_data;
    logic [DATA_WIDTH/8-1:0] rf_wr_strb;
    logic                   rf_wr_en;

    assign rf_wr_en   = wr_do_write && addr_in_range(eff_wr_addr);
    assign rf_wr_addr = addr_to_idx(eff_wr_addr);
    assign rf_wr_data = eff_wr_data;
    assign rf_wr_strb = eff_wr_strb;

    // ─────────────────────────────────────────────────────────────────────────
    // READ FSM
    // ─────────────────────────────────────────────────────────────────────────
    typedef enum logic [0:0] {
        RD_IDLE = 1'b0,
        RD_DATA = 1'b1
    } rd_state_t;

    rd_state_t rd_state, rd_next;
    logic [ADDR_WIDTH-1:0] ar_addr_r;

    // ARREADY: slave is ready to accept a read address when idle
    assign s_arready = (rd_state == RD_IDLE);

    // ── Read FSM next-state ───────────────────────────────────────────────────
    always_comb begin
        rd_next = rd_state;
        unique case (rd_state)
            RD_IDLE: if (s_arvalid)                 rd_next = RD_DATA;
            RD_DATA: if (s_rvalid && s_rready)      rd_next = RD_IDLE;
            default:                                 rd_next = RD_IDLE;
        endcase
    end

    // ── Read FSM state register ───────────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state  <= RD_IDLE;
            ar_addr_r <= '0;
            s_rvalid  <= 1'b0;
            s_rresp   <= RESP_OKAY;
        end else begin
            rd_state <= rd_next;

            // Latch AR address and assert RVALID on the next cycle
            if (rd_state == RD_IDLE && s_arvalid) begin
                ar_addr_r <= s_araddr;
                s_rvalid  <= 1'b1;
                s_rresp   <= addr_in_range(s_araddr) ? RESP_OKAY : RESP_DECERR;
            end

            // Deassert RVALID when master acknowledges
            if (s_rvalid && s_rready)
                s_rvalid <= 1'b0;
        end
    end

    // ── Register file read interface ──────────────────────────────────────────
    logic [REG_BITS-1:0]   rf_rd_addr;
    logic [DATA_WIDTH-1:0] rf_rd_data;

    assign rf_rd_addr = addr_in_range(ar_addr_r) ? addr_to_idx(ar_addr_r) : '0;
    assign s_rdata    = (s_rresp == RESP_OKAY) ? rf_rd_data : '0;

    // ─────────────────────────────────────────────────────────────────────────
    // REGISTER FILE INSTANCE
    // ─────────────────────────────────────────────────────────────────────────
    regfile #(
        .NUM_REGS   (NUM_REGS),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_regfile (
        .clk     (clk),
        .rst_n   (rst_n),
        .wr_addr (rf_wr_addr),
        .wr_data (rf_wr_data),
        .wr_strb (rf_wr_strb),
        .wr_en   (rf_wr_en),
        .rd_addr (rf_rd_addr),
        .rd_data (rf_rd_data)
    );

    // Unused: awprot/arprot are required by the spec but this slave
    // does not implement protection checking
    logic _unused;
    assign _unused = &{s_awprot, s_arprot};

endmodule

`default_nettype wire
