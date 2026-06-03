// =============================================================================
//  axi4lite_pkg.sv  —  AXI4-Lite Testbench Package
//  Shared types, response codes, and timeout constants used by the BFM and TB.
// =============================================================================
`ifndef AXI4LITE_PKG_SV
`define AXI4LITE_PKG_SV

package axi4lite_pkg;

    // AXI4 response codes (AMBA IHI0022G, Table A3-4)
    typedef enum logic [1:0] {
        RESP_OKAY   = 2'b00,   // Normal, successful access
        RESP_EXOKAY = 2'b01,   // Exclusive access OK (not used in AXI4-Lite)
        RESP_SLVERR = 2'b10,   // Slave error
        RESP_DECERR = 2'b11    // Decode error — address not mapped
    } axi_resp_t;

    // Simulation constants
    parameter int CLK_PERIOD  = 10;     // ns (100 MHz)
    parameter int TIMEOUT_CYC = 1000;   // Max cycles to wait for a handshake

    // DUT parameters
    parameter int DATA_WIDTH = 32;
    parameter int ADDR_WIDTH = 32;
    parameter int NUM_REGS   = 8;
    parameter logic [ADDR_WIDTH-1:0] BASE_ADDR = 32'h0000_0000;

    // Derived
    parameter int STRB_WIDTH = DATA_WIDTH / 8;   // 4
    parameter int REG_SPACE  = NUM_REGS * 4;     // 32 bytes

    // Test status tracking (updated by testbench tasks)
    int unsigned pass_count = 0;
    int unsigned fail_count = 0;

    // Helper: print a test result line
    task automatic test_result(input string name, input logic pass);
        if (pass) begin
            $display("  [PASS] %s", name);
            pass_count++;
        end else begin
            $display("  [FAIL] %s  <<<<<<<", name);
            fail_count++;
        end
    endtask

endpackage

`endif
