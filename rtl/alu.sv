`include "defs.vh"
// Combinational ALU: all RV32I arithmetic / logic / shift / compare operations
module alu (
  input  logic [31:0] a, b,
  input  logic [3:0]  op,
  output logic [31:0] y,
  output logic        zero
);
  always_comb begin
    case (op)
      `ALU_ADD:  y = a + b;
      `ALU_SUB:  y = a - b;
      `ALU_AND:  y = a & b;
      `ALU_OR:   y = a | b;
      `ALU_XOR:  y = a ^ b;
      `ALU_SLL:  y = a << b[4:0];
      `ALU_SRL:  y = a >> b[4:0];
      `ALU_SRA:  y = $signed(a) >>> b[4:0];
      `ALU_SLT:  y = {31'b0, $signed(a) < $signed(b)};
      `ALU_SLTU: y = {31'b0, a < b};
      default:   y = 32'b0;
    endcase
  end
  assign zero = (y == 32'b0);
endmodule
