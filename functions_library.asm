; ============================================================
; libRR.asm — RR16X core runtime v0.1
;
; Reusable software routines for the RR16X.
;
; ABI:
;   Arg0 = 0x07FF:0000
;   Arg1 = 0x07FF:0001
;   Arg2 = 0x07FF:0002
;   Arg3 = 0x07FF:0003
;
;   Ret0 = 0x07FF:4000
;   Ret1 = 0x07FF:4001
;
; Notes:
;   - 16-bit registers
;   - 32-bit values are low:high
;   - ADD/SUB update carry latch
;   - ADD.C/SUB.C consume carry latch
;   - SHL/SHR update carry from the last bit shifted out
;   - NOT.C is two's-complement bitwise negate and does not
;     affect carry
;   - SHR/SHL can therefore be used to establish carry state
; ============================================================


; ============================================================
; BUMP ALLOCATOR
; ============================================================

heap_ptr_low:
0000

heap_ptr_high:
0000


; ------------------------------------------------------------
; malloc(size)
;
; Arg0 = size in words
; Ret0/Ret1 = pointer
;
; Simple bump allocator.
; No overflow handling.
; ------------------------------------------------------------

malloc:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0

    EAM.SET 0x0000

    LDM R4, heap_ptr_low, R0
    LDM R5, heap_ptr_high, R0

    EAM.SET 0x07FF

    STM 0x4000, R4
    STM 0x4001, R5

    EAM.SET 0x0000

    ADD R4, R4, R0
    STM heap_ptr_low, R4
    STM heap_ptr_high, R5

    RET


; ------------------------------------------------------------
; free(ptr)
;
; No-op for bump allocator.
; ------------------------------------------------------------

free:
    RET


; ============================================================
; STRING / MEMORY ROUTINES
; ============================================================


; ------------------------------------------------------------
; strlen16(ptr_low, ptr_high)
;
; Arg0 = pointer low
; Arg1 = pointer high
;
; Ret0 = length in 16-bit words
; ------------------------------------------------------------

strlen16:
    EAM.SET 0x07FF

    LDM R4, 0x0000, R0
    LDM R5, 0x0001, R0

    EAM.SET R5

    SUB R6, R6, R6

strlen_loop:

    LDM R7, R4, R0

    JEQ strlen_done, R7, 0x0000

    ADD R6, R6, 0x0001
    ADD R4, R4, 0x0001

    JNE strlen_loop, R7, 0x0000


strlen_done:

    EAM.SET 0x07FF
    STM 0x4000, R6

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; strcpy16(dst_low,dst_high,src_low,src_high)
;
; Copies zero-terminated 16-bit string including terminator.
; ------------------------------------------------------------

strcpy16:
    EAM.SET 0x07FF

    LDM R4, 0x0000, R0
    LDM R5, 0x0001, R0
    LDM R6, 0x0002, R0
    LDM R7, 0x0003, R0


strcpy_loop:

    EAM.SET R7
    LDM R0, R6, R0

    EAM.SET R5
    STM M$[R4], R0

    JEQ strcpy_done, R0, 0x0000

    ADD R6, R6, 0x0001
    ADD R4, R4, 0x0001

    JNE strcpy_loop, R0, 0x0000


strcpy_done:
    EAM.SET 0x0000
<<<<<<< Updated upstream
    RET


; ------------------------------------------------------------
; memset16(dst_low,dst_high,value,count)
;
; Fills count words with value.
; ------------------------------------------------------------

memset16:
    EAM.SET 0x07FF

    LDM R4, 0x0000, R0
    LDM R5, 0x0001, R0
    LDM R6, 0x0002, R0
    LDM R7, 0x0003, R0

    EAM.SET R5


memset_loop:

    JEQ memset_done, R7, 0x0000

    STM M$[R4], R6

    ADD R4, R4, 0x0001
    SUB R7, R7, 0x0001

    JMP memset_loop


memset_done:

    EAM.SET 0x0000
    RET


; ============================================================
; 32-BIT INTEGER ROUTINES
; ============================================================


; ------------------------------------------------------------
; AddI32(A,B)
;
; Arg0/Arg1 = A
; Arg2/Arg3 = B
;
; Ret0/Ret1 = A+B
; ------------------------------------------------------------

AddI32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    ADD R0, R0, R2
    ADD.C R1, R1, R3

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; SubI32(A,B)
;
; Ret = A-B
; ------------------------------------------------------------

