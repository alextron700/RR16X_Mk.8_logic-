# RR16X system
A 16-bit CPU with extensions and sample assembly code. 
-----------------------------------
THE RR16X AT A GLANCE: 
RR16X is a 16-bit CPU built from scratch, built with two objectives: Be straightforward to program for, yet not be some retro toy. 
The RR16X is designed to be extensible, with extensions pre-installed. If you know C++, you can extend it. 

TO START, REQUISITE SOFTWARE:
- A text editor that can output a .txt file
- a recent C compiler 
- a recent C++ compiler
- optionally, an environment to run Verilog (Icarus Verilog 12.0)

# GETTING STARTED
1. Compile the emulator in `RR16X_EMULATOR/` with a C++ compiler.
2. Compile `hybrid_assembler.c` with a C compiler.
3. Assemble `IntegrationTest.asm`. ( it will prompt you to name your output hex file. You may name it however you wish, but the last 4 characters must be `.hex`)
4. Start the emulator.
5. Give the emulator the `.hex` file produced by the assembler.
6. Follow the emulator prompts.

hybrid_assembler can accept:
.txt, .asm

hybrid_assembler can produce:
.hex

The emulator can accept as input:
.hex

A sample dump from hybrid_assembler.c:
https://github.com/alextron700/RR16X_Mk.8_logic-/wiki/A-sample-dump-from-hybrid_assembler.c

-----------------------------------
SYSTEM SPECIFICATIONS:
- 8x 16-bit GENERAL PURPOSE REGISTERS ( Can be used in any operation as any operand that accepts a register)
- 16-bit main ALU
- Extended Addressing Module to greatly extend addressing capability, providing up to 256 MB of addressable memory
- Independent program and data bank, meaning a program can execute in any bank, and address memory in any bank, regardless of if they're the same bank
- 256 slots for return addresses in the return address buffer (CAL pushes and offsets, RET pops to the program counter)
- Variable-width instructions, fixed 16-bit base word plus 0 - 2 immediate words
- Memory is addressable in 16-bit words. Not 8-bit bytes. 
-------------------------------------
WHAT'S INCLUDED:
- ASSEMBLER (hybrid_assembler.c)
- EMULATOR  (RR16X_EMULATOR)
- SAMPLE ASSEMBLY PROGRAMS (allSystemsTest.asm , test.txt, torture.asm, IntegrationTest.asm)
- VERILOG IMPLEMENTATION (design.sv, testbench.sv)
---------------------------------------
FOR MORE TECHNICAL INFORMATION, SEE THE WIKI. AT: https://github.com/alextron700/RR16X_Mk.8_logic-/wiki



OTHER NOTES:
- INCLUDES EXTENSION HARDWARE
## EXTENSION HARDWARE:
- Timer (Timer.cpp, Timer.h)
- DMA (DMA.cpp, DMA.h)
- INT32 coprocessor (WideIntCoprocessor.cpp, WideIntCoprocessor.h)
- FP32 coprocessor (FP32Coprocessor.cpp, FP32Coprocessor.h)
- Multiplier (Multiplier.cpp, Multiplier.h)
- Interrupt Enhancer (InterruptEnhancer.cpp, InterruptEnhancer.h)
- UART (UART.cpp, UART.h)

NOTE: Additional Extension hardware should inherit from the AbstractPeripheral class. 



CURRENT ARCHITECTURE VERSION: RR16X Mk.8.2
