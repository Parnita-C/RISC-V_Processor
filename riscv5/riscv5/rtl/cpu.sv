`include "defs.vh"
// 5-stage pipelined RV32I core: IF | ID | EX | MEM | WB
//  - forwarding EX/MEM->EX and MEM/WB->EX, register-file write-through
//  - load-use stall (1 cycle)
//  - branches / jumps resolved in EX (2 bubbles when taken)
//  - error unit in EX: on a fault the instruction is squashed, younger ones are flushed,
//    older ones drain, and the core halts with err_code / err_pc latched.
module cpu #(
  parameter IMEM_WORDS = 256,
  parameter DMEM_WORDS = 256,
  parameter HEX        = "programs/main.hex"
)(
  input  logic        clk, rst,
  output logic        halted,
  output logic [2:0]  err_code,
  output logic [31:0] err_pc
);
  // =============================== IF ===============================
  logic [31:0] pc, if_instr, pc_next;
  logic        stall, flush, redirect;
  logic [31:0] redirect_pc;

  imem #(.WORDS(IMEM_WORDS), .HEX(HEX)) u_imem (.addr(pc), .instr(if_instr));
  assign pc_next = redirect ? redirect_pc : pc + 32'd4;

  always_ff @(posedge clk) begin
    if (rst)                                pc <= 32'b0;
    else if (!halted && (!stall || flush))  pc <= pc_next;
  end

  // ---- IF/ID ----
  logic [31:0] if_id_pc, if_id_instr;
  always_ff @(posedge clk) begin
    if (rst || flush || halted) begin if_id_pc <= 32'b0; if_id_instr <= `NOP; end
    else if (!stall)            begin if_id_pc <= pc;    if_id_instr <= if_instr; end
  end

  // =============================== ID ===============================
  logic [4:0]  id_rs1, id_rs2, id_rd;
  logic [31:0] id_rd1, id_rd2, id_imm;
  logic        c_reg_write, c_mem_read, c_mem_write, c_mem_to_reg, c_alu_src_b;
  logic [1:0]  c_alu_a_sel;
  logic [3:0]  c_alu_op;
  logic        c_branch, c_jal, c_jalr, c_uses_rs1, c_uses_rs2, c_illegal;

  assign id_rs1 = if_id_instr[19:15];
  assign id_rs2 = if_id_instr[24:20];
  assign id_rd  = if_id_instr[11:7];

  control u_ctrl (.instr(if_id_instr),
    .reg_write(c_reg_write), .mem_read(c_mem_read), .mem_write(c_mem_write),
    .mem_to_reg(c_mem_to_reg), .alu_src_b(c_alu_src_b), .alu_a_sel(c_alu_a_sel),
    .alu_op(c_alu_op), .branch(c_branch), .jal(c_jal), .jalr(c_jalr),
    .uses_rs1(c_uses_rs1), .uses_rs2(c_uses_rs2), .illegal(c_illegal));
  imm_gen u_imm (.instr(if_id_instr), .imm(id_imm));

  // write-back signals (declared here, driven in WB)
  logic        wb_we;
  logic [4:0]  wb_rd;
  logic [31:0] wb_data;
  regfile u_rf (.clk(clk), .we(wb_we), .waddr(wb_rd), .wdata(wb_data),
                .raddr1(id_rs1), .raddr2(id_rs2), .rdata1(id_rd1), .rdata2(id_rd2));

  // ---- ID/EX ----
  logic [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
  logic [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
  logic [2:0]  id_ex_funct3;
  logic [3:0]  id_ex_alu_op;
  logic [1:0]  id_ex_alu_a_sel;
  logic        id_ex_reg_write, id_ex_mem_read, id_ex_mem_write, id_ex_mem_to_reg,
               id_ex_alu_src_b, id_ex_branch, id_ex_jal, id_ex_jalr, id_ex_illegal;

  always_ff @(posedge clk) begin
    if (rst || flush || stall) begin   // insert bubble
      id_ex_reg_write <= 0; id_ex_mem_read <= 0; id_ex_mem_write <= 0; id_ex_mem_to_reg <= 0;
      id_ex_branch <= 0; id_ex_jal <= 0; id_ex_jalr <= 0; id_ex_illegal <= 0;
      id_ex_alu_src_b <= 0; id_ex_alu_a_sel <= 0; id_ex_alu_op <= `ALU_ADD;
      id_ex_rd <= 0; id_ex_rs1 <= 0; id_ex_rs2 <= 0; id_ex_funct3 <= 0;
      id_ex_pc <= 0; id_ex_rs1_data <= 0; id_ex_rs2_data <= 0; id_ex_imm <= 0;
    end else begin
      id_ex_reg_write <= c_reg_write; id_ex_mem_read <= c_mem_read; id_ex_mem_write <= c_mem_write;
      id_ex_mem_to_reg <= c_mem_to_reg; id_ex_branch <= c_branch; id_ex_jal <= c_jal;
      id_ex_jalr <= c_jalr; id_ex_illegal <= c_illegal; id_ex_alu_src_b <= c_alu_src_b;
      id_ex_alu_a_sel <= c_alu_a_sel; id_ex_alu_op <= c_alu_op;
      id_ex_rd <= id_rd; id_ex_rs1 <= id_rs1; id_ex_rs2 <= id_rs2; id_ex_funct3 <= if_id_instr[14:12];
      id_ex_pc <= if_id_pc; id_ex_rs1_data <= id_rd1; id_ex_rs2_data <= id_rd2; id_ex_imm <= id_imm;
    end
  end

  // load-use hazard detection (ID stage)
  hazard_unit u_haz (.id_ex_mem_read(id_ex_mem_read), .id_ex_rd(id_ex_rd),
                     .if_id_rs1(id_rs1), .if_id_rs2(id_rs2),
                     .uses_rs1(c_uses_rs1), .uses_rs2(c_uses_rs2), .stall(stall));

  // =============================== EX ===============================
  logic [1:0]  fwd_a_sel, fwd_b_sel;
  logic [31:0] fwd_a, fwd_b, alu_a, alu_b, alu_y, ex_out, store_data;
  logic        alu_zero;
  logic        cmp_eq, cmp_lt, cmp_ltu, cond_met, branch_taken, redirect_req, trap;
  logic [31:0] target;
  logic [2:0]  trap_code;

  // ex_mem_* declared below
  logic [31:0] ex_mem_result, ex_mem_store;
  logic [4:0]  ex_mem_rd;
  logic        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write, ex_mem_mem_to_reg;

  forwarding_unit u_fwd (.id_ex_rs1(id_ex_rs1), .id_ex_rs2(id_ex_rs2),
    .ex_mem_rd(ex_mem_rd), .mem_wb_rd(wb_rd),
    .ex_mem_reg_write(ex_mem_reg_write), .mem_wb_reg_write(wb_we),
    .forward_a(fwd_a_sel), .forward_b(fwd_b_sel));

  always_comb begin
    case (fwd_a_sel) 2'b10: fwd_a = ex_mem_result; 2'b01: fwd_a = wb_data; default: fwd_a = id_ex_rs1_data; endcase
    case (fwd_b_sel) 2'b10: fwd_b = ex_mem_result; 2'b01: fwd_b = wb_data; default: fwd_b = id_ex_rs2_data; endcase
  end

  assign alu_a = (id_ex_alu_a_sel == 2'd1) ? id_ex_pc :
                 (id_ex_alu_a_sel == 2'd2) ? 32'b0   : fwd_a;
  assign alu_b = id_ex_alu_src_b ? id_ex_imm : fwd_b;
  alu u_alu (.a(alu_a), .b(alu_b), .op(id_ex_alu_op), .y(alu_y), .zero(alu_zero));

  // branch comparator
  assign cmp_eq  = (fwd_a == fwd_b);
  assign cmp_lt  = ($signed(fwd_a) < $signed(fwd_b));
  assign cmp_ltu = (fwd_a < fwd_b);
  always_comb begin
    case (id_ex_funct3)
      3'b000: cond_met =  cmp_eq;    // beq
      3'b001: cond_met = !cmp_eq;    // bne
      3'b100: cond_met =  cmp_lt;    // blt
      3'b101: cond_met = !cmp_lt;    // bge
      3'b110: cond_met =  cmp_ltu;   // bltu
      3'b111: cond_met = !cmp_ltu;   // bgeu
      default: cond_met = 1'b0;
    endcase
  end
  assign branch_taken = id_ex_branch && cond_met;
  assign redirect_req = branch_taken || id_ex_jal || id_ex_jalr;
  assign target       = id_ex_jalr ? ((fwd_a + id_ex_imm) & ~32'd1) : (id_ex_pc + id_ex_imm);
  assign ex_out       = (id_ex_jal || id_ex_jalr) ? (id_ex_pc + 32'd4) : alu_y;   // link value for jal/jalr
  assign store_data   = fwd_b;

  // ---- error-processing unit ----
  error_unit #(.DMEM_BYTES(DMEM_WORDS*4)) u_err (
    .illegal(id_ex_illegal), .redirect_req(redirect_req), .target(target),
    .mem_read(id_ex_mem_read), .mem_write(id_ex_mem_write), .addr(alu_y),
    .trap(trap), .code(trap_code));

  assign redirect    = redirect_req && !trap;
  assign redirect_pc = target;
  assign flush       = redirect || trap;       // squash younger instructions (IF/ID, ID/EX)

  always_ff @(posedge clk) begin
    if (rst) begin halted <= 0; err_code <= `ERR_NONE; err_pc <= 0; end
    else if (trap && !halted) begin halted <= 1; err_code <= trap_code; err_pc <= id_ex_pc; end
  end

  // ---- EX/MEM ----
  always_ff @(posedge clk) begin
    if (rst || trap) begin   // faulting instruction is squashed
      ex_mem_reg_write <= 0; ex_mem_mem_read <= 0; ex_mem_mem_write <= 0; ex_mem_mem_to_reg <= 0;
      ex_mem_rd <= 0; ex_mem_result <= 0; ex_mem_store <= 0;
    end else begin
      ex_mem_reg_write <= id_ex_reg_write; ex_mem_mem_read <= id_ex_mem_read;
      ex_mem_mem_write <= id_ex_mem_write; ex_mem_mem_to_reg <= id_ex_mem_to_reg;
      ex_mem_rd <= id_ex_rd; ex_mem_result <= ex_out; ex_mem_store <= store_data;
    end
  end

  // =============================== MEM ===============================
  logic [31:0] mem_rdata;
  dmem #(.WORDS(DMEM_WORDS)) u_dmem (.clk(clk), .we(ex_mem_mem_write), .addr(ex_mem_result),
                                     .wdata(ex_mem_store), .rdata(mem_rdata));

  // ---- MEM/WB ----
  logic [31:0] mem_wb_result, mem_wb_rdata;
  logic        mem_wb_mem_to_reg;
  always_ff @(posedge clk) begin
    if (rst) begin
      wb_we <= 0; wb_rd <= 0; mem_wb_result <= 0; mem_wb_rdata <= 0; mem_wb_mem_to_reg <= 0;
    end else begin
      wb_we <= ex_mem_reg_write; wb_rd <= ex_mem_rd; mem_wb_result <= ex_mem_result;
      mem_wb_rdata <= mem_rdata; mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
    end
  end

  // =============================== WB ===============================
  assign wb_data = mem_wb_mem_to_reg ? mem_wb_rdata : mem_wb_result;
endmodule
