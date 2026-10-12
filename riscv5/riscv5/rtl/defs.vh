// ---------- ALU operations ----------
`define ALU_ADD  4'd0
`define ALU_SUB  4'd1
`define ALU_AND  4'd2
`define ALU_OR   4'd3
`define ALU_XOR  4'd4
`define ALU_SLL  4'd5
`define ALU_SRL  4'd6
`define ALU_SRA  4'd7
`define ALU_SLT  4'd8
`define ALU_SLTU 4'd9

// ---------- Error / trap codes ----------
`define ERR_NONE        3'd0
`define ERR_ILLEGAL     3'd1   // illegal / unsupported instruction
`define ERR_FETCH_ALIGN 3'd2   // branch/jump target not 4-byte aligned
`define ERR_LOAD_ALIGN  3'd3   // lw address not word aligned
`define ERR_STORE_ALIGN 3'd4   // sw address not word aligned
`define ERR_MEM_FAULT   3'd5   // data address outside data memory

// ---------- Opcodes ----------
`define OP_LUI    7'b0110111
`define OP_AUIPC  7'b0010111
`define OP_JAL    7'b1101111
`define OP_JALR   7'b1100111
`define OP_BRANCH 7'b1100011
`define OP_LOAD   7'b0000011
`define OP_STORE  7'b0100011
`define OP_IMM    7'b0010011
`define OP_REG    7'b0110011

`define NOP 32'h00000013   // addi x0, x0, 0