SubI32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    SUB R0, R0, R2
    SUB.C R1, R1, R3

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; NegI32(A)
;
; Two's-complement negation.
; ------------------------------------------------------------

NegI32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    NOT.C R0
    NOT.C R1

    ADD R0, R0, 0x0001
    ADD.C R1, R1, 0x0000

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; AbsI32(A)
;
; Signed 32-bit absolute value.
;
; INT_MIN remains INT_MIN.
; ------------------------------------------------------------

AbsI32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    AND R2, R1, 0x8000

    JEQ AbsI32_Positive, R2, 0x0000

    NOT.C R0
    NOT.C R1

    ADD R0, R0, 0x0001
    ADD.C R1, R1, 0x0000


AbsI32_Positive:

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ============================================================
; 32-BIT SHIFT ROUTINES
; ============================================================


; ------------------------------------------------------------
; ShlI32_1
;
; 32-bit logical left shift by one.
; ------------------------------------------------------------

ShlI32_1:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    SHL R0, R0, 0x0001
    ADD.C R1, R1, R1

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; ShrI32_1
;
; 32-bit logical right shift by one.
; ------------------------------------------------------------

ShrI32_1:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    ; Carry = original bit 0 of high word.
    SHR R1, R1, 0x0001

    ; Save that carry as 0x8000.
    SUB R2, R2, R2
    ADD.C R2, R2, R2
    SHL R2, R2, 0x000F

    ; Low word shift.
    SHR R0, R0, 0x0001

    ; Bring original high bit 0 into low bit 15.
    OR R0, R0, R2

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET

; ------------------------------------------------------------
; CarryToBit15
;
; Converts carry latch into:
;
;   carry = 0 -> R2 = 0x0000
;   carry = 1 -> R2 = 0x8000
;
; Consumes the carry latch.
; ------------------------------------------------------------

CarryToBit15:

    SUB R2, R2, R2
    ADD.C R2, R2, R2
    SHL R2, R2, 0x000F

    RET


; ============================================================
; FP32 HARDWARE-BACKED ROUTINES
; ============================================================


; ------------------------------------------------------------
; AddF32
; ------------------------------------------------------------

AddF32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    STM 0x0000, R0
    STM 0x0001, R1
    STM 0x0002, R2
    STM 0x0003, R3

    STM 0x0004, 0x0004

    NIL

    LDM R0, 0x0005, R0
    LDM R1, 0x0006, R0

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; SubF32
; ------------------------------------------------------------

SubF32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    STM 0x0000, R0
    STM 0x0001, R1
    STM 0x0002, R2
    STM 0x0003, R3

    STM 0x0004, 0x0005

    NIL

    LDM R0, 0x0005, R0
    LDM R1, 0x0006, R0

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; MulF32
; ------------------------------------------------------------

MulF32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    STM 0x0000, R0
    STM 0x0001, R1
    STM 0x0002, R2
    STM 0x0003, R3

    STM 0x0004, 0x0006

    NIL

    LDM R0, 0x0005, R0
    LDM R1, 0x0006, R0

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; DivF32
; ------------------------------------------------------------

DivF32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    STM 0x0000, R0
    STM 0x0001, R1
    STM 0x0002, R2
    STM 0x0003, R3

    STM 0x0004, 0x0007

    NIL

    LDM R0, 0x0005, R0
    LDM R1, 0x0006, R0

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; absFP32
;
; Clears FP32 sign bit.
; ------------------------------------------------------------

absFP32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    AND R1, R1, 0x7FFF

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ============================================================
; INTEGER -> FP32
; ============================================================


; ------------------------------------------------------------
; CastI32F32
;
; Arg0/Arg1 = signed I32
; Ret0/Ret1 = FP32
;
; v0.1:
;   - zero
;   - normal finite integers
;   - signed values
;   - truncating mantissa
;   - no special IEEE handling
; ------------------------------------------------------------

CastI32F32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    ; Zero?

    OR R2, R0, R1
    STJ CastI32F32_Zero
    JEQ R2, 0x0000

    ; Save sign.

    AND R4, R1, 0x8000

    ; Convert to magnitude if negative.
    STJ CastI32F32_MagnitudeReady
    JEQ R4, 0x0000

    NOT.C R0
    NOT.C R1

    ADD R0, R0, 0x0001
    ADD.C R1, R1, 0x0000


