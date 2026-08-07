; ============================================================
; EXTENSION INTEGRATION TEST ROM
;
; Interrupt vectors configured externally:
;
; 0x0100 -> timer_isr
; 0x0120 -> dma_isr
;
; Scratch RAM:
;
; 0x0200 timer_ticks
; 0x0201 dma_done
; 0x0202 test_value
;
; DMA source:
; 0x0300
; 0x0301
;
; DMA destination:
; 0x0400
; 0x0401
;
; ============================================================


start:

    ; clear variables

    ADD R0,0x0000,0x0000

    STM 0x0200,R0,R0
    STM 0x0201,R0,R0
    STM 0x0202,R0,R0


    ADD R0,0x0053,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000


; ============================================================
; MULTIPLIER TEST
;
; 123 * 456 = 0xDB18
; ============================================================


    ADD R0,0x007B,0x0000
    EAM.SET 0x07FF
    STM 0xFFFD,R0,R0
    EAM.SET 0x0000

    ADD R0,0x01C8,0x0000
    EAM.SET 0x07FF
    STM 0xFFFC,R0,R0
    EAM.SET 0x0000

    NIL

    EAM.SET 0x07FF
    LDM R1,0xFFFB,R0
    EAM.SET 0x0000

    ADD R2,0xDB18,0x0000


    STJ.C multiplier_fail
    JNE R1,R2


     ADD R0,0x004D,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000

; ============================================================
; INT32 TEST
;
; 100 + 200 = 300
; ============================================================


    ; A low

    ADD R0,0x0064,0x0000
    EAM.SET 0x07FF
    STM 0xFFED,R0,R0
    EAM.SET 0x0000

    ; A high

    ADD R0,0x0000,0x0000
    EAM.SET 0x07FF
    STM 0xFFEC,R0,R0
    EAM.SET 0x0000

    ; B low

    ADD R0,0x00C8,0x0000
    EAM.SET 0x07FF
    STM 0xFFEB,R0,R0
    EAM.SET 0x0000

    ; B high

    ADD R0,0x0000,0x0000
    EAM.SET 0x07FF
    STM 0xFFEA,R0,R0
    EAM.SET 0x0000

    ; command = ADD

    ADD R0,0x0000,0x0000
    EAM.SET 0x07FF
    STM 0xFFE9,R0,R0
    EAM.SET 0x0000

    NIL

    EAM.SET 0x07FF
    LDM R1,0xFFE8,R0
    EAM.SET 0x0000

    ADD R2,0x012C,0x0000


    STJ.C int32_fail
    JNE R1,R2


    ADD R0,0x0049,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000

; ============================================================
; FP32 TEST
;
; 1.0 + 2.0 = 3.0
;
; ============================================================


    ; A low

    ADD R0,0x0000,0x0000
    EAM.SET 0x07FF
    STM 0xFFD0,R0,R0
    EAM.SET 0x0000

    ; A high

    ADD R0,0x3F80,0x0000
    EAM.SET 0x07FF
    STM 0x07FFFFD1,R0,R0
    EAM.SET 0x0000

    ; B low

    ADD R0,0x0000,0x0000
    EAM.SET 0x07FF
    STM 0xFFD2,R0,R0
    EAM.SET 0x0000

    ; B high

    ADD R0,0x4000,0x0000
    EAM.SET 0x07FF
    STM 0xFFD3,R0,R0
    EAM.SET 0x0000

    ; command add

    ADD R0,0x0000,0x0000
    EAM.SET 0x07FF
    STM 0xFFD4,R0,R0
    EAM.SET 0x0000

    NIL

    EAM.SET 0x07FF
    LDM R1,0xFFD5,R0
    LDM R2,0xFFD6,R0
    EAM.SET 0x0000

    ADD R3,0x0000,0x0000
    ADD R4,0x4040,0x0000


    STJ.C fp32_fail
    JNE R1,R3


    STJ.C fp32_fail
    JNE R2,R4


     ADD R0,0x0046,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000


; ============================================================
; TIMER INTERRUPT TEST
; ============================================================


    ; enable timer only

    ADD R0,0x0001,0x0000
    EAM.SET 0x07FF
    STM 0xFFF5,R0,R0
    EAM.SET 0x0000

timer_wait:

    LDM R1,0x0200,R0


    ADD R2,0x0001,0x0000


    STJ.C timer_received
    JEQ R1,R2


    JMP


timer_received:

     ADD R0,0x0054,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000

; ============================================================
; DMA TEST
;
; Copy two words
; ============================================================


    ; source data

    ADD R0,0x1234,0x0000
    STM 0x0300,R0,R0


    ADD R0,0x5678,0x0000
    STM 0x0301,R0,R0


    ; enable DMA interrupt

    ADD R0,0x0004,0x0000
    EAM.SET 0x07FF
    STM 0xFFF5,R0,R0


    ; source

    ADD R0,0x0300,0x0000
    STM 0xFFF2,R0,R0


    ; destination

    ADD R0,0x0400,0x0000
    STM 0xFFF1,R0,R0


    ; count starts DMA

    ADD R0,0x0002,0x0000
    STM 0xFFF0,R0,R0
    EAM.SET 0x0000


dma_wait:

    LDM R1,0x0201,R0


    ADD R2,0x0001,0x0000


    STJ.C dma_received
    JEQ R1,R2


    JMP



dma_received:


    LDM R1,0x0400,R0
    ADD R2,0x1234,0x0000

    STJ.C dma_fail
    JNE R1,R2


    LDM R1,0x0401,R0
    ADD R2,0x5678,0x0000

    STJ.C dma_fail
    JNE R1,R2


     ADD R0,0x0044,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000

; ============================================================
; SUCCESS
; ============================================================


success:

     ADD R0,0x0050,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000
    HLT



; ============================================================
; FAILURES
; ============================================================


multiplier_fail:
    ADD R0,0x006D, 0x0000
    EAM.SET 0x07FF 
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000
    HLT
int32_fail:
      ADD R0,0x0069,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000
    HLT
fp32_fail:
     ADD R0,0x0066,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000
    HLT
timer_fail:
    ADD R0,0x0074,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000
    HLT
dma_fail:

    ADD R0,0x0064,0x0000
    EAM.SET 0x07FF
    STM 0xFFFF,R0,R0
    EAM.SET 0x0000
    HLT



; ============================================================
; INTERRUPT SERVICE ROUTINES
; ============================================================


timer_isr:

    ADD R0,0x0001,0x0000
    STM 0x0200,R0,R0

    RET



dma_isr:

    ADD R0,0x0001,0x0000
    STM 0x0201,R0,R0

    RET

