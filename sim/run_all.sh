#!/usr/bin/env bash
# =============================================================================
#  run_all.sh  —  Full Verification Flow
#  Project : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
#
#  Runs RTL simulation, then Yosys synthesis + GLS simulation.
#  Exits non-zero if either step fails.
#
#  Run from the project root:   bash sim/run_all.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   AXI4-Lite Slave — Full Verification Flow               ║"
echo "╚══════════════════════════════════════════════════════════╝"

# ── RTL simulation ────────────────────────────────────────────────────────────
echo ""
echo "━━━━  STEP 1: RTL Simulation  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash sim/run_rtl_sim.sh
RTL_STATUS=$?

# ── GLS flow ──────────────────────────────────────────────────────────────────
echo ""
echo "━━━━  STEP 2: Synthesis + GLS  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash sim/run_gls.sh
GLS_STATUS=$?

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   VERIFICATION SUMMARY                                   ║"
echo "╠══════════════════════════════════════════════════════════╣"

if [ $RTL_STATUS -eq 0 ]; then
    echo "║   RTL Simulation : PASSED                                ║"
else
    echo "║   RTL Simulation : FAILED  ←←←                          ║"
fi

if [ $GLS_STATUS -eq 0 ]; then
    echo "║   GLS Simulation : PASSED                                ║"
else
    echo "║   GLS Simulation : FAILED  ←←←                          ║"
fi

echo "╠══════════════════════════════════════════════════════════╣"
echo "║   Reports in: reports/                                   ║"
echo "║     rtl_sim.log   gls_sim.log   yosys.log                ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Exit non-zero if anything failed
if [ $RTL_STATUS -ne 0 ] || [ $GLS_STATUS -ne 0 ]; then
    exit 1
fi