CastI32F32_MagnitudeReady:

    ; --------------------------------------------------------
    ; R0:R1 = positive magnitude.
    ;
    ; Find highest set bit.
    ;
    ; R5 = bit position of highest set bit.
    ;
    ; High word occupies bits 31:16.
    ; Low word occupies bits 15:0.
    ; --------------------------------------------------------

    ; If high word is nonzero, search bits 31..16.
    STJ CastI32F32_HighSearch
    JNE R1, 0x0000

    ; Otherwise search bits 15..0.

    SUB R5, R5, R5
    ADD R5, R5, 0x000F


CastI32F32_LowSearch:

    AND R2, R0, 0x8000
    STJ CastI32F32_Found
    JNE R2, 0x0000

    SHL R0, R0, 0x0001
    SUB R5, R5, 0x0001
    STJ CastI32F32_LowSearch
    JMP


CastI32F32_HighSearch:

    ; Start at bit 31.

    SUB R5, R5, R5
    ADD R5, R5, 0x001F


CastI32F32_HighSearch_Loop:

    AND R2, R1, 0x8000
    STJ CastI32F32_Found
    JNE R2, 0x0000

    SHL R1, R1, 0x0001
    SHL.C R0, R0, 0x0001

    SUB R5, R5, 0x0001
    STJ CastI32F32_HighSearch_Loop
    JMP 


CastI32F32_Found:

    ; --------------------------------------------------------
    ; R5 = highest set bit position.
    ;
    ; FP32 exponent = highest_bit + 0x7F.
    ; --------------------------------------------------------

    ADD R5, R5, 0x007F

    ; --------------------------------------------------------
    ; Normalize so the leading 1 is bit 15 of R1.
    ; --------------------------------------------------------

CastI32F32_Normalize:

    AND R2, R1, 0x8000
    STJ CastI32F32_Normalized
    JNE R2, 0x0000

    SHL R0, R0, 0x0001
    SHL.C R1, R1, 0x0001
    STJ CastI32F32_Normalize
    JMP 


CastI32F32_Normalized:

    ; --------------------------------------------------------
    ; Remove implicit leading 1.
    ;
    ; The following 23 bits become the FP32 fraction.
    ; --------------------------------------------------------

    SHL R0, R0, 0x0001
    SHL.C R1, R1, 0x0001

    ; Pack exponent.

    SHL R5, R5, 0x0007

    OR R1, R1, R5

    ; Apply sign.

    OR R1, R1, R4

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET

; ============================================================
; FP32 -> INTEGER
; ============================================================


; ------------------------------------------------------------
; CastF32I32
;
; Arg0/Arg1 = FP32
; Ret0/Ret1 = signed I32
;
; Truncates toward zero.
;
; v0.1:
;   - zero
;   - normal finite values
;   - signed values
;   - no NaN/Inf handling
;   - overflow wraps according to the I32 representation
; ------------------------------------------------------------

CastF32I32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    ; --------------------------------------------------------
    ; Save sign.
    ; --------------------------------------------------------

    AND R4, R1, 0x8000

    ; --------------------------------------------------------
    ; Extract biased exponent.
    ; --------------------------------------------------------

    SHR R5, R1, 0x0007
    AND R5, R5, 0x00FF

    ; --------------------------------------------------------
    ; Extract fraction.
    ;
    ; R1 bits 6:0 = fraction high.
    ; Add implicit leading 1 at bit 7.
    ; --------------------------------------------------------

    AND R1, R1, 0x007F
    OR R1, R1, 0x0080

    ; --------------------------------------------------------
    ; E = exponent - 0x7F
    ; --------------------------------------------------------

    SUB R5, R5, 0x007F

    ; --------------------------------------------------------
    ; E < 0 => magnitude < 1.
    ;
    ; Detect negative signed exponent.
    ; --------------------------------------------------------

    AND R6, R5, 0x8000
    STJ CastF32I32_Zero
    JNE R6, 0x0000

    ; --------------------------------------------------------
    ; Desired shift:
    ;
    ;   E - 0x17
    ;
    ; because significand has 23 fractional bits.
    ; --------------------------------------------------------

    SUB R6, R5, 0x0017

    ; --------------------------------------------------------
    ; R6 < 0 => right shift.
    ; --------------------------------------------------------

    AND R7, R6, 0x8000
    STJ CastF32I32_RightShift
    JNE R7, 0x0000


    ; ========================================================
    ; LEFT SHIFT
    ; ========================================================

CastF32I32_LeftShift:
    STJ CastF32I32_ApplySign
    JEQ R6, 0x0000

    ; 32-bit << 1.

    SHL R0, R0, 0x0001
    ADD.C R1, R1, R1

    SUB R6, R6, 0x0001
    STJ CastF32I32_LeftShift
    JMP 


    ; ========================================================
    ; RIGHT SHIFT
    ; ========================================================

