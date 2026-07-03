; =========================================================================
; GATEWAY DRUG NATIVE ASSEMBLY HARDWARE TORTURE ROUTINE
; =========================================================================

main:
    ; 1. Fire up a signature validation character directly over Virtual UART
    print 'S'

    ; 2. Test 32-bit integer accelerator registers via native store commands
    ; Writing split values to 0x7FFFFEF (INT32_A_LO) and 0x7FFFFEE (INT32_A_HI)
    STM R0, 0x7FFFFEF, 0x5555
    STM R0, 0x7FFFFEE, 0xAAAA
    
    ; Writing split values to 0x7FFFFED (INT32_B_LO) and 0x7FFFFEC (INT32_B_HI)
    STM R0, 0x7FFFFED, 0x1111
    STM R0, 0x7FFFFEC, 0x2222

    ; Trigger 32-Bit ADD Command (CMD = 0)
    STM R0, 0x7FFFFEB, 0x0000

    ; 3. Test the brand-new FP32 FPU offset space
    ; Write 0x3F80 (IEEE-754 sign/exponent configuration for 1.0) into the FPU
    STM R0, 0x7FFFFF6, 0x3F80

    ; 4. Final output validation sequence over UART
    print 'O'
    print 'K'
    print '\n'

    ; 5. Halt execution cleanly
    HLT