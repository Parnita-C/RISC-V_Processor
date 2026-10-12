// Data forwarding into the EX stage.
// 2'b00 = register file value, 2'b10 = EX/MEM result, 2'b01 = MEM/WB (write-back) value
module forwarding_unit (
  input  logic [4:0] id_ex_rs1, id_ex_rs2,
  input  logic [4:0] ex_mem_rd, mem_wb_rd,
  input  logic       ex_mem_reg_write, mem_wb_reg_write,
  output logic [1:0] forward_a, forward_b
);
  always_comb begin
    forward_a = 2'b00;
    if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs1)       forward_a = 2'b10;
    else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs1)  forward_a = 2'b01;

    forward_b = 2'b00;
    if (ex_mem_reg_write && ex_mem_rd != 0 && ex_mem_rd == id_ex_rs2)       forward_b = 2'b10;
    else if (mem_wb_reg_write && mem_wb_rd != 0 && mem_wb_rd == id_ex_rs2)  forward_b = 2'b01;
  end
endmodule
