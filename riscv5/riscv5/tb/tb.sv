`include "defs.vh"
`timescale 1ns/1ps

// Runs one program and checks the trap result
module err_case #(parameter HEX = "", parameter [2:0] EXP = 0, parameter NAME = "") (input logic clk, rst, output logic done, output integer errors);
  logic halted; logic [2:0] code; logic [31:0] epc;
  cpu #(.HEX(HEX)) dut (.clk(clk), .rst(rst), .halted(halted), .err_code(code), .err_pc(epc));
  assign done = halted;
  initial begin
    errors = 0;
    wait (halted === 1'b1);
    #1;
    if (code !== EXP || epc !== 32'd4) begin
      $display("FAIL %-16s code=%0d (exp %0d) pc=%0d (exp 4)", NAME, code, EXP, epc); errors = 1;
    end else $display("PASS %-16s trapped code=%0d at pc=%0d", NAME, code, epc);
    // the instruction after the fault must NOT have executed
    if (dut.u_rf.regs[2] !== 32'd0 && NAME == "illegal") begin $display("FAIL illegal wrote x2"); errors = 1; end
    if (dut.u_rf.regs[3] !== 32'd0) begin $display("FAIL %s: younger instr executed", NAME); errors = 1; end
  end
endmodule

module tb;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  integer errors = 0;

  // ---------- main program ----------
  logic halted_m; logic [2:0] code_m; logic [31:0] pc_m;
  cpu #(.HEX("programs/main.hex")) dut (.clk(clk), .rst(rst), .halted(halted_m), .err_code(code_m), .err_pc(pc_m));

  task automatic chk(input integer r, input [31:0] exp);
    if (dut.u_rf.regs[r] !== exp) begin
      $display("FAIL x%0d = %h (expected %h)", r, dut.u_rf.regs[r], exp); errors = errors + 1;
    end
  endtask

  // ---------- error cases ----------
  wire [4:0] d; integer e0, e1, e2, e3, e4;
  err_case #("programs/err_illegal.hex",     `ERR_ILLEGAL,     "illegal")     c0 (clk, rst, d[0], e0);
  err_case #("programs/err_load_align.hex",  `ERR_LOAD_ALIGN,  "load_align")  c1 (clk, rst, d[1], e1);
  err_case #("programs/err_store_align.hex", `ERR_STORE_ALIGN, "store_align") c2 (clk, rst, d[2], e2);
  err_case #("programs/err_mem_fault.hex",   `ERR_MEM_FAULT,   "mem_fault")   c3 (clk, rst, d[3], e3);
  err_case #("programs/err_fetch_align.hex", `ERR_FETCH_ALIGN, "fetch_align") c4 (clk, rst, d[4], e4);

  initial begin
    $dumpfile("wave.vcd"); $dumpvars(0, tb);
    repeat (3) @(posedge clk);
    rst = 0;
    repeat (120) @(posedge clk);
    #1;
    chk(1,5);  chk(2,10); chk(3,15); chk(4,5);  chk(5,10); chk(6,15); chk(7,15); chk(8,160);
    chk(10,32'hFFFFFFF0); chk(11,32'hFFFFFFFC); chk(12,15); chk(13,1); chk(14,0);
    chk(15,15); chk(16,30);                       // sw/lw + load-use stall
    chk(17,32'h12345000); chk(18,68);             // lui, auipc
    chk(19,0);  chk(20,7);  chk(21,8);            // taken beq skips x19, bne not taken
    chk(22,96); chk(23,0);                        // jal link + skip
    chk(25,120); chk(26,108); chk(27,0);          // jalr (forwarded rs1) + skip
    chk(28,1);  chk(29,0);  chk(30,3);            // blt taken, bltu not taken
    if (dut.u_dmem.mem[0] !== 32'd15) begin $display("FAIL mem[0]"); errors = errors + 1; end
    if (halted_m) begin $display("FAIL main program trapped (code %0d)", code_m); errors = errors + 1; end
    errors = errors + e0 + e1 + e2 + e3 + e4;
    if (errors == 0) $display("\nALL TESTS PASSED"); else $display("\n%0d TEST(S) FAILED", errors);
    $finish;
  end
endmodule
