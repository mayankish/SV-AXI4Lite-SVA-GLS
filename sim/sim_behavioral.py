#!/usr/bin/env python3
"""
sim_behavioral.py  —  Behavioural simulation of axi4lite_slave.sv
Project : Synopsys_Projects_v2 / 02_axi4lite_sva_gls

Mirrors the RTL exactly — the same FSM states, transition conditions, and
output logic as the SystemVerilog source.  Used as a regression check when
Icarus Verilog / Questa are not available in the current environment.

On a machine with iverilog, run the real RTL/GLS sims instead:
    bash sim/run_all.sh
"""

import sys

# ─────────────────────────────────────────────────────────────────────────────
# Behavioural model of axi4lite_slave.sv
# ─────────────────────────────────────────────────────────────────────────────
class AXI4LiteSlave:
    NUM_REGS   = 8
    DATA_MASK  = 0xFFFF_FFFF
    RESP_OKAY  = 0b00
    RESP_DECERR= 0b11
    BASE_ADDR  = 0
    REG_SPACE  = NUM_REGS * 4   # 32 bytes

    # Write FSM states  (matches wr_state_t enum in RTL)
    WR_IDLE, WR_GOT_ADDR, WR_GOT_DATA, WR_RESPOND = 0, 1, 2, 3
    # Read  FSM states  (matches rd_state_t enum in RTL)
    RD_IDLE, RD_DATA = 0, 1

    def __init__(self):
        # ── Registered state ─────────────────────────────────────────────────
        self.wr_state  = self.WR_IDLE
        self.rd_state  = self.RD_IDLE
        self.aw_addr_r = 0
        self.w_data_r  = 0
        self.w_strb_r  = 0
        self.ar_addr_r = 0
        self.s_bvalid  = 0
        self.s_bresp   = self.RESP_OKAY
        self.s_rvalid  = 0
        self.s_rresp   = self.RESP_OKAY
        self.regfile   = [0] * self.NUM_REGS

        # ── Master-driven inputs (set by BFM before each clock edge) ─────────
        self.s_awaddr  = 0;  self.s_awvalid = 0
        self.s_wdata   = 0;  self.s_wstrb   = 0;  self.s_wvalid = 0
        self.s_bready  = 1
        self.s_araddr  = 0;  self.s_arvalid = 0
        self.s_rready  = 1

    # ── Address helpers (identical to RTL functions) ──────────────────────────
    def addr_in_range(self, addr):
        offset = (addr - self.BASE_ADDR) & 0xFFFF_FFFF
        return (addr & 3) == 0 and offset < self.REG_SPACE

    def addr_to_idx(self, addr):
        return ((addr - self.BASE_ADDR) >> 2) & (self.NUM_REGS - 1)

    # ── Combinational outputs (assign statements in RTL) ──────────────────────
    @property
    def s_awready(self):
        return int(self.wr_state in (self.WR_IDLE, self.WR_GOT_DATA))

    @property
    def s_wready(self):
        return int(self.wr_state in (self.WR_IDLE, self.WR_GOT_ADDR))

    @property
    def s_arready(self):
        return int(self.rd_state == self.RD_IDLE)

    @property
    def s_rdata(self):
        if self.s_rresp == self.RESP_OKAY and self.addr_in_range(self.ar_addr_r):
            return self.regfile[self.addr_to_idx(self.ar_addr_r)]
        return 0

    # ── Effective write mux (eff_wr_* combinational logic in RTL) ────────────
    def _eff_write(self):
        s = self.wr_state
        if   s == self.WR_IDLE:     return self.s_awaddr, self.s_wdata, self.s_wstrb
        elif s == self.WR_GOT_ADDR: return self.aw_addr_r, self.s_wdata, self.s_wstrb
        elif s == self.WR_GOT_DATA: return self.s_awaddr, self.w_data_r, self.w_strb_r
        else:                       return self.aw_addr_r, self.w_data_r, self.w_strb_r

    # ── Next-state functions (always_comb blocks in RTL) ─────────────────────
    def _wr_next(self):
        s = self.wr_state
        if   s == self.WR_IDLE:
            if self.s_awvalid and self.s_wvalid:   return self.WR_RESPOND
            elif self.s_awvalid:                    return self.WR_GOT_ADDR
            elif self.s_wvalid:                     return self.WR_GOT_DATA
        elif s == self.WR_GOT_ADDR:
            if self.s_wvalid:                       return self.WR_RESPOND
        elif s == self.WR_GOT_DATA:
            if self.s_awvalid:                      return self.WR_RESPOND
        elif s == self.WR_RESPOND:
            if self.s_bvalid and self.s_bready:     return self.WR_IDLE
        return s

    def _rd_next(self):
        s = self.rd_state
        if   s == self.RD_IDLE and self.s_arvalid:             return self.RD_DATA
        elif s == self.RD_DATA and self.s_rvalid and self.s_rready: return self.RD_IDLE
        return s

    # ── Clock edge (always_ff @posedge clk) ──────────────────────────────────
    def posedge(self):
        # -------------------------------------------------------------------
        # Critical: snapshot registered outputs BEFORE any updates.
        # In SystemVerilog always_ff, non-blocking assignments (<=) mean
        # every RHS reads the OLD value — two concurrent assignments to the
        # same register use the OLD value for all condition checks.
        # We replicate that here by saving old values first.
        # -------------------------------------------------------------------
        old_bvalid = self.s_bvalid
        old_rvalid = self.s_rvalid

        wr_next      = self._wr_next()
        rd_next      = self._rd_next()
        wr_do_write  = (wr_next == self.WR_RESPOND) and (self.wr_state != self.WR_RESPOND)
        eff_addr, eff_data, eff_strb = self._eff_write()

        # Latch AW
        if self.s_awvalid and self.s_awready:
            self.aw_addr_r = self.s_awaddr

        # Latch W
        if self.s_wvalid and self.s_wready:
            self.w_data_r = self.s_wdata
            self.w_strb_r = self.s_wstrb

        # Register write
        if wr_do_write and self.addr_in_range(eff_addr):
            idx = self.addr_to_idx(eff_addr)
            for b in range(4):
                if eff_strb & (1 << b):
                    shift = b * 8
                    byte  = (eff_data >> shift) & 0xFF
                    mask  = 0xFF << shift
                    self.regfile[idx] = (self.regfile[idx] & ~mask) | (byte << shift)
                    self.regfile[idx] &= self.DATA_MASK

        # BVALID / BRESP
        # Assert on wr_do_write; deassert uses OLD bvalid (non-blocking semantics).
        # These two conditions are mutually exclusive in correct operation:
        #   wr_do_write requires NOT being in WR_RESPOND (old_bvalid==0).
        if wr_do_write:
            self.s_bvalid = 1
            self.s_bresp  = self.RESP_OKAY if self.addr_in_range(eff_addr) else self.RESP_DECERR
        if old_bvalid and self.s_bready:   # ← use OLD bvalid, not newly set one
            self.s_bvalid = 0

        # RVALID / RRESP — latch AR and assert RVALID on the same edge.
        # Deassert uses OLD rvalid (non-blocking semantics).
        if self.rd_state == self.RD_IDLE and self.s_arvalid:
            self.ar_addr_r = self.s_araddr
            self.s_rvalid  = 1
            self.s_rresp   = self.RESP_OKAY if self.addr_in_range(self.s_araddr) else self.RESP_DECERR
        if old_rvalid and self.s_rready:   # ← use OLD rvalid
            self.s_rvalid = 0

        # State advance
        self.wr_state = wr_next
        self.rd_state = rd_next


