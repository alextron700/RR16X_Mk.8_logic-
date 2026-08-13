Welcome to the RR16X_Mk.8_logic- wiki!
# RR16X Application Binary Interface (ABI)

## Register set

- **General-purpose registers:** `R0`–`R7` (16-bit)
- **Data bank register:** set via `EAM.SET imm`
- **Jump register (JR):** target for `STJ`, used by `JMP` and conditional branches
-**USAGE EXAMPLE:***
```
 STJ target; Jump register now holds jump target
 JMP ; go there
 ```
## Instruction calling convention

- **Caller-saves:** All `R0`–`R7` are caller-saved.
- **No hardware stack:** Calls use `CAL`/`RET`; any stack discipline is purely software-defined.
- **Subroutine call:**
  - `call label` → assembler expands to `CAL imm16` (with bank handling if needed).
  - `RET` returns to caller.

## Argument and return passing

All arguments and return values are passed via a dedicated ABI bank:

- **ABI bank:** `0x07FF`

### Argument region

- **Address range:** `0x07FF'0000` → `0x07FF'3FFF`
- **Usage:**
  - `Arg0` at `0x07FF'0000`
  - `Arg1` at `0x07FF'0001`
  - `Arg2` at `0x07FF'0002`
  - `Arg3` at `0x07FF'0003`
  - `Arg4` at `0x07FF'0004`
  - and so on...
- **Access pattern:**
  - Before reading/writing arguments:
    - `EAM.SET 0x07FF`
  - Example:
    - `LDM R0, 0x0000, R0`  ; read Arg0
    - `STM 0x0001, R1`      ; write Arg1

### Return region

- **Address range:** `0x07FF'4000` → `0x07FF'7FFF`
- **Usage:**
  - `Ret0` at `0x07FF'4000`
  - `Ret1` at `0x07FF'4001`
  - and so on... 
- **Access pattern:**
  - Before reading/writing returns:
    - `EAM.SET 0x07FF`
  - Example:
    - `STM 0x4000, R4`      ; write Ret0
    - `STM 0x4001, R5`      ; write Ret1
