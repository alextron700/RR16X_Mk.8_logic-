# RR16X System (Mk.8.2)

A custom, extensible 16-bit CPU architecture built from scratch.

RR16X is designed around two goals:

Straightforward to program
Capable enough to be more than a retro toy

The project includes the CPU architecture, a custom assembler, a C++ emulator, a SystemVerilog implementation, and an extensible peripheral model.

If you know C++, you can build and integrate additional hardware extensions.

# 🚀 Getting Started
An annotated snippet of RR16X assembly (the assembler will accept this as-is): 
```asm
STJ start
JMP
text:
HEX 0048,0065,006C,006C,006F,0020,0057,006F,0072,006C,0064,0021,0000 ; "Hello World!\0" as ascii hex values 
start:
ADD R3 0x0000 text 


.stream_loop:
LDM R0 M$[R3]
STJ .string_done
JEQ R0 0x0000 ; Break stream loops at terminating null byte word
EAM.SET 0x07FF
STM M$[0xFFFF] R0 ; Write R0 to UART. Low byte will be printed to terminal 
EAM.SET 0x0000
ADD R3 R3 0x0001 ; Increment string buffer offset tracker index pointer
STJ .stream_loop
JMP
.string_done:

HLT
```
prints "Hello World!" to the terminal. 
The basic RR16X development pipeline is:
```
RR16X Assembly Source
        │
        ▼
 hybrid_assembler
        │
        ▼
 .txt / .bin / .hex
        │
        ▼
 RR16X Emulator
        │
        ▼
   RR16X Program
```

You write an RR16X assembly program, assemble it into machine code, and then run that machine code using the emulator.

# Prerequisites - General 
Required
- A text editor capable of saving plain-text files
- A C compiler
- A C++ compiler
- Optional
- A Verilog/SystemVerilog simulator, such as Icarus Verilog 12.0
## 🪟 Windows
Option A — Visual Studio

Prerequisite: Visual Studio 2022 with the Desktop development with C++ workload.

Open RR16X_EMULATOR.sln in Visual Studio.
Select either Debug or Release.
Build the solution with Ctrl + Shift + B.
Compile the assembler using the Visual Studio Developer Command Prompt:
`
cl hybrid_assembler.c
`

This produces the assembler executable.

Option B — MinGW / GCC

From the repository root:
```
gcc hybrid_assembler.c -o hybrid_assembler.exe
g++ RR16X_EMULATOR/*.cpp -o RR16X_EMULATOR.exe
```
Run the emulator

For a first run, use IntegrationTest.asm:
```
hybrid_assembler.exe 
RR16X_EMULATOR.exe
```

When the emulator asks for the program file, enter the path to the file produced by the assembler.

For a second system-level test, repeat the process with:
```
hybrid_assembler.exe torture.asm torture.hex
RR16X_EMULATOR.exe
```

Running both IntegrationTest.asm and torture.asm is recommended for your first setup.

## 🐧 Linux / macOS
Prerequisites

You will need:
```
gcc
g++
make (optional)
```
Compile the assembler
```bash
gcc hybrid_assembler.c -o hybrid_assembler
```
Compile the emulator
```
g++ RR16X_EMULATOR/*.cpp -o rr16x_emulator
```
Run the first test
```
./hybrid_assembler IntegrationTest.asm IntegrationTest.hex
./rr16x_emulator
```

When prompted, provide the path to the file produced by the assembler.

Then repeat with:
```
./hybrid_assembler 
./rr16x_emulator
```
## interpreting the trace of hybrid_assembler.c
the trace it produces may look daunting, but don't worry. There is only 1 line you can ctrl+F for to know your program assembled successfully:
`
Success! Saved to 
`
followed by the name of your hex file. 

# 📄 Assembler and Emulator File Formats

The assembler accepts:
`
.asm
.txt
`
NOTE: .asm is preferred
The assembler can produce:
`
.txt
.bin
.hex
`
NOTE: .hex is preferred
The emulator accepts:
`
.txt
.bin
.hex
`
NOTE: .hex is preferred 
This allows the assembled machine code to be represented in several formats while using the same RR16X execution pipeline.

Example assembler output

Assembler Output Example

# 🧠 System Specifications
```
CPU
8 × 16-bit general-purpose registers
Registers can be used as operands wherever an instruction accepts a register.
16-bit main ALU
Variable-width instructions
Fixed 16-bit base word
0–2 additional immediate words
Memory
Extended Addressing Module
Provides up to 256 MB of addressable memory.
16-bit word-addressable memory
Memory is addressed in 16-bit words rather than 8-bit bytes.
Independent program and data banks
Code can execute from one bank while accessing data in another.
Control Flow
256-slot return address buffer
CAL pushes and offsets return addresses.
RET retrieves the return address and transfers execution back to the caller.
```
🔧 What's Included
Assembler
`
hybrid_assembler.c
`
The custom RR16X assembler written in C.

It converts RR16X assembly source into machine-code output that can be loaded by the emulator.

Emulator
`
RR16X_EMULATOR/
`
A C++ software implementation of the RR16X system.

The emulator provides a way to develop and test RR16X programs without requiring physical CPU hardware.

Hardware Implementation
`
design.sv
`
`
testbench.sv
`
SystemVerilog implementation and testbench for the RR16X processor.

ABI

ABI.md

Application Binary Interface documentation describing the conventions used by RR16X software.

🔌 Extension Hardware

RR16X is designed to be extensible.

The current system includes:
```
Timer
Timer.cpp
Timer.h
DMA
DMA.cpp
DMA.h
INT32 Coprocessor
WideIntCoprocessor.cpp
WideIntCoprocessor.h
FP32 Coprocessor
FP32Coprocessor.cpp
FP32Coprocessor.h
Multiplier
Multiplier.cpp
Multiplier.h
Interrupt Enhancer
InterruptEnhancer.cpp
InterruptEnhancer.h
UART
UART.cpp
UART.h
```
Additional extension hardware should inherit from the AbstractPeripheral class.

This allows new peripherals and hardware functionality to be integrated into the RR16X system without changing the fundamental CPU architecture.
```
📁 Repository Structure
RR16X_Mk.8_logic-/
│
├── RR16X_EMULATOR/
│   └── C++ emulator and peripheral implementations
│
├── RR16X_EMULATOR.sln
│   └── Visual Studio solution
│
├── hybrid_assembler.c
│   └── RR16X assembler
│
├── IntegrationTest.asm
│   └── System integration test
│
├── torture.asm
│   └── Stress / instruction testing
│
├── design.sv
│   └── SystemVerilog CPU implementation
│
├── testbench.sv
│   └── SystemVerilog testbench
│
└── ABI.md
    └── Application Binary Interface documentation
```
# 📖 Documentation

The README is intended to get you up and running.

For detailed technical information, see the RR16X Wiki:

RR16X Wiki

The Wiki contains deeper information about the architecture, instruction set, assembler, memory model, ABI, and extensions.

# 🧭 Where to Go Next
I want to write RR16X programs

Start with:

- IntegrationTest.asm
- torture.asm
- The assembler documentation
- The instruction-set documentation
- I want to understand the CPU

Start with the system specifications above, then move to the architecture and ISA documentation in the Wiki.

I want to work on the emulator

Start with:
`
RR16X_EMULATOR/
`

The emulator also contains the implementations of the system's peripheral extensions.

I want to work on the hardware

Start with:
```
design.sv
testbench.sv
```
I want to create an extension

Start with the existing peripheral implementations and AbstractPeripheral. ( See the Extension API on the wiki For how to hook it up with the emulator ) 

Current Architecture Version

RR16X Mk.8.2