# ─────────────────────────────────────────────────────────────────────────────
# AXI4-Lite Master BFM
# ─────────────────────────────────────────────────────────────────────────────
class AXIMasterBFM:
    TIMEOUT = 200

    def __init__(self, dut: AXI4LiteSlave):
        self.dut = dut

    def _tick(self):
        self.dut.posedge()

    def write(self, addr, data, strb=0xF, exp_resp=0b00, label=""):
        d = self.dut
        d.s_awaddr = addr;  d.s_awvalid = 1
        d.s_wdata  = data;  d.s_wstrb   = strb;  d.s_wvalid = 1
        d.s_bready = 1

        aw_done = w_done = False
        for _ in range(self.TIMEOUT):
            # Sample before edge
            aw_hs = d.s_awvalid and d.s_awready
            w_hs  = d.s_wvalid  and d.s_wready
            b_hs  = d.s_bvalid  and d.s_bready
            actual_resp = d.s_bresp if b_hs else None
            self._tick()
            if aw_hs: d.s_awvalid = 0; aw_done = True
            if w_hs:  d.s_wvalid  = 0; w_done  = True
            if b_hs and aw_done and w_done:
                break
        else:
            raise TimeoutError(f"write timeout @0x{addr:08X}")

        assert actual_resp == exp_resp, \
            f"BRESP mismatch @0x{addr:08X}: got={actual_resp:02b} exp={exp_resp:02b}"

    def write_split(self, addr, data, strb=0xF, exp_resp=0b00, aw_first=True):
        d = self.dut;  d.s_bready = 1

        if aw_first:
            d.s_awaddr = addr;  d.s_awvalid = 1
            for _ in range(self.TIMEOUT):
                hs = d.s_awvalid and d.s_awready
                self._tick()
                if hs: d.s_awvalid = 0; break
            else: raise TimeoutError("AW split timeout")

            self._tick();  self._tick()   # 2-cycle gap

            d.s_wdata = data;  d.s_wstrb = strb;  d.s_wvalid = 1
            for _ in range(self.TIMEOUT):
                hs = d.s_wvalid and d.s_wready
                self._tick()
                if hs: d.s_wvalid = 0; break
            else: raise TimeoutError("W split timeout")

        else:
            d.s_wdata = data;  d.s_wstrb = strb;  d.s_wvalid = 1
            for _ in range(self.TIMEOUT):
                hs = d.s_wvalid and d.s_wready
                self._tick()
                if hs: d.s_wvalid = 0; break
            else: raise TimeoutError("W-first split timeout")

            self._tick();  self._tick()

            d.s_awaddr = addr;  d.s_awvalid = 1
            for _ in range(self.TIMEOUT):
                hs = d.s_awvalid and d.s_awready
                self._tick()
                if hs: d.s_awvalid = 0; break
            else: raise TimeoutError("AW-second timeout")

        actual_resp = None
        for _ in range(self.TIMEOUT):
            b_hs = d.s_bvalid and d.s_bready
            actual_resp = d.s_bresp if b_hs else actual_resp
            self._tick()
            if b_hs: break
        else: raise TimeoutError("B split timeout")

        assert actual_resp == exp_resp

    def read(self, addr, exp_resp=0b00):
        d = self.dut
        d.s_araddr = addr;  d.s_arvalid = 1;  d.s_rready = 1

        for _ in range(self.TIMEOUT):
            hs = d.s_arvalid and d.s_arready
            self._tick()
            if hs: d.s_arvalid = 0; break
        else: raise TimeoutError(f"AR timeout @0x{addr:08X}")

        for _ in range(self.TIMEOUT):
            r_hs = d.s_rvalid and d.s_rready
            rd_val  = d.s_rdata
            r_resp  = d.s_rresp
            self._tick()
            if r_hs: break
        else: raise TimeoutError(f"R timeout @0x{addr:08X}")

        assert r_resp == exp_resp, \
            f"RRESP mismatch @0x{addr:08X}: got={r_resp:02b} exp={exp_resp:02b}"
        return rd_val


