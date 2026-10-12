`include "defs.vh"
// Main decoder. Flags anything outside the supported RV32I subset as illegal.
module control (
  input  logic [31:0] instr,
  output logic        reg_write, mem_read, mem_write, mem_to_reg,
  output logic        alu_src_b,          // 0: rs2, 1: imm
  output logic [1:0]  alu_a_sel,          // 0: rs1, 1: pc, 2: zero
  output logic [3:0]  alu_op,
  output logic        branch, jal, jalr,
  output logic        uses_rs1, uses_rs2,
  output logic        illegal
);
  logic [6:0] opcode, funct7;
  logic [2:0] funct3;
  assign opcode = instr[6:0];
  assign funct3 = instr[14:12];
  assign funct7 = instr[31:25];

  always_comb begin
    reg_write = 0; mem_read = 0; mem_write = 0; mem_to_reg = 0;
    alu_src_b = 0; alu_a_sel = 2'd0; alu_op = `ALU_ADD;
    branch = 0; jal = 0; jalr = 0; uses_rs1 = 0; uses_rs2 = 0; illegal = 0;

    case (opcode)
      `OP_REG: begin
        reg_write = 1; uses_rs1 = 1; uses_rs2 = 1;
        case (funct3)
          3'b000: alu_op = funct7[5] ? `ALU_SUB : `ALU_ADD;
          3'b001: alu_op = `ALU_SLL;
          3'b010: alu_op = `ALU_SLT;
          3'b011: alu_op = `ALU_SLTU;
          3'b100: alu_op = `ALU_XOR;
          3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
          3'b110: alu_op = `ALU_OR;
          3'b111: alu_op = `ALU_AND;
        endcase
        if (!(funct7 == 7'b0000000 || (funct7 == 7'b0100000 && (funct3 == 3'b000 || funct3 == 3'b101))))
          illegal = 1;
      end
      `OP_IMM: begin
        reg_write = 1; uses_rs1 = 1; alu_src_b = 1;
        case (funct3)
          3'b000: alu_op = `ALU_ADD;
          3'b001: alu_op = `ALU_SLL;
          3'b010: alu_op = `ALU_SLT;
          3'b011: alu_op = `ALU_SLTU;
          3'b100: alu_op = `ALU_XOR;
          3'b101: alu_op = funct7[5] ? `ALU_SRA : `ALU_SRL;
          3'b110: alu_op = `ALU_OR;
          3'b111: alu_op = `ALU_AND;
        endcase
        if (funct3 == 3'b001 && funct7 != 7'b0000000) illegal = 1;
        if (funct3 == 3'b101 && !(funct7 == 7'b0000000 || funct7 == 7'b0100000)) illegal = 1;
      end
      `OP_LOAD: begin   // lw only
        reg_write = 1; mem_read = 1; mem_to_reg = 1; uses_rs1 = 1; alu_src_b = 1;
        if (funct3 != 3'b010) illegal = 1;
      end
      `OP_STORE: begin  // sw only
        mem_write = 1; uses_rs1 = 1; uses_rs2 = 1; alu_src_b = 1;
        if (funct3 != 3'b010) illegal = 1;
      end
      `OP_BRANCH: begin
        branch = 1; uses_rs1 = 1; uses_rs2 = 1;
        if (funct3 == 3'b010 || funct3 == 3'b011) illegal = 1;
      end
      `OP_JAL:   begin reg_write = 1; jal = 1; end
      `OP_JALR:  begin
        reg_write = 1; jalr = 1; uses_rs1 = 1; alu_src_b = 1;
        if (funct3 != 3'b000) illegal = 1;
      end
      `OP_LUI:   begin reg_write = 1; alu_src_b = 1; alu_a_sel = 2'd2; end
      `OP_AUIPC: begin reg_write = 1; alu_src_b = 1; alu_a_sel = 2'd1; end
      default:   illegal = 1;
    endcase

    // An illegal instruction must never touch architectural state
    if (illegal) begin
      reg_write = 0; mem_read = 0; mem_write = 0; branch = 0; jal = 0; jalr = 0;
    end
  end
endmodule
