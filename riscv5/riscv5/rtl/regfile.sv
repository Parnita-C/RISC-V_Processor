// 32 x 32 register file. x0 is hardwired to 0.
// Write-through: if WB writes the register ID is reading this cycle, ID sees the new value.
module regfile (
  input  logic        clk,
  input  logic        we,
  input  logic [4:0]  waddr, raddr1, raddr2,
  input  logic [31:0] wdata,
  output logic [31:0] rdata1, rdata2
);
  logic [31:0] regs [0:31];
  integer i;
  initial for (i = 0; i < 32; i = i + 1) regs[i] = 32'b0;

  always_ff @(posedge clk)
    if (we && waddr != 5'd0) regs[waddr] <= wdata;

  assign rdata1 = (raddr1 == 5'd0) ? 32'b0 :
                  (we && waddr == raddr1) ? wdata : regs[raddr1];
  assign rdata2 = (raddr2 == 5'd0) ? 32'b0 :
                  (we && waddr == raddr2) ? wdata : regs[raddr2];
endmodule
