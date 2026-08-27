# RR16X System (Mk.8.2)

A custom, extensible 16-bit CPU architecture built from scratch. Features a complete hardware ecosystem including a SystemVerilog implementation, a custom C assembler, a C++ emulator, and a peripheral extension model.

---

## 🛠️ System Specifications

* **Registers:** 8x 16-bit General Purpose Registers.
* **ALU:** 16-bit main Arithmetic Logic Unit.
* **Addressing:** Extended Addressing Module providing up to 256 MB of addressable memory.
* **Memory Architecture:** Independent 16-bit word-addressable program and data banks.
* **Return Address Buffer:** 256 slots for `CAL`/`RET` operations.
* **Instructions:** Variable-width (fixed 16-bit base + 0-2 immediate words).

---

## 🚀 Getting Started

### 🪟 Windows Setup

**Prerequisites:** Visual Studio 2022 (with C++ Desktop Development workload) **OR** MinGW (GCC).

#### Option A: Using Visual Studio (GUI)
1. Open `RR16X_EMULATOR.sln` in Visual Studio.
2. Set your build configuration to **Release** or **Debug** and build the solution (`Ctrl + Shift + B`) to generate `RR16X_EMULATOR.exe`.
3. Compile the assembler using the Developer Command Prompt:
   ```cmd
   cl hybrid_assembler.c
   ```

#### Option B: Using Command Line (MinGW/GCC)
```cmd
gcc hybrid_assembler.c -o hybrid_assembler.exe
g++ RR16X_EMULATOR/*.cpp -o RR16X_EMULATOR.exe
```

#### Running the Pipeline:
```cmd
hybrid_assembler.exe IntegrationTest.asm
RR16X_EMULATOR.exe
```

---

### 🐧 Linux / macOS Setup

**Prerequisites:** `gcc`, `g++`, and `make` (optional).

#### Compilation:
```bash
# Compile the assembler
gcc hybrid_assembler.c -o hybrid_assembler

# Compile the emulator
g++ RR16X_EMULATOR/*.cpp -o rr16x_emulator
```

#### Running the Pipeline:
```bash
./hybrid_assembler IntegrationTest.asm
./rr16x_emulator
```

---

## 📦 Repository Structure

* **`RR16X_EMULATOR/`** – Core C++ emulator runtime and extension peripherals (Timer, DMA, UART, etc.).
* **`RR16X_EMULATOR.sln`** – Visual Studio solution file for Windows developers.
* **`hybrid_assembler.c`** – Custom C compiler for source assembly.
* **`design.sv` & `testbench.sv`** – SystemVerilog hardware implementation.
* **`ABI.md`** – Application Binary Interface documentation.

---

## 📖 Documentation Links

* **Wiki:** [RR16X Wiki](https://github.com)
* **Sample Dump:** [Assembler Output Example](https://github.com/A-sample-dump-from-hybrid_assembler.c)