CastF32I32_RightShift:

    ; Convert negative shift count to positive.

    NOT.C R6
    ADD R6, R6, 0x0001


CastF32I32_RightShiftLoop:
    STJ CastF32I32_ApplySign
    JEQ R6, 0x0000

    ; High word first.
    ; Carry = old high bit 0.

    SHR R1, R1, 0x0001

    ; Materialize carry immediately.

    SUB R7, R7, R7
    ADD.C R7, R7, R7
    SHL R7, R7, 0x000F

    ; Shift low word.

    SHR R0, R0, 0x0001

    ; Insert old high bit 0.

    OR R0, R0, R7

    SUB R6, R6, 0x0001
    STJ CastF32I32_RightShiftLoop
    JMP 


    ; ========================================================
    ; APPLY SIGN
    ; ========================================================

CastF32I32_ApplySign:
    STJ CastF32I32_Return
    JEQ R4, 0x0000

    ; Negate magnitude.

    NOT.C R0
    NOT.C R1

    ADD R0, R0, 0x0001
    ADD.C R1, R1, 0x0000


CastF32I32_Return:

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; FP32 magnitude < 1
; ------------------------------------------------------------

CastF32I32_Zero:

    STM 0x4000, 0x0000
    STM 0x4001, 0x0000

    EAM.SET 0x0000
=======
>>>>>>> Stashed changes
    RET


; ------------------------------------------------------------
; memset16(dst_low,dst_high,value,count)
;
; Fills count words with value.
; ------------------------------------------------------------

memset16:
    EAM.SET 0x07FF

    LDM R4, 0x0000, R0
    LDM R5, 0x0001, R0
    LDM R6, 0x0002, R0
    LDM R7, 0x0003, R0

    EAM.SET R5


memset_loop:

    JEQ memset_done, R7, 0x0000

    STM M$[R4], R6

    ADD R4, R4, 0x0001
    SUB R7, R7, 0x0001

    JMP memset_loop


memset_done:

    EAM.SET 0x0000
    RET


; ============================================================
; 32-BIT INTEGER ROUTINES
; ============================================================


; ------------------------------------------------------------
; AddI32(A,B)
;
; Arg0/Arg1 = A
; Arg2/Arg3 = B
;
; Ret0/Ret1 = A+B
; ------------------------------------------------------------

AddI32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    ADD R0, R0, R2
    ADD.C R1, R1, R3

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; SubI32(A,B)
;
; Ret = A-B
; ------------------------------------------------------------

SubI32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    SUB R0, R0, R2
    SUB.C R1, R1, R3

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; NegI32(A)
;
; Two's-complement negation.
; ------------------------------------------------------------

NegI32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    NOT.C R0
    NOT.C R1

    ADD R0, R0, 0x0001
    ADD.C R1, R1, 0x0000

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; AbsI32(A)
;
; Signed 32-bit absolute value.
;
; INT_MIN remains INT_MIN.
; ------------------------------------------------------------

AbsI32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    AND R2, R1, 0x8000

    JEQ AbsI32_Positive, R2, 0x0000

    NOT.C R0
    NOT.C R1

    ADD R0, R0, 0x0001
    ADD.C R1, R1, 0x0000


AbsI32_Positive:

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ============================================================
; 32-BIT SHIFT ROUTINES
; ============================================================


; ------------------------------------------------------------
; ShlI32_1
;
; 32-bit logical left shift by one.
; ------------------------------------------------------------

ShlI32_1:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    SHL R0, R0, 0x0001
    ADD.C R1, R1, R1

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; ShrI32_1
;
; 32-bit logical right shift by one.
; ------------------------------------------------------------

ShrI32_1:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    ; Carry = original bit 0 of high word.
    SHR R1, R1, 0x0001

    ; Save that carry as 0x8000.
    SUB R2, R2, R2
    ADD.C R2, R2, R2
    SHL R2, R2, 0x000F

    ; Low word shift.
    SHR R0, R0, 0x0001

    ; Bring original high bit 0 into low bit 15.
    OR R0, R0, R2

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET

; ------------------------------------------------------------
; CarryToBit15
;
; Converts carry latch into:
;
;   carry = 0 -> R2 = 0x0000
;   carry = 1 -> R2 = 0x8000
;
; Consumes the carry latch.
; ------------------------------------------------------------

