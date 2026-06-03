#!/usr/bin/env bash
# =============================================================================
#  run_rtl_sim.sh  —  RTL Simulation with Icarus Verilog
#  Project : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
#
#  Compiles and simulates the RTL sources + testbench.
#  Run from the project root:   bash sim/run_rtl_sim.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

mkdir -p reports

echo ""
echo "============================================================"
echo "  AXI4-Lite RTL Simulation (Icarus Verilog)"
echo "============================================================"

# ── Compile ───────────────────────────────────────────────────────────────────
echo "[1/2] Compiling..."
iverilog \
    -g2012 \
    -Wall \
    -I tb \
    -o reports/axi4lite_rtl.vvp \
    tb/axi4lite_pkg.sv \
    rtl/regfile.sv \
    rtl/axi4lite_slave.sv \
    tb/axi_master_bfm.sv \
    tb/axi4lite_checker.sv \
    tb/axi4lite_tb.sv

echo "[2/2] Simulating..."
vvp reports/axi4lite_rtl.vvp 2>&1 | tee reports/rtl_sim.log

echo ""
echo "  Waveform : reports/axi4lite_rtl.vcd"
echo "  Log      : reports/rtl_sim.log"
echo "============================================================"
echo ""

# Return non-zero if any FAIL or ERROR lines in log
if grep -qE "\[FAIL\]|\[ERROR\]|\$error" reports/rtl_sim.log; then
    echo "  *** RTL simulation FAILED — see reports/rtl_sim.log ***"
    exit 1
else
    echo "  RTL simulation PASSED"
fi
