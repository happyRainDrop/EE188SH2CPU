# SH-2 CPU Implementation
Ruth Berkun, Nerissa Finnen

## Introduction
This CPU is a cycle-accurate VHDL implementation of the Hitachi SH-2 RISC processor. The design implements all instructions except for multiplication and division-related instructions, and a number of multi-clock instructions. A list of unimplemented SH-2 RISC instructions are listed at the bottom of this page.

This code in this folder simulates a CPU and RAM. The CPU executes the instructions in `cpu_test_program.txt` and dumps the contents of the RAM into `cpu_mem_output.txt`. See "Instructions for Use" for more details.

`CPU_Testbench.vhd` simulates putting the instructions in `cpu_test_program.txt` into RAM. 
Then, once it is no longer being reset by `CPU_Testbench.vhd`, `CPUtoplevel.vhd` acts as the control unit, performing instruction decoding, memory accesses, and execution of the instructions in codespace.
The control unit interfaces to the entities in`SH2reg.vhd`, `SH2alu.vhd`, `SH2DMAU.vhd`, `SH2PMAU.vhd`. These entities combinationally compute outputs for the CPU based off control signals set by `CPUtoplevel.vhd`.

## Instructions for Use
You will need a VHDL simulator. One option is to download GHDL (and, optionally, GTKwave for waveform debugging) by following [this guide](https://drive.google.com/file/d/1qeKNoJdyquR7BhnvsPSp44wEk-42WmKS/view?usp=sharing).

Download the following files into your project directory (don’t need build.sh unless running GHDL):
```
reg.vhd
alu.vhd
mau.vhd
memory.vhd
SH2reg.vhd
SH2alu.vhd
SH2DMAU.vhd
SH2PMAU.vhd
CPUtoplevel.vhd
CPU_Testbench.vhd
build.sh
```

To run a program, type the opcodes in the file `cpu_test_program.txt`. The opcodes should be 32 bits long and each opcode should be on a separate line. Example programs we used to test our code are listed in the “Testing” section – you can directly copy paste those into `cpu_test_program.txt` to run them.

Note to programmers: You can see which opcode corresponds to each instruction, as well as a list of SH-2 instructions and what they do, in the [SuperH RISC Engine SH-1/SH-2 Programming Manual](https://antime.kapsi.fi/sega/files/h12p0.pdf). In particular, refer to tables 5.3-5.8 in pages 40-48.

Next, compile with `CPUtoplevel.vhd` as your top-level file, and `CPU_Testbench.vhd` as your testbench.
If you’re using GHDL: you can do that by running the following commands in terminal:
```
./build.sh
ghdl --elab-run -fsynopsys --std=08 CPU_Testbench --fst=CPUTest
gtkwave CPUTest.gtkw
```
(This is similar to what’s shown on the guide, except we have a bash file to compile all of our .vhd files in order. Also, the gtkwave command is optional if you’re not debugging – you only need to run the first two commands to run a program).

After the program has run, the contents of RAM memory will appear in the file `cpu_mem_output.txt`. 
The contents of that file should look something like this:
```
Memory Dump by Block (32 words each):
===============================
Addr 0, 0 at 00000000000000000000000000000000 index   0: XXXXXXXXXXXXXXXX1110000000000001
Addr 0, 1 at 00000000000000000000000000000100 index   4: XXXXXXXXXXXXXXXX1110000101000000
..
Addr 0, 255 at 00000000000000000000001111111100 index 1020: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
===============================
Addr 1, 0 at 00000000000000000000010000000000 index 1024: 10110101000001000000010000000001
…
Addr 1, 255 at 00000000000000000000011111111100 index 2044: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
===============================
Addr 2, 0 at 00000000000000000000100000000000 index 2048: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
..
Addr 2, 255 at 00000000000000000000101111111100 index 3068: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
===============================
Addr 3, 0 at 00000000000000000000110000000000 index 3072: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
Addr 3, 255 at 00000000000000000000111111111100 index 4092: XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

There are four blocks of memory, 32 bits per longword, 256 longwords long, and separated by “===============================”. 
The format of each line is:
Addr [index in decimal of block of memory] [index in decimal of longword within that block of memory] at [memory location in binary] index [memory location in hex]: [contents of memory location in (memory location)(memory location +1)(memory location +2)(memory location +3)].

More details in “Interface to Memory.” As a tester: just make sure your input hexcodes show up in the lower words of codespace (Addr 0, …  which is the first code block), and other memory locations hold what you expect.

## Interface to Memory ##
For addressing, we use the big endian data format specified in SuperH RISC Engine SH-1/SH-2 Programming Manual Section 3.2.

We have 4 blocks of memory. Each block of memory consists of 256 (adjustable) longwords. Longwords are 32 bits long and thus 4 addresses apart.

Our first block of memory is reserved as codespace. We put one instruction in the lower word each longword. Thus, when we increment our PC to go though codespace, we use PCx4 to find the right memory address.
Basically, the programmer and PC is thinking, I am putting an instruction at codespace 0, 1, 2, 3..., and the control unit is thinking, I need to grab the instructions from memory address 0, 4, 8...

Our second block of memory is reserved as data space and our third block of memory is reserved as stack space. It is up to the programmer to make sure data and stack information is only stored in their corresponding memory blocks. The fourth block of memory is not used.

Our finite state machine, in `CPUtoplevel.vhd` in the process `updatePCandIRandSetNextState,` handles all the memory interfacing. It is the only place we update the PC via setting Program Memory Access Unit control signals. And it is the only place where we set `WE` and `RE` signals that interface to our similated RAM in `memory.vhd`. 

The finite state machine has three states, one for before we've read in any instructions, one when we are actively executing a program, and one when we are done with the program. The first and last state open the address and data bus so that the testing unit can use it to write code to RAM or read the RAM to dump its contents.
In the second state, we perform memory accesses on the falling edge of the clock so that memory data and addresses can be precalculated during the rising edge of the clock (when we first fetch our instructions).

The finite state machine is a clocked process, as is the process where we set our control signals. Therefore, we make the `SH2AddressBus`, `SH2DataBus`, and `InstructionReg` update combinationally based on control signals. This way, we can change these signals multiple times in a clock. We can open the data bus to read in the IR on the rising edge of the clock, and set it to a register's value to store to memory on the falling edge of the clock, for example. `InstructionReg` is combinational so that it can immediately latch to the fetched instruction on the `SH2DataBus` bus.

## Pipelining ##
We have a two-stage pipeline: fetch, decode, and pre-calculated needed information on one clock, and execute on the following clock.
(Pre-calculating information includes calculating memory addresses/data bus values, memory accesses, determining which register to store things in, etc).

We have two processes to handle this two-stage pipeline: `matchInstruction` and `executeInstruction`.This is where our design becomes a bit flimsy. Earlier in our design when we were doing memory accesses during the following clock, we somehow needed the register outputs to update instantenously after setting a register select signal. So we unclocked the registers.
Now, with loads and stores happening during the `matchInstruction` first clock, all `exectueInstruction` does is set register store signals. A redesign could involve moving all the register store signals into `matchInstruction` and clocking the registers, so that the register outputs are updated on the next clock without need for another process.

For multi-clock instructions: We need the ability to cancel executions and halt the pipeline.
We do this by having signals to keep track of what multi-clock instruction we're on (`MultiClockReg`) and which clock of it we are on (`ClockTwo`, `ClockThree`). When we're on the second or third clock of a multi-clock instruction, we call `setDefaultControlSignals` to call a NOP and override any control signals trying to be set by the next instruction. We also hold the PC value if we're doing a pipeline halt.

Our `matchInstruction` process only updates on IR changes, so we have latched versions of our pipeline and `ClockTwo`, `ClockThree` signals that update on the rising edge of the clock. Again, a redesign with a single clocked `matchInstruction` process without the `executeInstruction` process could remove the need for this redundancy.

## Test Programs
***ALU Example***
| Opcode             | Instruction name         | Result immediately after instruction |
|--------------------|--------------------------|--------------------------------------|
| 0111000100000001   | ADD x00000001, R1        | R1 = x00000001                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000002                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000004                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000008                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000010                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000020                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000040                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000080                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000100                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000200                       |
| 0100000100000000   | SHLL R1                  | R1 = x00000400                       |
| 0111001000000001   | ADD x00000001, R2        | R2 = x00000001                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000002                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000004                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000008                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000010                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000020                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000040                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000080                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000100                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000200                       |
| 0100001000000000   | SHLL R2                  | R2 = x00000400                       |
| 0111000100000101   | ADD x00000005, R1        | R1 = x00000405                       |
| 0111001000000100   | ADD x00000004, R2        | R2 = x00000404                       |
| 0010000100101001   | AND R1, R2               | R1 = x00000404                       |
| 0100000100000100   | ROTL R1                  | R1 = x00000808                       |
| 0010001000010010   | MOV.L R1, @ R2           | RAM x0404 holds x0808                |

**End result:** RAM x0404 holds x00000808

***Data Transfer Example***
| Opcode             | Instruction name              | Result immediately after instruction      |
|--------------------|-------------------------------|-------------------------------------------|
| 1110000000000001   | MOV x01, R0                   | R0 = x00000001                            |
| 1110000101000000   | MOV x40, R1                   | R1 = x00000040                            |
| 0100000100000000   | SHLL R1                       | R1 = x00000080                            |
| 0100000100000000   | SHLL R1                       | R1 = x00000100                            |
| 0100000100000000   | SHLL R1                       | R1 = x00000200                            |
| 0100000100000000   | SHLL R1                       | R1 = x00000400                            |
| 1110001001000000   | MOV x40, R2                   | R2 = x00000040                            |
| 0100001000000000   | SHLL R2                       | R2 = x00000080                            |
| 0100001000000000   | SHLL R2                       | R2 = x00000100                            |
| 0100001000000000   | SHLL R2                       | R2 = x00000200                            |
| 0100001000000000   | SHLL R2                       | R2 = x00000400                            |
| 0111001000000100   | ADD x00000004, R2             | R2 = x00000404                            |
| 1110001110110101   | MOV xB5, R3                   | R3 = xFFFFFFB5                            |
| 0010000100110000   | MOV.B R3, @ R1                | RAM x0400 holds xB5XXXXXX                 |
| 0000000100100101   | MOV.W R2, @(R0,R1)            | RAM x0400 holds xB50404XX                 |
| 0010001000000100   | MOV.B R0, @–R2                | R2 = x00000403, RAM x0400 = xB5040401     |
| 0001000100010001   | MOV.L R1, @(1,R1)             | RAM x0404 holds x00000400                 |
| 0110010000100100   | MOV.B @R2+, R4                | R4 = x00000001, R2 = x0404                |
| 0101000000100000   | MOV.L @(0,R2), R0             | R0 = x00000400                            |
| 0100000000000001   | SHLR R0                       | R0 = x00000200                            |
| 0100000000000001   | SHLR R0                       | R0 = x00000100                            |
| 0100000000000001   | SHLR R0                       | R0 = x00000080                            |
| 0100000000000001   | SHLR R0                       | R0 = x00000040                            |
| 0100000000000001   | SHLR R0                       | R0 = x00000020                            |
| 0100000000000001   | SHLR R0                       | R0 = x00000010                            |
| 0100000000000001   | SHLR R0                       | R0 = x00000008                            |
| 0100000000000001   | SHLR R0                       | R0 = x00000004                            |
| 0000001100011101   | MOV.W @(R0,R1), R3            | R3 = x00000000                            |
| 0001000100110010   | MOV.L R3, @(2,R1)             | RAM x0408 holds x00000000                 |

**End result:** RAM x0400 = xB5040401, RAM x0404 = x00000400, RAM x0408 = x00000000

***JMP Example***
| Opcode             | Instruction name         | Result immediately after instruction       |
|--------------------|--------------------------|--------------------------------------------|
| 1110000000000001   | MOV x01, R0              | R0 = x00000001                              |
| 1110000101000000   | MOV x40, R1              | R1 = x00000040                              |
| 0100000100000000   | SHLL R1                  | R1 = x00000080                              |
| 0100000100000000   | SHLL R1                  | R1 = x00000100                              |
| 0100000100000000   | SHLL R1                  | R1 = x00000200                              |
| 0100000100000000   | SHLL R1                  | R1 = x00000400                              |
| 1110001001000000   | MOV x40, R2              | R2 = x00000040                              |
| 0100001000000000   | SHLL R2                  | R2 = x00000080                              |
| 0100001000000000   | SHLL R2                  | R2 = x00000100                              |
| 0100001000000000   | SHLL R2                  | R2 = x00000200                              |
| 0100001000000000   | SHLL R2                  | R2 = x00000400                              |
| 0111001000000100   | ADD x00000004, R2        | R2 = x00000404                              |
| 1110001110110101   | MOV xB5, R3              | R3 = xFFFFFFB5                              |
| 0010000100110000   | MOV.B R3, @ R1           | RAM x0400 holds xB5XXXXXX                   |
| 0000000100100101   | MOV.W R2, @(R0,R1)       | RAM x0400 holds xB50404XX                   |
| 0010001000000100   | MOV.B R0, @–R2           | R2 = x00000403, RAM x0400 = xB5040401       |
| 0001000100010001   | MOV.L R1, @(1,R1)        | RAM x0404 holds x00000400                   |
| 0110010000100100   | MOV.B @R2+, R4           | R4 = x00000001, R2 = x0404                  |
| 0101000000100000   | MOV.L @(0,R2), R0        | R0 = x00000400                              |
| 0100000000000001   | SHLR R0                  | R0 = x00000200                              |
| 0100000000000001   | SHLR R0                  | R0 = x00000100                              |
| 0100000000000001   | SHLR R0                  | R0 = x00000080                              |
| 0100000000000001   | SHLR R0                  | R0 = x00000040                              |
| 0100000000000001   | SHLR R0                  | R0 = x00000020                              |
| 0100000000101011   | JMP @R0                  | dummyPC = x00000020                         |
| 0001000100000011   | MOV.L R0, @(3,R1)        | RAM x040C holds x00000020                   |
| 0000000000001001   | NOP                      |                                            |
| ...                | NOPs continued           |                                            |
| 0100000000000001   | SHLR R0                  | R0 = x00000010                              |
| 0100000000000001   | SHLR R0                  | R0 = x00000008                              |
| 0100000000000001   | SHLR R0                  | R0 = x00000004                              |
| 0000001100011101   | MOV.W @(R0,R1),R3        | R3 = x00000000                              |
| 0001000100110010   | MOV.L R3, @(2,R1)        | RAM x0408 holds x00000000                   |

**End result:** RAM x0400 = xB5040401, RAM x0404 = x00000400, RAM x0408 = x00000000, RAM x040C = x00000020

***Pipeline Stall Example***
| Opcode             | Instruction name         | Result immediately after instruction       |
|--------------------|--------------------------|--------------------------------------------|
| 1110000000000001   | MOV x01, R0              | R0 = x00000001                              |
| 1110000101000000   | MOV x40, R1              | R1 = x00000040                              |
| 0100000100000000   | SHLL R1                  | R1 = x00000080                              |
| 0100000100000000   | SHLL R1                  | R1 = x00000100                              |
| 0100000100000000   | SHLL R1                  | R1 = x00000200                              |
| 0100000100000000   | SHLL R1                  | R1 = x00000400                              |
| 1110001001000000   | MOV x40, R2              | R2 = x00000040                              |
| 0100001000000000   | SHLL R2                  | R2 = x00000080                              |
| 0100001000000000   | SHLL R2                  | R2 = x00000100                              |
| 0100001000000000   | SHLL R2                  | R2 = x00000200                              |
| 0100001000000000   | SHLL R2                  | R2 = x00000400                              |
| 0111001000000100   | ADD x00000004, R2        | R2 = x00000404                              |
| 1110001110110101   | MOV xB5, R3              | R3 = xFFFFFFB5                              |
| 0010000100110000   | MOV.B R3, @ R1           | RAM x0400 holds xB5XXXXXX                   |
| 0000000100100101   | MOV.W R2, @(R0,R1)       | RAM x0400 holds xB50404XX                   |
| 0010001000000100   | MOV.B R0, @–R2           | R2 = x00000403, RAM x0400 = xB5040401       |
| 0100000100000111   | LDC.L @R1+, SR           | SR = x00000001, R1 = x0404                  |
| 0111000100001000   | ADD x00000008, R1        | R1 = x0000040C                              |
| 0100000100000011   | STC.L SR, @–R1           | R1 = x00000408, RAM x0408 holds x00000001   |
| 0010000100110110   | MOV.L R3, @–R1           | R1 = x00000404, RAM x0404 holds xFFFFFFB5   |

**End result:** RAM x0400 = xB5040401, RAM x0404 = xFFFFFFB5, RAM x0408 = x00000001

## Unimplemented Instructions
- SLEEP 
- CLRT
- RTE
- TRAPA
- CLRMAC
- LDS Rm,MACH
- LDS Rm,MACL
- LDS.L @Rm+,MACH
- LDS.L @Rm+,MACL
- STS MACH,Rn
- STS MACL,Rn
- STS.L MACH,@–Rn
- STS.L MACL,@–Rn
- DIV1 Rm,Rn
- DIV0S Rm,Rn
- DIV0U
- DMULS.L Rm,Rn
- DMULU.L Rm,Rn
- MAC.L @Rm+,@Rn+
- MAC.W @Rm+,@Rn+
- MUL.L Rm,Rn
- MULS.W Rm,Rn
- MULU.W Rm,Rn
