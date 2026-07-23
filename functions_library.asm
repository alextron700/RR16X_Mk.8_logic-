; libRR.asm — RR16X core runtime v0.1
; Minimal, assembler-ready, using your ABI + instruction set

; ------------------------------------------------------------
; Simple bump allocator state (in bank 0x0000)
; ------------------------------------------------------------

heap_ptr_low:
0000

heap_ptr_high:
0000

; ------------------------------------------------------------
; malloc(size)
; Arg0: size (words) at 0x07FF0000
; Ret0/Ret1: pointer (low/high) at 0x07FF4000 / 0x07FF4001
; ------------------------------------------------------------

malloc:
    ; load size from Arg0 (bank 0x07FF)
    EAM.SET 0x07FF
    LDM R0, 0x0000, R0      ; R0 = size

    ; load heap_ptr_low/high from bank 0x0000
    EAM.SET 0x0000
    LDM R4, heap_ptr_low,  R0
    LDM R5, heap_ptr_high, R0

    ; write return pointer to Ret0/Ret1 (bank 0x07FF)
    EAM.SET 0x07FF
    STM 0x4000, R4          ; Ret0 = low
    STM 0x4001, R5          ; Ret1 = high

    ; bump heap_ptr_low by size (no overflow handling yet)
    EAM.SET 0x0000
    ADD R4, R4, R0
    STM heap_ptr_low,  R4
    STM heap_ptr_high, R5

    RET

; ------------------------------------------------------------
; free(ptr) — no-op for bump allocator
; Arg0/Arg1: pointer (ignored)
; ------------------------------------------------------------

free:
    RET

; ------------------------------------------------------------
; strlen16(ptr_low, ptr_high)
; Arg0: low, Arg1: high (bank 0x07FF)
; Ret0: length (words) at 0x07FF4000
; ------------------------------------------------------------

strlen16:
    ; load pointer from Arg0/Arg1
    EAM.SET 0x07FF
    LDM R4, 0x0000, R0      ; R4 = ptr_low
    LDM R5, 0x0001, R0      ; R5 = ptr_high

    ; select data bank
    EAM.SET R5

    ; R6 = length = 0
    SUB R6, R6, R6

strlen_loop:
    ; load word at [ptr_low]
    LDM R7, R4, R0          ; R7 = *ptr

    ; if R7 == 0 → done
    JEQ strlen_done, R7, 0

    ; length++
    ADD R6, R6, 1

    ; ptr++
    ADD R4, R4, 1

    ; loop
    JNE strlen_loop, R7, 0  ; if R7 != 0, keep going

strlen_done:
    ; store length to Ret0
    EAM.SET 0x07FF
    STM 0x4000, R6

    RET

; ------------------------------------------------------------
; strcpy16(dst_low,dst_high,src_low,src_high)
; Arg0: dst_low, Arg1: dst_high
; Arg2: src_low, Arg3: src_high
; Copies including terminator
; ------------------------------------------------------------

strcpy16:
    ; load dst/src pointers
    EAM.SET 0x07FF
    LDM R4, 0x0000, R0      ; dst_low
    LDM R5, 0x0001, R0      ; dst_high
    LDM R6, 0x0002, R0      ; src_low
    LDM R7, 0x0003, R0      ; src_high

strcpy_loop:
    ; load from src (bank = src_high)
    EAM.SET R7
    LDM R0, R6, R0          ; R0 = *src

    ; store to dst (bank = dst_high)
    EAM.SET R5
    STM R4, R0              ; *dst = R0

    ; if zero → done
    JEQ strcpy_done, R0, 0

    ; advance src/dst
    ADD R6, R6, 1
    ADD R4, R4, 1

    ; loop
    JNE strcpy_loop, R0, 0

strcpy_done:
    RET
