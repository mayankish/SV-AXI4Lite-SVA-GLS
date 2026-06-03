#!/usr/bin/env bash
# =============================================================================
#  run_gls.sh  —  Yosys Synthesis + Gate-Level Simulation
#  Project : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
#
#  Step 1: Synthesize RTL → gate-level netlist using Yosys
#  Step 2: Re-simulate the netlist with the same testbench using iverilog
#          A GLS_SIM define is set so the testbench knows it's GLS mode
#
#  Run from the project root:   bash sim/run_gls.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p reports

echo ""
echo "============================================================"
echo "  AXI4-Lite GLS Flow"
echo "============================================================"

# ── Step 1: Yosys synthesis ───────────────────────────────────────────────────
echo "[1/3] Running Yosys synthesis..."
yosys -l reports/yosys.log synth/synth.ys

if [ ! -f synth/axi4lite_slave_net.v ]; then
    echo "ERROR: synthesis did not produce axi4lite_slave_net.v"
    exit 1
fi

echo "  Netlist  : synth/axi4lite_slave_net.v"
echo "  Yosys log: reports/yosys.log"
echo ""

# Print cell statistics
if [ -f synth/synth.stat ]; then
    echo "--- Cell statistics ---"
    cat synth/synth.stat
    echo ""
fi

# ── Step 2: Compile for GLS ───────────────────────────────────────────────────
echo "[2/3] Compiling GLS testbench..."

# The GLS compile uses:
#   - synth/cells_sim.v       : behavioural Yosys primitive models
#   - synth/axi4lite_slave_net.v : post-synthesis netlist (replaces RTL)
#   - regfile.sv              : regfile is embedded in the netlist but we
#                               include cells_sim.v which covers all primitives
#   - Same TB + BFM + checker as RTL sim

iverilog \
    -g2012 \
    -DGLS_SIM \
    -I tb \
    -o reports/axi4lite_gls.vvp \
    tb/axi4lite_pkg.sv \
    synth/cells_sim.v \
    synth/axi4lite_slave_net.v \
    tb/axi_master_bfm.sv \
    tb/axi4lite_checker.sv \
    tb/axi4lite_tb.sv

# ── Step 3: Run GLS simulation ────────────────────────────────────────────────
echo "[3/3] Running GLS simulation..."
vvp reports/axi4lite_gls.vvp 2>&1 | tee reports/gls_sim.log

echo ""
echo "  Waveform : reports/axi4lite_gls.vcd  (if $dumpfile set in TB)"
echo "  Log      : reports/gls_sim.log"
echo "============================================================"
echo ""

if grep -qE "\[FAIL\]|\[ERROR\]|\$error" reports/gls_sim.log; then
    echo "  *** GLS simulation FAILED — see reports/gls_sim.log ***"
    exit 1
else
    echo "  GLS simulation PASSED"
fi