# ─────────────────────────────────────────────────────────────────────────────
# Test runner
# ─────────────────────────────────────────────────────────────────────────────
PASS = "\033[32mPASS\033[0m"
FAIL = "\033[31mFAIL\033[0m"

results = []

def test(name, condition):
    tag = PASS if condition else FAIL
    print(f"  [{tag}] {name}")
    results.append(condition)

def run_tests():
    dut = AXI4LiteSlave()
    bfm = AXIMasterBFM(dut)
    OKAY   = AXI4LiteSlave.RESP_OKAY
    DECERR = AXI4LiteSlave.RESP_DECERR

    print("\n" + "="*60)
    print("  AXI4-Lite Slave — Behavioural Simulation")
    print("="*60 + "\n")

    # T01: Basic write + readback
    print("[T01] Basic write + readback (REG0)")
    bfm.write(0x0000_0000, 0xDEAD_BEEF, strb=0xF, exp_resp=OKAY)
    rd = bfm.read(0x0000_0000, exp_resp=OKAY)
    test("T01 write+readback REG0", rd == 0xDEAD_BEEF)

    # T02: All 8 registers
    print("[T02] Write all 8 registers")
    for i in range(8):
        bfm.write(i*4, 0xA5A5_0000 | i, strb=0xF, exp_resp=OKAY)
    ok = True
    for i in range(8):
        rd = bfm.read(i*4, exp_resp=OKAY)
        if rd != (0xA5A5_0000 | i):
            print(f"  REG{i} mismatch: got=0x{rd:08X} exp=0x{0xA5A5_0000|i:08X}")
            ok = False
    test("T02 all-register R/W", ok)

    # T03: Partial WSTRB (bytes 0 and 2 only)
    print("[T03] Partial write via WSTRB (bytes 0+2)")
    bfm.write(0x10, 0xFFFF_FFFF, strb=0xF,    exp_resp=OKAY)  # pre-load
    bfm.write(0x10, 0x1234_5678, strb=0b0101,  exp_resp=OKAY)  # update b0+b2
    rd = bfm.read(0x10, exp_resp=OKAY)
    # Byte layout of 0x1234_5678:  byte3=0x12  byte2=0x34  byte1=0x56  byte0=0x78
    # WSTRB=0b0101 selects bytes 2 and 0 → bytes 1,3 stay 0xFF
    test("T03 WSTRB partial write", rd == 0xFF34_FF78)

    # T04: Out-of-range write → DECERR
    print("[T04] Out-of-range write → DECERR")
    bfm.write(0x0000_0080, 0xBAD_BAAAD, strb=0xF, exp_resp=DECERR)
    rd = bfm.read(0x0000_0000, exp_resp=OKAY)
    # After T02, reg0 was overwritten to 0xA5A5_0000 — verify OOB write did not corrupt it
    test("T04 OOB write DECERR + reg0 unchanged", rd == 0xA5A5_0000)

    # T05: Out-of-range read → DECERR, RDATA=0
    print("[T05] Out-of-range read → DECERR")
    rd = bfm.read(0x0000_0100, exp_resp=DECERR)
    test("T05 OOB read DECERR + RDATA=0", rd == 0x0)

    # T06: AW before W (aw_first=True)
    print("[T06] AW before W → tests WR_GOT_ADDR state")
    bfm.write_split(0x04, 0xCAFE_BABE, strb=0xF, exp_resp=OKAY, aw_first=True)
    rd = bfm.read(0x04, exp_resp=OKAY)
    test("T06 AW-before-W split write", rd == 0xCAFE_BABE)

    # T07: W before AW (aw_first=False)
    print("[T07] W before AW → tests WR_GOT_DATA state")
    bfm.write_split(0x08, 0x1234_ABCD, strb=0xF, exp_resp=OKAY, aw_first=False)
    rd = bfm.read(0x08, exp_resp=OKAY)
    test("T07 W-before-AW split write", rd == 0x1234_ABCD)

    # T08: BREADY deasserted — BVALID must hold
    print("[T08] BREADY held low — BVALID must stay asserted")
    dut.s_bready = 0       # Deassert bready on the master side
    dut.s_awaddr = 0x0C;  dut.s_awvalid = 1
    dut.s_wdata  = 0xBEEF_FEED;  dut.s_wstrb = 0xF;  dut.s_wvalid = 1

    for _ in range(50):
        aw_hs = dut.s_awvalid and dut.s_awready
        w_hs  = dut.s_wvalid  and dut.s_wready
        dut.posedge()
        if aw_hs: dut.s_awvalid = 0
        if w_hs:  dut.s_wvalid  = 0
        if not dut.s_awvalid and not dut.s_wvalid:
            break

    # Wait for BVALID to assert
    for _ in range(20):
        dut.posedge()
        if dut.s_bvalid: break

    # Verify BVALID stays high for 4 cycles while BREADY=0
    bvalid_held = True
    for _ in range(4):
        dut.posedge()
        if not dut.s_bvalid:
            bvalid_held = False

    # Release BREADY — handshake occurs on the next posedge
    dut.s_bready = 1
    dut.posedge()   # B handshake
    dut.posedge()   # Let BVALID deassert
    test("T08 BVALID held during BREADY=0", bvalid_held)

    rd = bfm.read(0x0C, exp_resp=OKAY)
    test("T08 data integrity after BREADY hold", rd == 0xBEEF_FEED)

    # T09: Back-to-back reads
    print("[T09] Back-to-back reads")
    rd0 = bfm.read(0x00, exp_resp=OKAY)
    rd4 = bfm.read(0x04, exp_resp=OKAY)
    rd8 = bfm.read(0x08, exp_resp=OKAY)
    # reg0=0xA5A5_0000 (T02), reg1=CAFE_BABE (T06), reg2=1234_ABCD (T07)
    test("T09 back-to-back reads consistent",
         rd0 == 0xA5A5_0000 and rd4 == 0xCAFE_BABE and rd8 == 0x1234_ABCD)

    # ── Summary ──────────────────────────────────────────────────────────────
    passed = sum(results)
    failed = len(results) - passed
    print(f"\n{'='*60}")
    print(f"  RESULTS:  {passed} PASS   {failed} FAIL")
    print(f"{'='*60}")
    if failed == 0:
        print("  ALL TESTS PASSED\n")
    else:
        print("  *** FAILURES DETECTED ***\n")
    return failed == 0


if __name__ == "__main__":
    ok = run_tests()
    sys.exit(0 if ok else 1)
