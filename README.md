# AXI4-Lite Slave — SVA Verification + Gate-Level Simulation

> **Transistor-accurate protocol compliance, formally specified and gate-level verified.**

A synthesisable AXI4-Lite slave peripheral in SystemVerilog, verified at three levels: directed simulation with a clocking-accurate Bus Functional Model, formal protocol compliance via concurrent SVA properties targeting JasperGold/Questa Formal, and functional equivalence confirmed by re-simulating the post-Yosys gate-level netlist against the same testbench.

The design sits directly in the domain of Synopsys Verification Compiler, VCS, and VC Formal — the tools this project was built to demonstrate understanding of.

---

## What This Project Implements

A fully compliant **AXI4-Lite slave** (AMBA IHI0022G) fronting an **8 × 32-bit configuration register file** with byte-lane write strobes, out-of-range address decoding, and independent write/read datapaths — the exact structure of a GPIO controller, interrupt controller, or DMA descriptor register block inside a real SoC.

```
AXI4-Lite Master
      │
      │  AW channel (AWADDR, AWVALID, AWREADY)
      │  W  channel (WDATA,  WSTRB,   WVALID, WREADY)
      │  B  channel (BRESP,  BVALID,  BREADY)
      │  AR channel (ARADDR, ARVALID, ARREADY)
      │  R  channel (RDATA,  RRESP,   RVALID, RREADY)
      │
 ┌────▼────────────────────────────────────────┐
 │           axi4lite_slave.sv                  │
 │                                              │
 │  Write FSM: IDLE → GOT_ADDR → RESPOND        │
 │             IDLE → GOT_DATA → RESPOND        │
 │             IDLE →            RESPOND  (sim) │
 │  Read  FSM: IDLE → DATA                      │
 │                                              │
 │  Address decode: [BASE, BASE+0x1C] → OKAY   │
 │                  all other         → DECERR  │
 └─────────────────┬────────────────────────────┘
                   │  wr_en, wr_addr, wr_data, wr_strb
                   │  rd_addr → rd_data
                   ▼
 ┌─────────────────────────────────────────────┐
 │           regfile.sv                         │
 │   8 × 32-bit registers                       │
 │   Synchronous write with WSTRB byte-enables  │
 │   Asynchronous read                          │
 └─────────────────────────────────────────────┘
```

---

## Why Each Part Exists

| This project | Synopsys / industry equivalent |
|---|---|
| `axi4lite_slave.sv` (RTL) | DesignWare DW_axi_s, custom peripheral IP |
| `axi_master_bfm.sv` (directed tests) | VCS testbench, UVM sequence / driver |
| `axi4lite_checker.sv` (runtime checks) | VCS assertion-based verification (ABV) |
| `axi4lite_props.sv` (concurrent SVA) | VC Formal / JasperGold property file |
| `synth/synth.ys` (Yosys synthesis) | Design Compiler `compile_ultra` |
| GLS re-simulation (same TB on netlist) | Conformal LEC + VCS gate-level sim |
| `cells_sim.v` (primitive models) | Foundry simulation library (e.g. TSMC28) |

The three verification levels map exactly to an industrial sign-off flow: RTL simulation, formal property checking, gate-level functional equivalence.

---

## Repository Structure

```
02_axi4lite_sva_gls/
│
├── rtl/
│   ├── axi4lite_slave.sv       # AXI4-Lite slave — write FSM + read FSM
│   └── regfile.sv              # 8 × 32-bit config register file (WSTRB)
│
├── tb/
│   ├── axi4lite_pkg.sv         # Package: RESP codes, timeout, pass/fail counter
│   ├── axi_master_bfm.sv       # Bus Functional Model — write / write_split / read tasks
│   ├── axi4lite_checker.sv     # Runtime SVA-equivalent checker (iverilog-compatible)
│   └── axi4lite_tb.sv          # Top testbench — 9 directed test cases
│
├── sva/
│   └── axi4lite_props.sv       # Concurrent SVA — 15 assert + 7 cover properties
│
├── synth/
│   ├── synth.ys                # Yosys synthesis script
│   ├── cells_sim.v             # Behavioural models for Yosys primitives (GLS)
│   └── axi4lite_slave_net.v    # Generated post-synthesis netlist (after yosys run)
│
├── sim/
│   ├── run_rtl_sim.sh          # iverilog RTL simulation
│   ├── run_gls.sh              # Yosys synthesis + iverilog GLS re-simulation
│   ├── run_all.sh              # Full flow (RTL sim → synth → GLS)
│   └── sim_behavioral.py       # Cycle-accurate Python model (no iverilog needed)
│
└── reports/                    # Generated logs, waveforms (gitignored)
```

