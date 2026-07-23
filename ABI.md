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
