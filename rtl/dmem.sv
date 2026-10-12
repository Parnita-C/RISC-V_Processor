// Data memory: word-addressed RAM, sync write, async read. Range/alignment are checked by the error unit.
module dmem #(parameter WORDS = 256) (
  input  logic        clk, we,
  input  logic [31:0] addr, wdata,
  output logic [31:0] rdata
);
  localparam AW = $clog2(WORDS);
  logic [31:0] mem [0:WORDS-1];
  integer i;
  initial for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'b0;
  always_ff @(posedge clk) if (we) mem[addr[AW+1:2]] <= wdata;
  assign rdata = mem[addr[AW+1:2]];
endmodule
