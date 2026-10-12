`include "defs.vh"
// Error-processing unit (EX stage). Detects faults and reports a trap + error code.
module error_unit #(parameter DMEM_BYTES = 1024) (
  input  logic        illegal,
  input  logic        redirect_req,    // taken branch / jal / jalr
  input  logic [31:0] target,
  input  logic        mem_read, mem_write,
  input  logic [31:0] addr,
  output logic        trap,
  output logic [2:0]  code
);
  always_comb begin
    code = `ERR_NONE;
    if (illegal)                                        code = `ERR_ILLEGAL;
    else if (redirect_req && target[1:0] != 2'b00)      code = `ERR_FETCH_ALIGN;
    else if (mem_read  && addr[1:0] != 2'b00)           code = `ERR_LOAD_ALIGN;
    else if (mem_write && addr[1:0] != 2'b00)           code = `ERR_STORE_ALIGN;
    else if ((mem_read || mem_write) && addr >= DMEM_BYTES) code = `ERR_MEM_FAULT;
    trap = (code != `ERR_NONE);
  end
endmodule
