; ==========================================
; CPU Validation Suite
; ==========================================

start:
    print 'S'
    call arithmetic
    call memory
    call branches
    call nested
    print 'P'
    print 'A'
    print 'S'
    print 'S'
    HLT

; ------------------------------------------
arithmetic:
    R0 = 10
    R1 = 20
    R2 = R0 + R1
    R3 = R2 - R0
    RET

; ------------------------------------------
memory:
    EAM.SET 0
    STM 0x0200, R2
    LDM R4, 0x0200
    RET

; ------------------------------------------
branches:
    STJ greater
    JGT R2, R3

    print 'F'
    HLT

greater:
    print 'G'
    RET

; ------------------------------------------
nested:
    print 'N'
    call nested2
    print 'X'
    RET

nested2:
    print '2'
    RET