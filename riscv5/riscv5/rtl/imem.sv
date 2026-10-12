// Instruction memory: word-addressed ROM, async read, loaded from a hex file (one 32-bit word per line)
module imem #(parameter WORDS = 256, parameter HEX = "programs/main.hex") (
  input  logic [31:0] addr,
  output logic [31:0] instr
);
  localparam AW = $clog2(WORDS);
  logic [31:0] mem [0:WORDS-1];
  integer i;
  initial begin
    for (i = 0; i < WORDS; i = i + 1) mem[i] = 32'h00000013;   // NOP fill
    $readmemh(HEX, mem);
  end
  assign instr = mem[addr[AW+1:2]];
endmodule