CarryToBit15:

    SUB R2, R2, R2
    ADD.C R2, R2, R2
    SHL R2, R2, 0x000F

    RET


; ============================================================
; FP32 HARDWARE-BACKED ROUTINES
; ============================================================


; ------------------------------------------------------------
; AddF32
; ------------------------------------------------------------

AddF32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    STM 0x0000, R0
    STM 0x0001, R1
    STM 0x0002, R2
    STM 0x0003, R3

    STM 0x0004, 0x0004

    NIL

    LDM R0, 0x0005, R0
    LDM R1, 0x0006, R0

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; SubF32
; ------------------------------------------------------------

SubF32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    STM 0x0000, R0
    STM 0x0001, R1
    STM 0x0002, R2
    STM 0x0003, R3

    STM 0x0004, 0x0005

    NIL

    LDM R0, 0x0005, R0
    LDM R1, 0x0006, R0

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; MulF32
; ------------------------------------------------------------

MulF32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    STM 0x0000, R0
    STM 0x0001, R1
    STM 0x0002, R2
    STM 0x0003, R3

    STM 0x0004, 0x0006

    NIL

    LDM R0, 0x0005, R0
    LDM R1, 0x0006, R0

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; DivF32
; ------------------------------------------------------------

DivF32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0
    LDM R2, 0x0002, R0
    LDM R3, 0x0003, R0

    STM 0x0000, R0
    STM 0x0001, R1
    STM 0x0002, R2
    STM 0x0003, R3

    STM 0x0004, 0x0007

    NIL

    LDM R0, 0x0005, R0
    LDM R1, 0x0006, R0

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; absFP32
;
; Clears FP32 sign bit.
; ------------------------------------------------------------

absFP32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    AND R1, R1, 0x7FFF

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ============================================================
; INTEGER -> FP32
; ============================================================


; ------------------------------------------------------------
; CastI32F32
;
; Arg0/Arg1 = signed I32
; Ret0/Ret1 = FP32
;
; v0.1:
;   - zero
;   - normal finite integers
;   - signed values
;   - truncating mantissa
;   - no special IEEE handling
; ------------------------------------------------------------

CastI32F32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    ; Zero?

    OR R2, R0, R1
    STJ CastI32F32_Zero
    JEQ R2, 0x0000

    ; Save sign.

    AND R4, R1, 0x8000

    ; Convert to magnitude if negative.
    STJ CastI32F32_MagnitudeReady
    JEQ R4, 0x0000

    NOT.C R0
    NOT.C R1

    ADD R0, R0, 0x0001
    ADD.C R1, R1, 0x0000


CastI32F32_MagnitudeReady:

    ; --------------------------------------------------------
    ; R0:R1 = positive magnitude.
    ;
    ; Find highest set bit.
    ;
    ; R5 = bit position of highest set bit.
    ;
    ; High word occupies bits 31:16.
    ; Low word occupies bits 15:0.
    ; --------------------------------------------------------

    ; If high word is nonzero, search bits 31..16.
    STJ CastI32F32_HighSearch
    JNE R1, 0x0000

    ; Otherwise search bits 15..0.

    SUB R5, R5, R5
    ADD R5, R5, 0x000F


CastI32F32_LowSearch:

    AND R2, R0, 0x8000
    STJ CastI32F32_Found
    JNE R2, 0x0000

    SHL R0, R0, 0x0001
    SUB R5, R5, 0x0001
    STJ CastI32F32_LowSearch
    JMP


CastI32F32_HighSearch:

    ; Start at bit 31.

    SUB R5, R5, R5
    ADD R5, R5, 0x001F


CastI32F32_HighSearch_Loop:

    AND R2, R1, 0x8000
    STJ CastI32F32_Found
    JNE R2, 0x0000

    SHL R1, R1, 0x0001
    SHL.C R0, R0, 0x0001

    SUB R5, R5, 0x0001
    STJ CastI32F32_HighSearch_Loop
    JMP 


CastI32F32_Found:

    ; --------------------------------------------------------
    ; R5 = highest set bit position.
    ;
    ; FP32 exponent = highest_bit + 0x7F.
    ; --------------------------------------------------------

    ADD R5, R5, 0x007F

    ; --------------------------------------------------------
    ; Normalize so the leading 1 is bit 15 of R1.
    ; --------------------------------------------------------

CastI32F32_Normalize:

    AND R2, R1, 0x8000
    STJ CastI32F32_Normalized
    JNE R2, 0x0000

    SHL R0, R0, 0x0001
    SHL.C R1, R1, 0x0001
    STJ CastI32F32_Normalize
    JMP 


