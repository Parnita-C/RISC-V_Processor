# 5-Stage Pipelined RISC-V Processor (RV32I) in SystemVerilog

A synthesizable-style, 5-stage pipelined RISC-V (RV32I subset) CPU with data forwarding, load-use hazard detection, control-hazard flushing, and a built-in **error-processing unit** that traps illegal instructions, misaligned accesses, and out-of-range memory accesses. Includes a self-checking testbench and directed test programs, simulated with Icarus Verilog.

The microarchitecture follows the classic 5-stage RISC-V pipeline (Patterson & Hennessy, *Computer Organization and Design: RISC-V Edition*) as taught in UC Davis EEC 170 (Computer Architecture).

---

## Table of Contents
1. [Features](#features)
2. [Architecture](#architecture)
3. [Supported Instructions](#supported-instructions)
4. [Hazard Handling](#hazard-handling)
5. [Error-Processing Unit](#error-processing-unit)
6. [Memory System](#memory-system)
7. [Repository Layout](#repository-layout)
8. [Getting Started](#getting-started)
9. [Verification](#verification)
10. [Module Reference](#module-reference)
11. [Design Decisions](#design-decisions)
12. [Limitations and Future Work](#limitations-and-future-work)
13. [Troubleshooting](#troubleshooting)
14. [References](#references)

---

## Features

| Area | What is implemented |
|---|---|
| Pipeline | 5 stages: IF, ID, EX, MEM, WB, with IF/ID, ID/EX, EX/MEM, MEM/WB pipeline registers |
| ISA | RV32I subset (see table below), 32 x 32-bit register file with `x0` hardwired to zero |
| ALU | `add sub and or xor sll srl sra slt sltu` (all RV32I arithmetic, logic, shift, and compare operations) |
| Forwarding | EX/MEM to EX and MEM/WB to EX, for both ALU operands; register-file write-through (WB to ID in the same cycle) |
| Hazards | 1-cycle stall on load-use; branches and jumps resolved in EX with a 2-instruction flush when taken (predict not-taken) |
| Error unit | Illegal instruction, misaligned branch/jump target, misaligned `lw`/`sw`, data address out of range. Faulting instruction is squashed, the core halts, and `err_code` / `err_pc` are latched |
| Verification | Self-checking testbench, a 36-instruction directed program, and 5 fault-injection programs |

---

## Architecture

### Block diagram

```
        IF               ID                 EX                    MEM            WB
   +---------+      +----------+      +--------------+      +-----------+   +--------+
   |  PC     |      | Control  |      | Fwd mux A/B  |      |  Data     |   | WB mux |
   |  +4     | IF/ID| RegFile  | ID/EX| ALU          |EX/MEM|  Memory   |MEM| (ALU / |
   |  IMEM   |=====>| ImmGen   |=====>| Branch cmp   |=====>|  (lw/sw)  |/WB|  load) |
   +---------+      | Hazard   |      | Target adder |      +-----------+===>+--------+
        ^           +----------+      | ERROR UNIT   |                          |
        |                             +--------------+                          |
        |   redirect_pc (taken branch / jal / jalr)                             |
        +-----------------------------<-----------+          wb_data -> RegFile +
                                                   |          wb_data -> forwarding
                       forwarding unit  <----------+          ex_mem_result -> forwarding
```

### Stage responsibilities

| Stage | Work done | Key signals (in `cpu.sv`) |
|---|---|---|
| **IF** | Read instruction at `pc`; compute `pc + 4`; choose next PC (`redirect ? target : pc+4`) | `pc`, `if_instr`, `pc_next` |
| **ID** | Decode, read registers (with write-through), generate immediate, detect load-use hazard | `c_*` control signals, `id_imm`, `stall` |
| **EX** | Forward operands, ALU, branch comparison, branch/jump target, error checks | `fwd_a`, `fwd_b`, `alu_y`, `branch_taken`, `target`, `trap` |
| **MEM** | `lw` / `sw` access to data memory | `ex_mem_*`, `mem_rdata` |
| **WB** | Select ALU result or loaded data, write register file | `wb_data`, `wb_we`, `wb_rd` |

### Pipeline timing (no hazards)

```
cycle:      1    2    3    4    5    6    7
instr 1:    IF   ID   EX   MEM  WB
instr 2:         IF   ID   EX   MEM  WB
instr 3:              IF   ID   EX   MEM  WB
```

---

## Supported Instructions

| Type | Instructions | Notes |
|---|---|---|
| R-type | `add sub sll slt sltu xor srl sra or and` | `sub`/`sra` use funct7 = `0100000` |
| I-type ALU | `addi slti sltiu xori ori andi slli srli srai` | Shift-immediate funct7 is validated |
| Load / Store | `lw`, `sw` | Word accesses only; other widths are flagged illegal |
| Branch | `beq bne blt bge bltu bgeu` | Resolved in EX |
| Jump | `jal`, `jalr` | Link value (`pc + 4`) written to `rd`; `jalr` clears target bit 0 |
| Upper immediate | `lui`, `auipc` | |

Anything else (including `fence`, `ecall`, `lb/lh/lbu/lhu`, `sb/sh`, malformed funct fields) is treated as an **illegal instruction** and handled by the error unit.

---

## Hazard Handling

### 1. Data hazards: forwarding

The forwarding unit compares source registers in EX against destination registers in EX/MEM and MEM/WB. The EX/MEM result has priority (it is the most recent).

| `forward_a` / `forward_b` | Source |
|---|---|
| `2'b00` | Register-file value read in ID |
| `2'b10` | EX/MEM result (`ex_mem_result`) |
| `2'b01` | MEM/WB write-back value (`wb_data`, which is the load data for `lw`) |

Forwarding is suppressed when the destination is `x0`. A producer three instructions ahead is covered by the register file's **write-through bypass** (a register read in ID sees a value being written back in the same cycle, the same effect as the "write in the first half, read in the second half" trick).

### 2. Data hazards: load-use stall

A `lw` result is not available until MEM, so an instruction in ID that needs it must wait one cycle. `hazard_unit.sv` detects this (using `uses_rs1` / `uses_rs2` from the decoder so unrelated instructions are not stalled). The PC and IF/ID register hold, and a bubble is inserted into ID/EX. After the stall, the value is forwarded from MEM/WB.

```
lw   x15, 0(x0)    IF  ID  EX  MEM WB
add  x16,x15,x15       IF  ID  --  EX  MEM WB     (1 stall cycle, then MEM/WB -> EX forward)
```

WAR and WAW hazards cannot occur in this in-order pipeline (all instructions take 5 stages, reads happen in ID, writes in WB), so no logic is needed for them.

### 3. Control hazards: branches and jumps

Branches and jumps resolve in EX. The pipeline implicitly predicts **not taken** and keeps fetching sequentially. When a branch is taken (or on any `jal` / `jalr`), the two younger instructions in IF/ID and ID/EX are flushed to bubbles and the PC is redirected, giving a 2-cycle penalty. Branch operands come from the forwarding muxes, so back-to-back dependencies work.

### 4. Structural hazards

None: separate instruction and data memories, and a register file with two read ports and one write port.

---

## Error-Processing Unit

`error_unit.sv` runs in the EX stage. If it flags a fault, the core:

1. squashes the faulting instruction (no register write, no memory write, no redirect),
2. flushes the younger instructions in IF and ID,
3. lets older instructions already in MEM/WB finish,
4. stops fetching, sets `halted`, and latches `err_code` and `err_pc` (the PC of the faulting instruction).

Priority when multiple faults coincide is top to bottom:

| Code | Name | Condition |
|---|---|---|
| 1 | `ERR_ILLEGAL` | Unsupported or malformed instruction |
| 2 | `ERR_FETCH_ALIGN` | Taken branch / `jal` / `jalr` target is not 4-byte aligned |
| 3 | `ERR_LOAD_ALIGN` | `lw` address is not word aligned |
| 4 | `ERR_STORE_ALIGN` | `sw` address is not word aligned |
| 5 | `ERR_MEM_FAULT` | Data address is outside data memory |

Codes are defined in `rtl/defs.vh`. Only the first error is recorded.

---

## Memory System

| Memory | Size (default) | Behavior |
|---|---|---|
| Instruction memory (`imem.sv`) | 256 words (1 KiB) | Asynchronous read, loaded with `$readmemh` from a hex file, NOP-filled elsewhere |
| Data memory (`dmem.sv`) | 256 words (1 KiB) | Synchronous write, asynchronous read, zero-initialized |

Sizes are parameters on `cpu` (`IMEM_WORDS`, `DMEM_WORDS`) and the program file is the `HEX` parameter. The reset PC is `0x00000000`. The error unit derives its out-of-range limit from `DMEM_WORDS`.

---

## Repository Layout

```
.
├── README.md
├── Makefile
├── rtl/
│   ├── defs.vh              ALU ops, error codes, opcodes, NOP
│   ├── cpu.sv               Top level: pipeline registers and stage logic
│   ├── alu.sv               ALU
│   ├── control.sv           Main decoder + illegal-instruction detection
│   ├── imm_gen.sv           Immediate generator (I/S/B/U/J)
│   ├── regfile.sv           32x32 register file, x0 = 0, write-through
│   ├── forwarding_unit.sv   EX-stage forwarding select
│   ├── hazard_unit.sv       Load-use stall detection
│   ├── error_unit.sv        Fault detection and error codes
│   ├── imem.sv              Instruction memory
│   └── dmem.sv              Data memory
├── tb/
│   └── tb.sv                Self-checking testbench
└── programs/
    ├── main.hex             36-instruction directed test
    └── err_*.hex            5 fault-injection programs
```

---

## Getting Started

### Requirements
- [Icarus Verilog](https://steveicarus.github.io/iverilog/) 11 or newer (developed with 12.0)
- [GTKWave](https://gtkwave.sourceforge.net/) (optional, for waveforms)
- VS Code with a SystemVerilog extension (for example *Verilog-HDL/SystemVerilog* by mshr-h) is recommended

Install on Ubuntu/Debian: `sudo apt install iverilog gtkwave`. On macOS: `brew install icarus-verilog gtkwave`. On Windows, use the Icarus Verilog installer or WSL.

### Build and run (from the repository root)

```bash
make            # compile and run all tests
make wave       # open waveforms in GTKWave
make clean
```

Or manually:

```bash
iverilog -g2012 -I rtl -o sim rtl/*.sv tb/tb.sv
vvp sim
gtkwave wave.vcd
```

### Expected output

```
PASS illegal          trapped code=1 at pc=4
PASS load_align       trapped code=3 at pc=4
PASS store_align      trapped code=4 at pc=4
PASS mem_fault        trapped code=5 at pc=4
PASS fetch_align      trapped code=2 at pc=4

ALL TESTS PASSED
```

### Running your own program
1. Assemble RV32I code to a hex file with one 32-bit word per line (for example with the RISC-V GNU toolchain: `riscv64-unknown-elf-as -march=rv32i`, then `objcopy -O binary` and convert to word-per-line hex).
2. Change the `HEX` parameter of the `cpu` instance in `tb/tb.sv`, or pass `-P` for a top-level parameter.
3. Add checks for the registers you expect, using `dut.u_rf.regs[n]`.

---

## Verification

`tb/tb.sv` is self-checking: it prints `PASS`/`FAIL` for each case and ends with `ALL TESTS PASSED` or a failure count.

### Directed program: `programs/main.hex`

Exercises every ALU operation, forwarding, the load-use stall, taken and not-taken branches, `jal`, and `jalr`. Registers and memory are compared with expected values after 120 cycles.

| Idx | Instruction | Purpose / expected result |
|---|---|---|
| 0-1 | `addi x1,x0,5` ; `addi x2,x0,10` | Setup |
| 2 | `add x3,x1,x2` | x3 = 15 (EX/MEM and MEM/WB forwarding) |
| 3 | `sub x4,x2,x1` | x4 = 5 |
| 4-6 | `and x5` / `or x6` / `xor x7` | 10 / 15 / 15 |
| 7 | `sll x8,x1,x1` | x8 = 160 |
| 8 | `addi x10,x0,-16` | x10 = 0xFFFFFFF0 |
| 9-10 | `srai x11,x10,2` ; `srli x12,x10,28` | 0xFFFFFFFC (arithmetic) / 15 (logical) |
| 11-12 | `slt x13,x10,x1` ; `sltu x14,x10,x1` | 1 (signed) / 0 (unsigned) |
| 13-15 | `sw x3,0(x0)` ; `lw x15,0(x0)` ; `add x16,x15,x15` | Store/load, **load-use stall**, x16 = 30 |
| 16-17 | `lui x17,0x12345` ; `auipc x18,0` | 0x12345000 / 68 |
| 18-20 | `beq x1,x1,+8` skipping `addi x19,x0,99` | Taken branch flush; x19 stays 0, x20 = 7 |
| 21-22 | `bne x1,x1,+8` ; `addi x21,x0,8` | Not-taken; x21 = 8 |
| 23-24 | `jal x22,+8` skipping `addi x23,x0,99` | x22 = 96 (link), x23 stays 0 |
| 25-26 | `addi x25,x0,120` ; `jalr x26,0(x25)` | Forwarded `jalr` operand; x26 = 108 |
| 30 | `addi x28,x0,1` (at address 120) | Jump landed correctly; x27 stays 0 |
| 31-34 | `blt` taken (skips x29), `bltu` not taken, `addi x30,x0,3` | x29 = 0, x30 = 3 |
| 35 | `jal x0,0` | End-of-program loop |

### Fault-injection programs: `programs/err_*.hex`

Each program triggers exactly one fault at PC = 4 and the testbench checks the error code, the PC, and that the instruction after the fault never executed.

| File | Fault injected | Expected code |
|---|---|---|
| `err_illegal.hex` | `0xFFFFFFFF` | 1 |
| `err_fetch_align.hex` | `jal x0,+6` (target 0x0A) | 2 |
| `err_load_align.hex` | `lw` from address 2 | 3 |
| `err_store_align.hex` | `sw` to address 6 | 4 |
| `err_mem_fault.hex` | `lw` from 0x1000 (beyond 1 KiB) | 5 |

### Not yet covered
No randomized or constrained-random stimulus, no functional coverage, and no assertions or formal checks yet. See [Future Work](#limitations-and-future-work).

---

## Module Reference

| Module | Inputs / outputs (summary) | Role |
|---|---|---|
| `cpu` | `clk, rst` / `halted, err_code, err_pc` | Top level, pipeline registers |
| `alu` | `a, b, op` / `y, zero` | Arithmetic, logic, shifts, compares |
| `control` | `instr` / control bits + `illegal` | Decode and validity check |
| `imm_gen` | `instr` / `imm` | I, S, B, U, J immediates |
| `regfile` | read addrs, write port / two read data | Registers with write-through |
| `forwarding_unit` | EX source regs, EX/MEM and MEM/WB dests / `forward_a/b` | Operand forwarding select |
| `hazard_unit` | ID/EX load info, IF/ID sources / `stall` | Load-use detection |
| `error_unit` | EX-stage info / `trap, code` | Fault detection |
| `imem`, `dmem` | address (and write port) / data | Memories |

---

## Design Decisions

- **Branch resolution in EX** (as drawn in the 5-stage RISC-V pipeline diagram): simpler forwarding at the cost of a 2-cycle taken-branch penalty. Moving the comparator to ID would cut the penalty to 1 cycle but needs forwarding into ID and an extra stall for branch-after-load.
- **Link value computed in EX**: `jal` / `jalr` write `pc + 4` through the normal ALU-result path, so the forwarding unit needs no special case.
- **Faults detected in EX**: all fault conditions (illegal bit from decode, target, address) are known there; younger instructions are still speculative and are safely flushed.
- **Illegal instructions are neutralized in decode**: control signals that touch state are cleared when `illegal` is set, so a fault can never partially execute.
- **Halt on first error**: keeps the behavior deterministic and easy to check in simulation; there is no trap vector or CSR state.

---

## Limitations and Future Work

- RV32I subset only: no byte/halfword loads and stores, `fence`, `ecall`/`ebreak`, or CSRs
- No M extension (hardware multiply/divide), no compressed instructions
- No dynamic branch prediction (predict-not-taken only)
- No caches or virtual memory; memories are ideal, single-cycle, and small
- Instruction fetch wraps around at the end of instruction memory (no instruction-fetch fault)
- Verification so far is directed testing. Planned: constrained-random instruction streams with a reference model (scoreboard), functional coverage of hazard combinations, and SystemVerilog assertions or a UVM environment
- Possible extensions: M extension, 2-bit dynamic branch predictor, trap vector with CSRs, formal checks of the forwarding logic

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `sorry: constant selects in always_* processes are not currently supported` | Harmless Icarus Verilog warning for `always_comb` blocks. Simulation results are unaffected |
| `$readmemh ... Not enough words in the file for the requested range` | Harmless: program shorter than memory; the rest is NOP-filled |
| `Unable to open input file` for `vvp` | Compile step failed; re-run `iverilog` without piping its output and read the first real error |
| `Unknown module type` | Pass every RTL file: `rtl/*.sv`, and include `-I rtl` for `defs.vh` |
| Hex file not found | Run from the repository root so `programs/...` paths resolve |

---

## References
- D. Patterson and J. Hennessy, *Computer Organization and Design: RISC-V Edition*
- The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA (RV32I)
- UC Davis EEC 170 (Computer Architecture) lecture material on the 5-stage pipeline, hazards, and forwarding

## Author
Parnita Reddy Chowtoori, B.S. Computer Engineering, UC Davis
