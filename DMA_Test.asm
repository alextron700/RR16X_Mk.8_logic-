; =========================================================================
; GATEWAY 16-BIT FOUNDATION - DIRECT MEMORY ACCESS HARDWARE VERIFICATION
; =========================================================================

; Step 1: Set up the DMA Source RAM Address (0x0100)
R1 = 0x0100
STM R1, 0x7FFFFF2

; Step 2: Set up the DMA Destination RAM Address (0x0200)
R2 = 0x0200
STM R2, 0x7FFFFF1

; Step 3: Set up the Transfer Count to 5 Words.
; Writing to the Count register instantly triggers the hardware DMA burst!
R3 = 5
STM R3, 0x7FFFFF0

; Step 4: Stop the processor. 
; The DMA will freeze the CPU before it even fetches this HLT, 
; burst the data, and then hand control back to gracefully exit.
HLT