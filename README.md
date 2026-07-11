# RR16X system
A simple 16-bit CPU with extensions and sample assembly code. 
-----------------------------------
SYSTEM SPECIFICATIONS:
- 8x 16-bit GENERAL PURPOSE REGISTERS ( Can be used in any operation as any operand that accepts a register)
- 16-bit main ALU
- Extended Addressing Module to greatly extend addressing capability, here you have 256 MB of addressable memory
- Independent program and data bank, meaning a program can execute in any bank, and address memory in any bank, regardless of if they're the same bank
- 256 slots for return addresses in the return address buffer (CAL pushes and offsets, RET pops to the program counter)
- Variable-width instructions, fixed 16-bit base word plus 0 - 2 immediate words
- Memory is addressable in 16-bit words. Not 8-bit bytes. 
-------------------------------------
WHAT'S INCLUDED:
- ASSEMBLER (hybrid_assembler.c)
- EMULATOR  (RR16X_EMULATOR)
- SAMPLE ASSEMBLY PROGRAMS (allSystensTest.asm , test.txt, torture.asm)
- VERILOG IMPLEMENTATION (design.sv, testbench.sv)
---------------------------------------
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


# GETTING STARTED
1) Download and compile the contents of the RR16X_EMULATOR folder
2) Download and compile hybrid_assembler.c
3) Assemble one of the sample programs with hybrid_assembler.c
4) feed the output of hybrid_assembler.c into RR16X_EMULATOR.cpp
