// =============================================================================
//  axi4lite_tb.sv  —  Top-Level Testbench
//  Project : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
//
//  9 directed test cases covering:
//   T01  Basic write + readback (register 0)
//   T02  Write all 8 registers, verify all readbacks
//   T03  Partial write via WSTRB (byte-lane enable)
//   T04  Out-of-range write address → DECERR
//   T05  Out-of-range read address → DECERR, RDATA = 0
//   T06  AW before W (slave enters WR_GOT_ADDR)
//   T07  W before AW (slave enters WR_GOT_DATA)
//   T08  Master deasserts BREADY for 4 cycles (BVALID hold test)
//   T09  Back-to-back reads (RVALID hold test)
// =============================================================================
`timescale 1ns/1ps
`default_nettype none

module axi4lite_tb;
    import axi4lite_pkg::*;

    // ── Clock + Reset ─────────────────────────────────────────────────────────
    logic clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    logic rst_n;
    initial begin
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    end

    // ── DUT Interface Wires ───────────────────────────────────────────────────
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic [2:0]              awprot;
    logic                    awvalid, awready;
    logic [DATA_WIDTH-1:0]   wdata;
    logic [STRB_WIDTH-1:0]   wstrb;
    logic                    wvalid, wready;
    logic [1:0]              bresp;
    logic                    bvalid, bready;
    logic [ADDR_WIDTH-1:0]   araddr;
    logic [2:0]              arprot;
    logic                    arvalid, arready;
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rvalid, rready;

    // ── DUT ───────────────────────────────────────────────────────────────────
    axi4lite_slave #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .NUM_REGS   (NUM_REGS),
        .BASE_ADDR  (BASE_ADDR)
    ) dut (
        .clk       (clk),       .rst_n     (rst_n),
        .s_awaddr  (awaddr),    .s_awprot  (awprot),
        .s_awvalid (awvalid),   .s_awready (awready),
        .s_wdata   (wdata),     .s_wstrb   (wstrb),
        .s_wvalid  (wvalid),    .s_wready  (wready),
        .s_bresp   (bresp),     .s_bvalid  (bvalid),  .s_bready (bready),
        .s_araddr  (araddr),    .s_arprot  (arprot),
        .s_arvalid (arvalid),   .s_arready (arready),
        .s_rdata   (rdata),     .s_rresp   (rresp),
        .s_rvalid  (rvalid),    .s_rready  (rready)
    );

    // ── BFM ──────────────────────────────────────────────────────────────────
    axi_master_bfm #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) bfm (
        .clk       (clk),       .rst_n     (rst_n),
        .m_awaddr  (awaddr),    .m_awprot  (awprot),
        .m_awvalid (awvalid),   .m_awready (awready),
        .m_wdata   (wdata),     .m_wstrb   (wstrb),
        .m_wvalid  (wvalid),    .m_wready  (wready),
        .m_bresp   (bresp),     .m_bvalid  (bvalid),  .m_bready (bready),
        .m_araddr  (araddr),    .m_arprot  (arprot),
        .m_arvalid (arvalid),   .m_arready (arready),
        .m_rdata   (rdata),     .m_rresp   (rresp),
        .m_rvalid  (rvalid),    .m_rready  (rready)
    );

    // ── Protocol Checker ─────────────────────────────────────────────────────
    axi4lite_checker #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) chk (
        .clk     (clk),    .rst_n   (rst_n),
        .awaddr  (awaddr), .awvalid (awvalid), .awready (awready),
        .wdata   (wdata),  .wstrb   (wstrb),
        .wvalid  (wvalid), .wready  (wready),
        .bresp   (bresp),  .bvalid  (bvalid),  .bready  (bready),
        .araddr  (araddr), .arvalid (arvalid), .arready (arready),
        .rdata   (rdata),  .rresp   (rresp),
        .rvalid  (rvalid), .rready  (rready)
    );

    // ── Waveform dump ─────────────────────────────────────────────────────────
    initial begin
        $dumpfile("reports/axi4lite_rtl.vcd");
        $dumpvars(0, axi4lite_tb);
    end

    // ─────────────────────────────────────────────────────────────────────────
    // TEST BODY
    // ─────────────────────────────────────────────────────────────────────────
    logic [DATA_WIDTH-1:0] rd_val;
    logic [DATA_WIDTH-1:0] exp_val;

    initial begin
        // Wait for reset to release
        @(posedge rst_n);
        repeat(2) @(posedge clk);

        $display("\n========================================================");
        $display("  AXI4-Lite Slave Testbench — %0t", $time);
        $display("========================================================\n");

        // ── T01: Basic write + readback ──────────────────────────────────────
        $display("[T01] Basic write + readback (REG0)");
        bfm.axi_write(32'h0000_0000, 32'hDEAD_BEEF, 4'hF, RESP_OKAY);
        bfm.axi_read (32'h0000_0000, rd_val,        RESP_OKAY);
        test_result("T01 write+readback REG0", rd_val === 32'hDEAD_BEEF);

        // ── T02: Write all 8 registers, verify all ───────────────────────────
        $display("[T02] Write all 8 registers");
        for (int i = 0; i < NUM_REGS; i++) begin
            bfm.axi_write(32'(i*4), 32'hA5A5_0000 | 32'(i), 4'hF, RESP_OKAY);
        end
        begin
            logic all_ok = 1'b1;
            for (int i = 0; i < NUM_REGS; i++) begin
                bfm.axi_read(32'(i*4), rd_val, RESP_OKAY);
                if (rd_val !== (32'hA5A5_0000 | 32'(i))) begin
                    $display("  REG%0d mismatch: got=0x%08h exp=0x%08h",
                             i, rd_val, (32'hA5A5_0000 | 32'(i)));
                    all_ok = 1'b0;
                end
            end
            test_result("T02 all-register R/W", all_ok);
        end

        // ── T03: Partial write via WSTRB ─────────────────────────────────────
        $display("[T03] Partial write via WSTRB (bytes 0+2 only)");
        // Pre-load known pattern
        bfm.axi_write(32'h0000_0010, 32'hFFFF_FFFF, 4'hF, RESP_OKAY);
        // Write only bytes 0 and 2 (WSTRB=4'b0101)
        bfm.axi_write(32'h0000_0010, 32'h1234_5678, 4'b0101, RESP_OKAY);
        bfm.axi_read (32'h0000_0010, rd_val, RESP_OKAY);
        // 0x1234_5678: byte3=0x12 byte2=0x34 byte1=0x56 byte0=0x78
        // WSTRB=4'b0101 writes bytes 2 and 0 → byte3,1 stay 0xFF
        exp_val = 32'hFF34_FF78;
        test_result("T03 WSTRB partial write", rd_val === exp_val);

        // ── T04: Out-of-range write → DECERR ────────────────────────────────
        $display("[T04] Out-of-range write address → DECERR");
        bfm.axi_write(32'h0000_0080, 32'hBAD_BAAAD, 4'hF, RESP_DECERR);
        // Verify reg0 still holds the T02 value (T02 wrote 0xA5A5_0000 to reg0)
        bfm.axi_read(32'h0000_0000, rd_val, RESP_OKAY);
        test_result("T04 OOB write DECERR", rd_val === 32'hA5A5_0000);

        // ── T05: Out-of-range read → DECERR, RDATA=0 ────────────────────────
        $display("[T05] Out-of-range read address → DECERR");
        bfm.axi_read(32'h0000_0100, rd_val, RESP_DECERR);
        test_result("T05 OOB read DECERR+zero", rd_val === 32'h0);

        // ── T06: AW before W (split, aw_first=1) ────────────────────────────
        $display("[T06] AW before W — tests WR_GOT_ADDR state");
        bfm.axi_write_split(32'h0000_0004, 32'hCAFE_BABE, 4'hF, RESP_OKAY, 1'b1);
        bfm.axi_read(32'h0000_0004, rd_val, RESP_OKAY);
        test_result("T06 AW-before-W split write", rd_val === 32'hCAFE_BABE);

        // ── T07: W before AW (split, aw_first=0) ────────────────────────────
        $display("[T07] W before AW — tests WR_GOT_DATA state");
        bfm.axi_write_split(32'h0000_0008, 32'h1234_ABCD, 4'hF, RESP_OKAY, 1'b0);
        bfm.axi_read(32'h0000_0008, rd_val, RESP_OKAY);
        test_result("T07 W-before-AW split write", rd_val === 32'h1234_ABCD);

        // ── T08: BREADY deasserted for 4 cycles (BVALID hold test) ───────────
        $display("[T08] BREADY held low — verifies BVALID stays asserted");
        begin
            // Deassert master's BREADY so BFM won't consume response immediately
            bfm.m_bready <= 1'b0;
            @(posedge clk);

            // Issue write
            bfm.m_awaddr  <= 32'h0000_000C;
            bfm.m_awprot  <= 3'b000;
            bfm.m_awvalid <= 1'b1;
            bfm.m_wdata   <= 32'hBEEF_FEED;
            bfm.m_wstrb   <= 4'hF;
            bfm.m_wvalid  <= 1'b1;

            // Wait for both handshakes
            @(posedge clk);
            while (!(bfm.m_awvalid && awready && bfm.m_wvalid && wready))
                @(posedge clk);
            bfm.m_awvalid <= 1'b0;
            bfm.m_wvalid  <= 1'b0;

            // Wait for BVALID
            while (!bvalid) @(posedge clk);

            // Hold BREADY low for exactly 4 cycles, verify BVALID stays up
            begin
                logic bvalid_ok = 1'b1;
                repeat(4) begin
                    @(posedge clk);
                    if (!bvalid) bvalid_ok = 1'b0;
                end
                // Now release BREADY
                bfm.m_bready <= 1'b1;
                @(posedge clk);    // B handshake happens here
                bfm.m_bready <= 1'b1;   // leave high for subsequent tests
                test_result("T08 BVALID held during BREADY=0", bvalid_ok);
            end

            // Verify the register was written correctly
            bfm.axi_read(32'h0000_000C, rd_val, RESP_OKAY);
            test_result("T08 data integrity after BREADY hold", rd_val === 32'hBEEF_FEED);
        end

        // ── T09: Back-to-back reads ───────────────────────────────────────────
        $display("[T09] Back-to-back reads (stress RVALID hold)");
        begin
            logic [DATA_WIDTH-1:0] rd0, rd4, rd8;
            bfm.axi_read(32'h0000_0000, rd0, RESP_OKAY);
            bfm.axi_read(32'h0000_0004, rd4, RESP_OKAY);
            bfm.axi_read(32'h0000_0008, rd8, RESP_OKAY);
            // reg0 = 0xA5A5_0000 (from T02); reg1 = CAFE_BABE (T06); reg2 = 1234_ABCD (T07)
            test_result("T09 back-to-back reads consistent",
                        (rd0 === 32'hA5A5_0000) &&
                        (rd4 === 32'hCAFE_BABE) &&
                        (rd8 === 32'h1234_ABCD));
        end

        // ── Summary ──────────────────────────────────────────────────────────
        repeat(5) @(posedge clk);
        $display("\n========================================================");
        $display("  RESULTS:  %0d PASS   %0d FAIL", pass_count, fail_count);
        $display("========================================================\n");

        if (fail_count == 0)
            $display("  ALL TESTS PASSED\n");
        else
            $display("  *** FAILURES DETECTED — see [FAIL] lines above ***\n");

        $finish;
    end

    // ── Timeout watchdog ──────────────────────────────────────────────────────
    initial begin
        #(CLK_PERIOD * 10000);
        $error("[TB] Global simulation timeout — possible deadlock");
        $finish;
    end

endmodule

`default_nettype wire