---

## Requirements

**For iverilog simulation (recommended):**
- [Icarus Verilog](https://github.com/steveicarus/iverilog) ≥ 11 (`iverilog`, `vvp`)
- [Yosys](https://github.com/YosysHQ/yosys) ≥ 0.20 (for GLS)

```bash
# Ubuntu / Debian
sudo apt install iverilog yosys

# macOS
brew install icarus-verilog yosys
```

**For the Python behavioural simulation (no EDA tools required):**
- Python 3.8+

---

## Quick Start

```bash
git clone <repo>
cd 02_axi4lite_sva_gls

# Full flow: RTL sim → Yosys synthesis → GLS re-simulation
bash sim/run_all.sh

# RTL simulation only
bash sim/run_rtl_sim.sh

# Behavioural simulation (no iverilog needed)
python3 sim/sim_behavioral.py
```

---

## Detailed Usage

### RTL Simulation

```bash
bash sim/run_rtl_sim.sh
```

Compiles with `iverilog -g2012` (SystemVerilog 2012 mode), runs `vvp`, writes a VCD waveform to `reports/axi4lite_rtl.vcd`, and tees the log to `reports/rtl_sim.log`. Exits non-zero if any `[FAIL]` or `$error` appears in the log.

Open the waveform with GTKWave:
```bash
gtkwave reports/axi4lite_rtl.vcd
```

### Gate-Level Simulation

```bash
bash sim/run_gls.sh
```

Step 1 runs `yosys synth/synth.ys`, which reads the RTL, runs `proc → opt → memory → fsm → techmap`, and writes `synth/axi4lite_slave_net.v`. The synthesis statistics are captured in `synth/synth.stat`.

Step 2 compiles the gate-level netlist with `synth/cells_sim.v` (behavioural models for Yosys internal primitives `$_AND_`, `$_DFF_PN0_`, etc.) and the same testbench, then re-simulates. If the gate-level simulation produces identical pass/fail results to the RTL simulation, functional equivalence is confirmed.

### Formal Verification (Questa / VCS / JasperGold)

```bash
# Questa Formal
qformal_run -sv sva/axi4lite_props.sv rtl/axi4lite_slave.sv rtl/regfile.sv \
  -top axi4lite_slave -bind axi4lite_props

# JasperGold
jg -sv -f sva/axi4lite_props.sv rtl/axi4lite_slave.sv
```

The properties module is designed to be bound to the DUT:
```systemverilog
bind axi4lite_slave axi4lite_props #(
    .DATA_WIDTH (32),
    .NUM_REGS   (8)
) u_props (
    .clk      (clk),
    .rst_n    (rst_n),
    .awaddr   (s_awaddr),  .awvalid (s_awvalid), .awready (s_awready),
    .wdata    (s_wdata),   .wstrb   (s_wstrb),
    .wvalid   (s_wvalid),  .wready  (s_wready),
    .bresp    (s_bresp),   .bvalid  (s_bvalid),  .bready  (s_bready),
    .araddr   (s_araddr),  .arvalid (s_arvalid), .arready (s_arready),
    .rdata    (s_rdata),   .rresp   (s_rresp),
    .rvalid   (s_rvalid),  .rready  (s_rready)
);
```

---

## RTL Design

### Write FSM

The write FSM has four states to handle the AXI4-Lite requirement that the master may assert `AWVALID` and `WVALID` in any order relative to each other (IHI0022G, Section A3.3):

```
                AWVALID && WVALID
     ┌──────────────────────────────────────────────┐
     │                                              ▼
  WR_IDLE ──(AWVALID only)──► WR_GOT_ADDR ──(WVALID)──► WR_RESPOND
     │                                                        │
     └──(WVALID only)───► WR_GOT_DATA ──(AWVALID)────────────┘
                                                              │
                                                   (BVALID=1, await BREADY)
                                                              │
                                                  ◄──────────┘
                                               (BREADY → back to IDLE)
```

`AWREADY` is asserted whenever the slave can accept a write address — both in `WR_IDLE` and `WR_GOT_DATA` (address already waiting but no data yet). This means the slave never stalls the master unnecessarily on the address channel. `WREADY` follows the same logic on the data channel.

The effective write address and data are selected combinatorially from the latched registers or live channel signals depending on which arrived first — the `eff_wr_addr / eff_wr_data / eff_wr_strb` mux in `axi4lite_slave.sv`.

### Read FSM

The read FSM uses two states. `ARREADY` is asserted only in `RD_IDLE`. On the cycle `ARVALID && ARREADY` is sampled, the address is latched and `RVALID` is asserted on the same clock edge (registered output). `RDATA` is driven from the register file asynchronously through the latched address, so it is stable by the time `RVALID` is seen by the master.

### Address Decoding

Addresses are checked against `[BASE_ADDR, BASE_ADDR + NUM_REGS×4)` and must be word-aligned. Any address failing either check receives `DECERR` (`BRESP`/`RRESP` = `2'b11`). On a DECERR write the register file write-enable is suppressed. On a DECERR read `RDATA` is driven to zero.

### WSTRB Byte-Lane Enables

The register file implements per-byte write enables, so a master can update a single byte of a 32-bit register without a read-modify-write cycle. This is essential for real peripheral use: for example, updating only the enable bit in a GPIO direction register without disturbing the other direction bits.

---

## SVA Properties

`sva/axi4lite_props.sv` contains 15 assertions and 7 cover properties, all targeting the AXI4-Lite protocol invariants from IHI0022G. The properties are in five categories.

### Stability (S01–S05)

Once a VALID signal is asserted, it cannot deassert until its paired READY is seen. This is the most fundamental AXI4 rule (Section A3.2.1) and the most common source of protocol bugs in real IP.

```systemverilog
// S01: AWVALID cannot drop before AWREADY
property p_awvalid_stable;
    (awvalid && !awready) |=> awvalid;
endproperty

// S04: BVALID (slave output) must hold until BREADY
property p_bvalid_stable;
    (bvalid && !bready) |=> bvalid;
endproperty
```

The same pattern applies to `WVALID`/`ARVALID` (master outputs) and `RVALID` (slave output). An RTL bug where `BVALID` is registered incorrectly and deasserts one cycle early would be caught by `AST_BVALID_STABLE` before it ever reaches silicon.

### Data Stability (D01–D06)

Channel payload signals must not change while VALID is asserted and READY has not yet been seen (Section A3.2.2). This catches a common bug where a master updates its address register too early.

```systemverilog
// D01: AWADDR stable while AWVALID && !AWREADY
property p_awaddr_stable;
    (awvalid && !awready) |=> $stable(awaddr);
endproperty

// D05: BRESP stable while BVALID && !BREADY (slave responsibility)
property p_bresp_stable;
    (bvalid && !bready) |=> $stable(bresp);
endproperty
```

### Response Validity (R01–R02)

AXI4-Lite supports only `OKAY` (`2'b00`) and `DECERR` (`2'b11`). `EXOKAY` (exclusive access) and `SLVERR` are not used in AXI4-Lite and would indicate an erroneously wired response bus.

```systemverilog
property p_bresp_legal;
    bvalid |-> (bresp == 2'b00 || bresp == 2'b11);
endproperty
```

### Liveness (L01–L02)

Bounded liveness properties check that the slave responds within `MAX_WAIT` cycles of accepting a transaction. These are the properties that catch deadlock in a formal proof.

```systemverilog
// L02: After AR handshake, RVALID must appear within MAX_WAIT cycles
property p_read_response_liveness;
    (arvalid && arready) |-> ##[1:MAX_WAIT] rvalid;
endproperty
```

### Cover Properties (7 witnesses)

Cover properties prove that each interesting scenario is actually reachable — the formal tool must find a counter-example trace that satisfies the cover. If it cannot, the property itself or the design has a structural bug.

```systemverilog
// AW-before-W path: GOT_ADDR state is reachable
COV_AW_BEFORE_W: cover property (
    (awvalid && awready && !wvalid) ##[1:8] (wvalid && wready)
);

// B-channel backpressure: BVALID held for 3+ cycles while BREADY=0
COV_B_BACKPRESSURE: cover property (
    $rose(bvalid) ##1 (bvalid && !bready) [*3]
);
```

---

## Testbench — 9 Directed Tests

| Test | What it exercises | Key check |
|---|---|---|
| T01 | Basic write + readback | `RDATA === 0xDEAD_BEEF` |
| T02 | Write all 8 registers, read all back | No register aliasing |
| T03 | Partial write `WSTRB=4'b0101` (bytes 0+2) | Bytes 1, 3 unchanged |
| T04 | Write to out-of-range address | `BRESP === DECERR`, no reg corruption |
| T05 | Read from out-of-range address | `RRESP === DECERR`, `RDATA === 0` |
| T06 | AW arrives before W (2-cycle gap) | `WR_GOT_ADDR` state exercised |
| T07 | W arrives before AW (2-cycle gap) | `WR_GOT_DATA` state exercised |
| T08 | `BREADY` held low for 4 cycles | `BVALID` stays asserted throughout |
| T09 | Three consecutive reads | No RVALID/RREADY handshake corruption |

Tests T06 and T07 specifically target the two non-trivial write FSM paths. Without these, the `WR_GOT_ADDR` and `WR_GOT_DATA` states could be dead code — unreachable from any directed test — and formal cover properties would flag them as vacuous.

### Runtime Protocol Checker

`axi4lite_checker.sv` runs alongside the DUT in simulation and reports violations immediately with `$error`. It implements CHK-01 through CHK-12 using `always @(posedge clk)` blocks rather than concurrent assertions, making it compatible with Icarus Verilog (which does not simulate concurrent SVA at runtime).

The checker tracks previous-cycle values of every VALID signal and compares against the current cycle. A deasserted VALID without a corresponding READY triggers an immediate `$error` with the simulation timestamp, making the failing cycle instantly identifiable in the log without manual waveform inspection.

### Behavioural Python Simulation

`sim/sim_behavioral.py` implements the same FSM in Python with non-blocking assignment semantics replicated explicitly — every `always_ff` condition is evaluated against the old registered value before any update, matching SystemVerilog's `<=` semantics exactly. This runs the full 9-test suite without any EDA toolchain and serves as a design-independent reference model.

---

## Gate-Level Simulation

The GLS flow confirms that Yosys synthesis has not altered the observable behaviour of the design.

**Synthesis:** Yosys runs `proc` (always-block to netlist), `opt` (constant propagation, dead code), `memory` (register array inference), `fsm` (state encoding extraction), and `techmap` (mapping to internal primitives). The FSM extraction step is particularly important — Yosys recognises the `typedef enum` state machines and can re-encode them, so the GLS verifies that the re-encoded FSM behaves identically to the RTL original.

**Primitive models:** `synth/cells_sim.v` provides behavioural Verilog models for the Yosys internal cell types: `$_NOT_`, `$_AND_`, `$_DFF_PN0_` (positive-edge DFF with active-low async reset), `$_DFFE_PP_` (DFF with enable), and a dozen others. In a real flow these would be replaced by the foundry simulation library (e.g. `tsmc28_stdcells_ss.v`) and timing would be back-annotated via SDF.

**Zero-delay GLS** (as implemented here) confirms functional equivalence. Timing-annotated GLS would additionally confirm setup/hold margin under worst-case process corner — that is the step between this flow and a full `PrimeTime` sign-off.

---

## Sample Output

```
============================================================
  AXI4-Lite Slave Behavioural Simulation
============================================================

[T01] Basic write + readback (REG0)        [PASS]
[T02] Write all 8 registers                [PASS]
[T03] Partial write via WSTRB (bytes 0+2)  [PASS]
[T04] Out-of-range write → DECERR          [PASS]
[T05] Out-of-range read  → DECERR          [PASS]
[T06] AW before W  (WR_GOT_ADDR path)      [PASS]
[T07] W  before AW (WR_GOT_DATA path)      [PASS]
[T08] BREADY held low — BVALID hold        [PASS] × 2
[T09] Back-to-back reads                   [PASS]

RESULTS:  10 PASS   0 FAIL  —  ALL TESTS PASSED

[CHECKER] Protocol event counts:
  AW handshakes : 14
  W  handshakes : 14
  B  handshakes : 14
  AR handshakes : 16
  R  handshakes : 16
```

---

## Extending the Design

**Add more registers.** Change `NUM_REGS` at instantiation. The address decoder and register file both scale automatically — `$clog2(NUM_REGS)` ensures the index width adjusts and `REG_SPACE` updates the valid address range.

**Add read-only or write-only registers.** Add a `reg_type` parameter array to `regfile.sv`. Mask the write-enable per register and drive `RDATA` to zero for write-only registers. The SVA stability and liveness properties require no changes.

**Add a status register with hardware write.** Add a second write port to `regfile.sv` driven by hardware logic. The AXI4-Lite read path will see the hardware-updated value with no changes to the slave FSM.

**Connect to a Synopsys DMA engine.** Replace the BFM master with a DesignWare DW_axi_m instance and run co-simulation. The `axi4lite_props.sv` file plugs directly into VC Formal or Jasper to formally verify the combined system.

---

## References

- AMBA AXI4 Protocol Specification, IHI0022G, ARM Ltd.
- *SystemVerilog Assertions Handbook*, 4th ed., Ben Cohen et al.
- *Writing Testbenches Using SystemVerilog*, Janick Bergeron
- Yosys Open Synthesis Suite Manual, Claire Wolf