CastI32F32_Normalized:

    ; --------------------------------------------------------
    ; Remove implicit leading 1.
    ;
    ; The following 23 bits become the FP32 fraction.
    ; --------------------------------------------------------

    SHL R0, R0, 0x0001
    SHL.C R1, R1, 0x0001

    ; Pack exponent.

    SHL R5, R5, 0x0007

    OR R1, R1, R5

    ; Apply sign.

    OR R1, R1, R4

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET

; ============================================================
; FP32 -> INTEGER
; ============================================================


; ------------------------------------------------------------
; CastF32I32
;
; Arg0/Arg1 = FP32
; Ret0/Ret1 = signed I32
;
; Truncates toward zero.
;
; v0.1:
;   - zero
;   - normal finite values
;   - signed values
;   - no NaN/Inf handling
;   - overflow wraps according to the I32 representation
; ------------------------------------------------------------

CastF32I32:
    EAM.SET 0x07FF

    LDM R0, 0x0000, R0
    LDM R1, 0x0001, R0

    ; --------------------------------------------------------
    ; Save sign.
    ; --------------------------------------------------------

    AND R4, R1, 0x8000

    ; --------------------------------------------------------
    ; Extract biased exponent.
    ; --------------------------------------------------------

    SHR R5, R1, 0x0007
    AND R5, R5, 0x00FF

    ; --------------------------------------------------------
    ; Extract fraction.
    ;
    ; R1 bits 6:0 = fraction high.
    ; Add implicit leading 1 at bit 7.
    ; --------------------------------------------------------

    AND R1, R1, 0x007F
    OR R1, R1, 0x0080

    ; --------------------------------------------------------
    ; E = exponent - 0x7F
    ; --------------------------------------------------------

    SUB R5, R5, 0x007F

    ; --------------------------------------------------------
    ; E < 0 => magnitude < 1.
    ;
    ; Detect negative signed exponent.
    ; --------------------------------------------------------

    AND R6, R5, 0x8000
    STJ CastF32I32_Zero
    JNE R6, 0x0000

    ; --------------------------------------------------------
    ; Desired shift:
    ;
    ;   E - 0x17
    ;
    ; because significand has 23 fractional bits.
    ; --------------------------------------------------------

    SUB R6, R5, 0x0017

    ; --------------------------------------------------------
    ; R6 < 0 => right shift.
    ; --------------------------------------------------------

    AND R7, R6, 0x8000
    STJ CastF32I32_RightShift
    JNE R7, 0x0000


    ; ========================================================
    ; LEFT SHIFT
    ; ========================================================

CastF32I32_LeftShift:
    STJ CastF32I32_ApplySign
    JEQ R6, 0x0000

    ; 32-bit << 1.

    SHL R0, R0, 0x0001
    ADD.C R1, R1, R1

    SUB R6, R6, 0x0001
    STJ CastF32I32_LeftShift
    JMP 


    ; ========================================================
    ; RIGHT SHIFT
    ; ========================================================

CastF32I32_RightShift:

    ; Convert negative shift count to positive.

    NOT.C R6
    ADD R6, R6, 0x0001


CastF32I32_RightShiftLoop:
    STJ CastF32I32_ApplySign
    JEQ R6, 0x0000

    ; High word first.
    ; Carry = old high bit 0.

    SHR R1, R1, 0x0001

    ; Materialize carry immediately.

    SUB R7, R7, R7
    ADD.C R7, R7, R7
    SHL R7, R7, 0x000F

    ; Shift low word.

    SHR R0, R0, 0x0001

    ; Insert old high bit 0.

    OR R0, R0, R7

    SUB R6, R6, 0x0001
    STJ CastF32I32_RightShiftLoop
    JMP 


    ; ========================================================
    ; APPLY SIGN
    ; ========================================================

CastF32I32_ApplySign:
    STJ CastF32I32_Return
    JEQ R4, 0x0000

    ; Negate magnitude.

    NOT.C R0
    NOT.C R1

    ADD R0, R0, 0x0001
    ADD.C R1, R1, 0x0000


CastF32I32_Return:

    STM 0x4000, R0
    STM 0x4001, R1

    EAM.SET 0x0000
    RET


; ------------------------------------------------------------
; FP32 magnitude < 1
; ------------------------------------------------------------

CastF32I32_Zero:

    STM 0x4000, 0x0000
    STM 0x4001, 0x0000

    EAM.SET 0x0000
    RET