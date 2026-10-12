// Load-use hazard: a load in EX whose rd is needed by the instruction in ID.
// Forwarding cannot help (data isn't read until MEM), so stall one cycle.
module hazard_unit (
  input  logic       id_ex_mem_read,
  input  logic [4:0] id_ex_rd, if_id_rs1, if_id_rs2,
  input  logic       uses_rs1, uses_rs2,
  output logic       stall
);
  assign stall = id_ex_mem_read && id_ex_rd != 0 &&
                 ((uses_rs1 && id_ex_rd == if_id_rs1) || (uses_rs2 && id_ex_rd == if_id_rs2));
endmodule
