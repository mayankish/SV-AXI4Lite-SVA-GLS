// =============================================================================
//  cells_sim.v  —  Behavioural Models for Yosys Internal Primitives
//  Project : Synopsys_Projects_v2 / 02_axi4lite_sva_gls
//
//  After Yosys synthesis with `techmap`, the netlist uses Yosys internal
//  cell names (e.g., $_AND_, $_DFF_PN0_).  This file provides synthesisable
//  behavioural models for those primitives so that the GLS simulation
//  can be run with Icarus Verilog without a commercial PDK.
//
//  In a real flow, this file would be replaced by the foundry-provided
//  simulation library (e.g., tsmc28_stdcells.v) and timing would be
//  annotated via an SDF file.  This behavioural version runs at zero-delay,
//  which verifies functional equivalence but not timing.
//
//  Cells modelled:
//    Logic   : $_NOT_, $_AND_, $_OR_, $_NAND_, $_NOR_, $_XOR_, $_XNOR_
//    Mux     : $_MUX_
//    Flip-flops (all Yosys DFF variants used after techmap):
//              $_DFF_P_     — positive-edge, no reset
//              $_DFF_N_     — negative-edge, no reset
//              $_DFF_PP0_   — posedge clk, async reset-HIGH, Q=0
//              $_DFF_PP1_   — posedge clk, async reset-HIGH, Q=1
//              $_DFF_PN0_   — posedge clk, async reset-LOW,  Q=0
//              $_DFF_PN1_   — posedge clk, async reset-LOW,  Q=1
//              $_DFFE_PP_   — posedge clk, active-HIGH enable, no reset
//              $_DFFE_PN0P_ — posedge clk, active-LOW enable, async reset
// =============================================================================
`timescale 1ns/1ps

// ── Combinational primitives ──────────────────────────────────────────────────

module $_NOT_ (input A, output Y);
    assign Y = ~A;
endmodule

module $_AND_ (input A, B, output Y);
    assign Y = A & B;
endmodule

module $_OR_ (input A, B, output Y);
    assign Y = A | B;
endmodule

module $_NAND_ (input A, B, output Y);
    assign Y = ~(A & B);
endmodule

module $_NOR_ (input A, B, output Y);
    assign Y = ~(A | B);
endmodule

module $_XOR_ (input A, B, output Y);
    assign Y = A ^ B;
endmodule

module $_XNOR_ (input A, B, output Y);
    assign Y = ~(A ^ B);
endmodule

module $_MUX_ (input A, B, S, output Y);
    assign Y = S ? B : A;
endmodule

module $_NMUX_ (input A, B, S, output Y);
    assign Y = ~(S ? B : A);
endmodule

module $_ANDNOT_ (input A, B, output Y);
    assign Y = A & (~B);
endmodule

module $_ORNOT_ (input A, B, output Y);
    assign Y = A | (~B);
endmodule

// ── D Flip-flops ──────────────────────────────────────────────────────────────

// Positive-edge DFF, no reset
module $_DFF_P_ (input C, D, output reg Q);
    always @(posedge C) Q <= D;
endmodule

// Negative-edge DFF, no reset
module $_DFF_N_ (input C, D, output reg Q);
    always @(negedge C) Q <= D;
endmodule

// Positive-edge DFF, async reset-HIGH (R=1 resets), Q reset to 0
module $_DFF_PP0_ (input C, R, D, output reg Q);
    always @(posedge C or posedge R)
        if (R) Q <= 1'b0; else Q <= D;
endmodule

// Positive-edge DFF, async reset-HIGH (R=1 resets), Q reset to 1
module $_DFF_PP1_ (input C, R, D, output reg Q);
    always @(posedge C or posedge R)
        if (R) Q <= 1'b1; else Q <= D;
endmodule

// Positive-edge DFF, async reset-LOW (R=0 resets), Q reset to 0
module $_DFF_PN0_ (input C, R, D, output reg Q);
    always @(posedge C or negedge R)
        if (!R) Q <= 1'b0; else Q <= D;
endmodule

// Positive-edge DFF, async reset-LOW (R=0 resets), Q reset to 1
module $_DFF_PN1_ (input C, R, D, output reg Q);
    always @(posedge C or negedge R)
        if (!R) Q <= 1'b1; else Q <= D;
endmodule

// Positive-edge DFF with active-HIGH enable, no reset
module $_DFFE_PP_ (input C, E, D, output reg Q);
    always @(posedge C)
        if (E) Q <= D;
endmodule

// Positive-edge DFF, active-LOW enable, async active-LOW reset, Q=0
module $_DFFE_PN0P_ (input C, E, R, D, output reg Q);
    always @(posedge C or posedge R)
        if (R) Q <= 1'b0;
        else if (!E) Q <= D;
endmodule

// Positive-edge DFF, active-HIGH enable, async active-LOW reset, Q=0
module $_DFFE_PP0P_ (input C, E, R, D, output reg Q);
    always @(posedge C or posedge R)
        if (R) Q <= 1'b0;
        else if (E) Q <= D;
endmodule

// Positive-edge DFF, active-LOW enable, async active-HIGH reset, Q=0
module $_DFFE_PN0N_ (input C, E, R, D, output reg Q);
    always @(posedge C or negedge R)
        if (!R) Q <= 1'b0;
        else if (!E) Q <= D;
endmodule

// Negative-edge DFF, async active-LOW reset, Q=0
module $_DFF_NP0_ (input C, R, D, output reg Q);
    always @(negedge C or posedge R)
        if (R) Q <= 1'b0; else Q <= D;
endmodule

module $_DFF_NN0_ (input C, R, D, output reg Q);
    always @(negedge C or negedge R)
        if (!R) Q <= 1'b0; else Q <= D;
endmodule