## INTERRUPTS
- Interrupt acknowledgement and raise/clear is owned by interrupting device
- An interrupt is cleared with the InterruptEnhancer function clear_interrupt(), and raised with raise_interrupt()
- interrupts are **LEVEL TRIGGERED**
-On interrupt entry, the current PC and Program EAM are pushed onto the hardware call stack (Entry consists of ((ProgramEAM << 16) | PC) . Execution then transfers to the interrupt vector associated with that interrupt line.
N.B: IVR Effective address:
PC <- (IVR & 0xFFFF)
Program EAM <- (IVR >> 16) & 0xFFFF
- return address is saved to hidden on-board call stack, akin to a subroutine call. 
- It is possible to have multiple interrupts at once. Priority is determined by line number. Line 0 gets serviced first, line 1 goes second, and so on. Pending interrupts stay pending.  
- interrupts may not interrupt interrupts. 
- DATA EAM, the jump register, and R0 - R7 will be in whatever state they were in when the interrupt happened. 
- RET restores PC and program EAM 
- IVR IS BANKED 
- INSTRUCTION TO DISABLE INTERRUPTS: RET.C (opcode 0xE800, you should be in a subroutine to do that), INTERRUPT ENABLE: RET (opcode 0xE000), interrupt enable is stored as state 
- Interrupt entry costs a slot
- RET underflow wraps mod 256 
- interrupt handler must preserve R0-R7
- The InterruptEnhancer Mk.2 (InterruptEnhancer) provides 16 interrupt channels (0-15).
- Each interrupt channel maintains a pending state and an associated vector address.
- Interrupt vectors are supplied by the interrupting device when raising an interrupt.
- The InterruptEnhancer does not automatically acknowledge or clear interrupts.
- Mask register bits control whether channels participate in interrupt arbitration:
    - Bit = 1: interrupt channel enabled
    - Bit = 0: interrupt channel ignored
- The status register reflects pending interrupt state regardless of the mask register.
- If multiple enabled interrupts are pending, the lowest numbered channel is selected.
- Disabled interrupt channels remain pending and may be serviced after being enabled.
## General notes:
- NIL can technically consume immediates 
- Every instruction is fetched at ProgramEAM:PC 
- PC increments AFTER execution 
- Immediates use the same fetch hardware as instructions
- instructions may cross a bank boundary. 
- STJ only modifies the jump register. JMP uses JR. It does not consume JR. 
- JR is unchanged before and after a Jump, success or otherwise. 
- CPU and DMA cannot operate at the same time.
- WideIntCoprocessor is an ALU extension 
- FP32 is dependent on host single-precision floating point behaviour
- DMA stalls the CPU (No instruction execution at all) until completion (count != 0) 
- One instruction == One tick
- memory read is an execution operation
- DMA freezes execution on cycle after count != 0, DMA gets a tick independent of CPU, as part of APList Tick ( DMA transfer happens DURING APList Tick) 
    - Cycle N: CPU writes to count
    - Cycle N + 1: CPU Execution pauses
- Interrupts sampled before next CPU tick
- CPU OPERATION ORDER
    - (peripheral/s tick outside) 
    - (APList ticks) 
    - HANDLE INTERRUPTS <- COUNTS AS A TICK 
    - FETCH INSTR
    - DECODE
    - FETCH IMMEDIATE X (skipped if no X immediate)
    - FETCH IMMEDIATE Y (skipped if no Y immediate) 
    - EXECUTE
    - PC INCREMENT 
- EXTENSION DEVICES ARE MEMORY-MAPPED 
- CPU memory accesses and peripheral accesses are serialized through the bus.
- should an interrupt occur while DMA is active, it will have to wait until DMA is no longer active
- Emulator will raise an error if stack overflow. On hardware it just wraps mod 256. ( or whatever installed stack space there is, but it needs to be at least 256) 
- CAL/RET and interrupts share exactly the same hardware infrastructure. 
     -should an interrupt occur in a subroutine, interrupt will return to interrupted instruction
- **All conditional branches implicitly compare. There is no need for, nor does there exist on this hardware, an explicit CMP**
- Reads and Writes to Peripheral-mapped addresses may have device-defined side effects 
- assembler emits instructions as (INSTRUCTION CODE)(Optional immediate X)(Optional Immediate Y) in that exact order. 
- undefined opcodes are treated as NIL (effectively a NOP) 
- EAM immediate fetch happens BEFORE bank swap. 
- CAL pushes address of NEXT instruction. 
## RESET STATUS
PROGRAM EAM = 0x0000
PC = 0x0000
DATA EAM = 0x0000
JR = 0x0000:0000 NOTE: JR is 32-bit 
IVR = 0x0000:0000 (32 bits) 
REGISTERS = 0x0000
SP = 0x00
Stack is empty
Interrupts Enabled, No Interrupts active 
## IMPORTANT:
FP32Coprocessor implements IEEE-754 binary32 operations.
The emulator uses host float as an approximation.
Differences due to host rounding behavior are permitted.


## Emulator responsibilities

- On reset/boot, the emulator must:
  - Select ABI bank `0x07FF`.
  - Zero-initialize:
    - Argument region: `0x07FF'0000` → `0x07FF'3FFF`
    - Return region: `0x07FF'4000` → `0x07FF'7FFF`
- Program code loaded from the assembler must **not** overwrite the ABI bank; it lives in other banks (e.g., `0x0000`).

## libRR / C backend expectations

- Functions read arguments from the ABI argument region and write results to the ABI return region.
- The C backend:
  - Marshals function parameters into `Arg*`.
  - Reads results from `Ret*`.
  - Uses `call label` / `RET` for control flow.
- No hidden stack or register convention beyond what’s stated here; all additional calling discipline is defined by libRR and the backend.
