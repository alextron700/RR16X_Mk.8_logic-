; =====================================================================
; RR16X SYSTEM-ON-CHIP MASTER MEMORY MAP DEFINE CONTEXT
; =====================================================================
;define SOURCE_CODE_BASE 0x00010000 ; Raw high-level source text block pointer
;define TOKEN_ARRAY_START 0x00100000 ; Target destination where lexer stacks tokens

; Lexer Scratch Buffers
define LEX_ID_PTR 0x00200000 ; LEX_ID_PTR location
define LEX_NUM_PTR 0x00201000 ; LEX_NUM_PTR location
define LEX_SYM_PTR 0x00202000 ; LEX_SYM_PTR location
define LEX_STR_PTR 0x00203000 ;

; Database Storage Matrices
define SYMBOL_TABLE_BASE 0x00300000 ; Variable Symbol Table base address
define FUNCTION_TABLE_BASE 0x00400000 ; Function Directory Table base address
define COMPILED_BINARY_BASE 0x00500000 ; Code generation target destination

; Hardware Peripheral Mapping Offsets
define MULT_REG_A 0xFFFD ; Multiplier Input A (EAM Page 0x07FF)
define MULT_REG_B 0xFFFC ; Multiplier Input B (EAM Page 0x07FF)
define MULT_REG_OUT 0xFFFB ; Multiplier Product Result (EAM Page 0x07FF)

; Pre-calculated 32-Bit DJB2 Keyword Hashes
; Recomputed and verified against the actual runtime hash loop below -
; the previous values here did not match what hash_32bit_loop actually
; produces for these keywords (checked by hand and cross-checked in
; Python), so "if"/"while"/"func"/"for" recognition was silently dead
; code. HASH_PRINT_HIGH/LOW was referenced by parser_statement_dispatcher
; but was never defined at all - added below.
define HASH_IF_HIGH 0x0059 ; "if" High Word Hash
define HASH_IF_LOW 0x7834 ; "if" Low Word Hash
define HASH_WHILE_HIGH 0x10A3 ; "while" High Word Hash
define HASH_WHILE_LOW 0x387E ; "while" Low Word Hash
define HASH_FUNC_HIGH 0x7C96 ; "func" High Word Hash
define HASH_FUNC_LOW 0xFE71 ; "func" Low Word Hash
define HASH_FOR_HIGH 0x0B88 ; "for" High Word Hash
define HASH_FOR_LOW 0x738C ; "for" Low Word Hash
define HASH_PRINT_HIGH 0x102A ; "print" High Word Hash
define HASH_PRINT_LOW 0x0912 ; "print" Low Word Hash
define free_register_mask 0x0000FFFF
define Print_Target_Addr 0x00010000
define If_Placeholder_Address 0x000100FF
define Loop_Start_Anchor 0x000101FF
define Loop_Exit_Placeholder 0x000101FE
define Target_Var_Address 0x000102FF
define For_Var_Backup 0x000103FF
define For_Condition_Anchor 0x000104FF
define For_Exit_Placeholder 0x000105FF 
define Target_Func_Anchor_Address 0x000106FF
define Rel_Placeholder_Address 0x000107FF
define Rel_Skip_Placeholder 0x000108FF
define Scratch0 0x000109F0
define Scratch1 0x000109F1
define Scratch2 0x000109F2
define Scratch3 0x000109F3
define Scratch4 0x000109F4
define Scratch5 0x000109F5
define Scratch6 0x000109F6
define Scratch7 0x000109F7
define token_stream_ptr 0x000109F8

; =====================================================================
; RR16X SYSTEM CONFIGURATION WELCOME PROMPT SIGNATURES
; =====================================================================
prompt_text:
HEX 0052, 0052, 0031, 0036, 0058, 0020 ; "RR16X "
HEX 004D, 006B, 0020, 0038, 002E, 0031 ; "Mk 8.1"
HEX 0020, 0042, 0041, 0053, 0049, 0043 ; " BASIC"
HEX 000D, 000A ; " r n"
HEX 0061, 006C, 006C, 0020, 0073, 0079 ; "all sy"
HEX 0073, 0074, 0065, 006D, 0073, 0020 ; "stems "
HEX 006F, 006E, 006C, 0069, 006E, 0065 ; "online"
HEX 000D, 000A ; " r n"
HEX 0052, 0045, 0041, 0044, 0059, 002E ; "READY."
HEX 0000 ; Null Terminator sentinel

; =====================================================================
; RR16X SYSTEM-ON-CHIP MASTER OPERATING SHELL
; =====================================================================
BASIC_MACHINE_SHELL_START:
; Initialize Compiler Dynamic Memory Pool Counters at System Boot
ADD R0 0x0000 0x0060
STM M$[COMPILED_BINARY_BASE] R0 ; Set runtime compiled data pool pointer
ADD R0 0x0000 0x0081
STM M$[free_register_mask] R0 ; Lock registers R0 and R7 from allocator mapping

; 1. Transmit the iconic startup prompt out over your UART Tx port
CAL transmit_ready_prompt

; 2. Initialize our line input character index counter
XOR R6 R6 R6 ; R6 = Character index counter (= 0)

.poll_keyboard_loop:
EAM.SET 0x07FF ; Bank up to your high peripheral matrix
LDM R1 M$[0xFFE5] ; Poll your UART Rx Status Register

LDM R0 M$[0xFFE6] ; Read the incoming ASCII keyboard character byte
EAM.SET 0x0000 ; Return to standard memory bank

STJ .poll_keyboard_loop
JEQ R1 0x0000 ; If no new character arrived, spin and wait

; Check if the user pressed the Enter key (Carriage Return -> 0x000D)
STJ .execute_entered_line
JEQ R0 0x000D

; Otherwise, save the typed character directly into your high-level source string buffer!
EAM.SET 0x0001 ; Bank up to Page 1 address boundary space
STM M$[R6] R0 ; Save character byte using offset tracker R6
EAM.SET 0x0000 ; Cleanly restore base memory bank instantly!
ADD R6 R6 0x0001 ; Advance character index

; Echo the typed character back to the user's terminal live!
EAM.SET 0x07FF
STM M$[0xFFFF] R0 ; Stream character from R0 to exact hardware port 0xFFFF
EAM.SET 0x0000

STJ .poll_keyboard_loop
JMP ; Loop back to wait for the next character

.execute_entered_line:
; User hit Enter! Append a 0x0000 null terminator to complete the source string
XOR R0 R0 R0
EAM.SET 0x0001
STM M$[R6] R0 ; Cap the line buffer with a terminating null
EAM.SET 0x0000 ; Restore base memory bank instantly!

; Print a newline back to their terminal screen
EAM.SET 0x07FF
STM M$[0xFFFF] 0x000D ; Output Carriage Return
STM M$[0xFFFF] 0x000A ; Output Line Feed
EAM.SET 0x0000

; --- TRIGGER THE COMPLETE REPL ENGINE PIPELINE ---
; Reset the code generation output pointer to the start of the execution region
ADD R0 0x0000 0x0050 ; COMPILED_BINARY_BASE target pointer address
STM M$[COMPILED_BINARY_BASE] R0

CAL parse_line ; Stage 1: Lexer turns raw input chars into 32-bit tokens
CAL parse_program ; Stage 2: Parser and Allocator emit runnable binary opcodes

; Stage 3: NATIVE EXECUTION!
; Perform an absolute context switch by jumping your CPU's PC directly to your compiled buffer!
EAM.SET 0x0050 ; Bank execution pointer up to Page 0x0050 space boundary
STJ 0x0000 ; Clear jump target to point right to offset 0x0000 inside the bank
JMP ; Run the user's compiled command natively at full clock speed!

; Once the compiled user program finishes executing, its trailing 'RET' statement
; pops the context back up, and we bounce right back to the start to type the next line!
STJ BASIC_MACHINE_SHELL_START
JMP

; =====================================================================
; STAGE 1: LEXICAL ANALYSER / TOKENISER
; =====================================================================
parse_line:
ADD R0 0x0000 SYMBOL_TABLE_BASE
STM M$[SYMBOL_TABLE_BASE] R0
STM M$[Scratch0] R0
STM M$[Scratch1] R1
STM M$[Scratch2] R2
STM M$[Scratch3] R3
STM M$[Scratch4] R4

ADD R0 0xFFFF 0x0000 ; Initialize tracking offset index at -1
ADD R1 LEX_ID_PTR 0x0000 ; Buffer destination tracking for text symbols
ADD R2 LEX_NUM_PTR 0x0000 ; Buffer destination tracking for integers
ADD R3 LEX_SYM_PTR 0x0000 ; Buffer destination tracking for symbols
ADD R4 0x0000 0x0000 ; State machine engine register tracking

loop:
ADD R0 R0 0x0001 ; Advance current character tracking position
LDM R0 M$[*line] ; Read the character value from the raw line buffer

STJ exit
JEQ R0 0x0000 ; If end of string (0x0000), drop out safely

STJ StringMode
JEQ R4 0x0004

STJ handleWhitespace
JLE R0 0x0020 ; Space, Tab, or Line Feed implies a token boundary flush step


STJ stringEntry
JEQ R0 0x0022

STJ pickMode
JNE R4 0x0000 ; If locked inside an active state mode, bypass sorting

; Initial entry point mode selection logic block
STJ letterMode
JGE R0 0x0041 ; Over 0x0041 ('A')

STJ numberMode
JGE R0 0x0030 ; Over 0x0030 ('0') -> potential digit token

STJ SymMode
JMP ; Drop straight into punctuation mapping

; --- Boundary Whitespace Handler ---
handleWhitespace:
STJ flushID
JEQ R4 0x0001 ; If state was text loop tracking, trigger conversion sweep
STJ flushNum
JEQ R4 0x0002 ; If state was integer loop tracking, trigger parsing conversion
STJ flushSym
JEQ R4 0x0003 ; If state was symbol loop tracking, trigger packing conversion
STJ loop
JMP ; Safe fall-through for sequential whitespace elements

flushID:
CAL dealWithID
XOR R1 R1 R1
XOR R4 R4 R4
STJ loop
JMP

flushNum:
CAL dealWithNum
XOR R2 R2 R2
XOR R4 R4 R4
STJ loop
JMP

flushSym:
CAL handleSym
XOR R3 R3 R3
XOR R4 R4 R4
STJ loop
JMP

; --- Individual Categorisation States ---
letterMode:
STJ testLower
JLT R0 0x0041
JGT R0 0x005A
STJ UpperLetter
JMP

testLower:
STJ notLetter
JLT R0 0x0061
JGT R0 0x007A
STJ LowerLetter
JMP

STJ notLetter
JMP

UpperLetter:
LowerLetter:
STM M$[R1] R0 ; Dynamic array storage write pass
ADD R1 R1 0x0001
ADD R4 0x0001 0x0000 ; Establish state lock mode code 1
STJ loop
JMP

notLetter:
CAL dealWithID
XOR R1 R1 R1
XOR R4 R4 R4
STJ loop
JMP
stringEntry:
STJ .string_from_id
JEQ R4 0x0001

STJ .string_from_num
JEQ R4 0x0002

STJ .string_from_sym
JEQ R4 0x0003

; R4 == 0, so begin string immediately
STJ .begin_string
JMP

.string_from_id:
CAL dealWithID
XOR R1 R1 R1
XOR R4 R4 R4
STJ .begin_string
JMP

.string_from_num:
CAL dealWithNum
XOR R2 R2 R2
XOR R4 R4 R4
STJ .begin_string
JMP

.string_from_sym:
CAL handleSym
XOR R3 R3 R3
XOR R4 R4 R4

.begin_string:
; ------------------------------------------------------------
; Enter string mode.
; The opening quote itself is NOT stored.
; ------------------------------------------------------------
ADD R4 0x0004 0x0000
ADD R1 0x0000 LEX_STR_PTR

STJ loop
JMP
numberMode:
STJ NotNum
JLT R0 0x0030
JGT R0 0x0039
ADD R4 0x0002 0x0000 ; Establish state lock mode code 2
STM M$[R2] R0
ADD R2 R2 0x0001
STJ loop
JMP

NotNum:
CAL dealWithNum
XOR R2 R2 R2
XOR R4 R4 R4
STJ loop
JMP

SymMode:
ADD R4 0x0003 0x0000 ; Establish state lock mode code 3
STM M$[R3] R0
ADD R3 R3 0x0001
ADD R5 LEX_SYM_PTR 0x0000
SUB R5 R5 R3
STJ dontReset
JLT R5 0x0002
CAL handleSym
XOR R3 R3 R3
XOR R4 R4 R4
dontReset:
STJ loop ; Explicit return jump added to prevent dispatcher lockup
JMP

StringMode:
    STJ StringEnd
    JEQ R0 0x0022          ; closing quote?

    STM M$[R1] R0          ; store character
    ADD R1 R1 0x0001

    STJ loop
    JMP

StringEnd:
    CAL dealWithString

    XOR R1 R1 R1
    XOR R4 R4 R4

    STJ loop
    JMP

pickMode:
STJ letterMode
JEQ R4 0x0001
STJ numberMode
JEQ R4 0x0002
STJ SymMode
JEQ R4 0x0003
STJ StringMode
JEQ R4 0x0004
STJ loop
JMP

exit:
STJ .exit_flush_id
JEQ R4 0x0001
STJ .exit_flush_num
JEQ R4 0x0002
STJ .exit_flush_sym
JEQ R4 0x0003
STJ .exit_flush_string
JEQ R4 0x0004
STJ .exit_restore
JMP

.exit_flush_id:
CAL dealWithID
STJ .exit_restore
JMP

.exit_flush_num:
CAL dealWithNum
STJ .exit_restore
JMP

.exit_flush_sym:
CAL handleSym
STJ .exit_restore
JMP
.exit_flush_string:
    CAL trigger_syntax_error
    STJ .exit_restore
    JMP
.exit_restore:
LDM R0 M$[Scratch0]
LDM R1 M$[Scratch1]
LDM R2 M$[Scratch2]
LDM R3 M$[Scratch3]
LDM R4 M$[Scratch4]
RET
; =====================================================================
; VARIABLE-WIDTH LEXER SUBROUTINES (32-BIT COPROCESSOR HASHING)
; =====================================================================
dealWithID:
STM M$[Scratch5] R5
STM M$[Scratch6] R6
STM M$[Scratch7] R7
STM M$[Scratch3] R3
STM M$[Scratch2] R2
STM M$[Scratch4] R4
STM M$[Scratch1] R1
STM M$[Scratch0] R0
STJ .empty_id
JEQ R1 0x0000 ; If buffer length is 0, exit;
; Initialize 32-bit DJB2 Hash constant (5381 = 0x00001505)
XOR R6 R6 R6 ; Hash High Word = 0x0000
ADD R5 0x0000 0x1505 ; Hash Low Word = 0x1505
XOR R3 R3 R3 ; Loop Index Counter (R3 = 0)
.hash_32bit_loop:
ADD R7 0x0000 LEX_ID_PTR ; Load scratch buffer base address
ADD R7 R7 R3 ; Add index offset counter
LDM R7 M$[R7] ; Pull character byte from calculated address

; --- Case-fold to lowercase before hashing, so keyword matching (and
; user identifiers) are case-insensitive, matching classic BASIC. ---
STJ .not_upper
JLT R7 0x0041 ; below 'A'
JGT R7 0x005A ; above 'Z'
ADD R7 R7 0x0020 ; fold to lowercase
.not_upper:

; --- INT32 Coprocessor Interaction (Hash * 33) ---
EAM.SET 0x07FF ; Bank address line up to peripheral matrix
STM M$[0xFFFD] R5 ; LHS Low Word
STM M$[0xFFFC] 0x0021 ; RHS Low Word (Constant scalar 33)
LDM R5 M$[0xFFFA]
LDM R4 M$[0xFFFB] ; Load result from multiplication staging
STM M$[0xFFEC] R5 ; Place in active int32 coprocessor computing execution lanes
STM M$[0xFFED] R4
STM M$[0xFFFD] R6 ; LHS High Word
STM M$[0xFFFC] 0x0000 ; RHS High Word
LDM R6 M$[0xFFFB]
LDM R0 M$[0xFFFA]
STM M$[0xFFEA] R0
STM M$[0xFFEB] R6
STM M$[0xFFE9] 0x0000 ; Trigger multiply
LDM R5 M$[0xFFE8] ; Pull Result Low Word
LDM R6 M$[0xFFE7] ; Pull Result High Word
EAM.SET 0x0000 ; Restore standard address mapping bank

; Add character byte to running low word
ADD R5 R5 R7
STJ .no_hash_carry
JGE R5 R7 ; If Low Word overflowed, carry the 1 up
ADD R6 R6 0x0001 ; Increment High Word

.no_hash_carry:
ADD R3 R3 0x0001 ; Advance loop index pointer
STJ .hash_32bit_loop
JNE R3 R1 ; Repeat until all string characters are processed

; --- Stream Out 3-Word Token Package to Memory Matrix ---
LDM R7 M$[token_stream_ptr]
ADD R4 0x1000 R1 ; Word 0: Header (0x1000 Type Flag + String Length in R1)
STM M$[R7] R4
ADD R7 R7 0x0001
STM M$[R7] R6 ; Word 1: 32-Bit Hash High Word
ADD R7 R7 0x0001
STM M$[R7] R5 ; Word 2: 32-Bit Hash Low Word
ADD R7 R7 0x0001
STM M$[token_stream_ptr] R7 ; Update global streaming pointer position

.empty_id:
LDM R0 M$[Scratch0]
LDM R1 M$[Scratch1]
LDM R2 M$[Scratch2]
LDM R3 M$[Scratch3]
LDM R4 M$[Scratch4]
LDM R5 M$[Scratch5]
LDM R6 M$[Scratch6]
LDM R7 M$[Scratch7]
RET

dealWithNum:
STM M$[Scratch5] R5
STM M$[Scratch6] R6
STM M$[Scratch7] R7
STM M$[Scratch3] R3
STM M$[Scratch2] R2
STM M$[Scratch4] R4

STJ .empty_num
JEQ R2 0x0000 ; If number buffer length is 0, exit

XOR R5 R5 R5 ; Running Total Low Word (R5 = 0)
XOR R6 R6 R6 ; Running Total High Word (R6 = 0)
XOR R3 R3 R3 ; Loop Index Counter (R3 = 0)

.convert_32bit_loop:
ADD R7 0x0000 LEX_NUM_PTR
ADD R7 R7 R3
LDM R7 M$[R7] ; Read raw ASCII byte safely
SUB R7 R7 0x0030 ; Strip ASCII bias ('5' -> 5)

; --- INT32 Coprocessor Interaction (Total * 10) ---
EAM.SET 0x07FF
STM M$[0xFFFD] R5 ; LHS Low Word
STM M$[0xFFFC] 0x000A ; RHS Low Word (Multiply by 10)
LDM R5 M$[0xFFFA]
LDM R4 M$[0xFFFB]
STM M$[0xFFEC] R5
STM M$[0xFFED] R4

STM M$[0xFFFD] R6 ; LHS High Word
STM M$[0xFFFC] 0x0000 ; RHS High Word
LDM R6 M$[0xFFFB]
LDM R0 M$[0xFFFA]
STM M$[0xFFEA] R0
STM M$[0xFFEB] R6

STM M$[0xFFE9] 0x0000 ; Trigger multiply
LDM R5 M$[0xFFE8] ; Pull Result Low Word
LDM R6 M$[0xFFE7] ; Pull Result High Word
EAM.SET 0x0000

ADD R5 R5 R7 ; Add digit value to running total
STJ .no_carry
JGE R5 R7
ADD R6 R6 0x0001 ; Carry bit to high word container

.no_carry:
ADD R3 R3 0x0001 ; Advance loop index pointer
STJ .convert_32bit_loop
JNE R3 R2 ; Repeat until every digit character is parsed

; Stream Out 3-Word Packet
LDM R7 M$[token_stream_ptr]
ADD R4 0x2000 R2 ; Header (0x2000 Type Flag + Digit Count in R2)
CAL EmitWordR4
CAL EmitWordR6 ; Word 1: Converted Integer High 16-bits
CAL EmitWordR5 ; Word 2: Converted Integer Low 16-bits

.empty_num:
LDM R2 M$[Scratch2]
LDM R3 M$[Scratch3]
LDM R4 M$[Scratch4]
LDM R5 M$[Scratch5]
LDM R6 M$[Scratch6]
LDM R7 M$[Scratch7]
RET

handleSym:
STM M$[Scratch5] R5
STM M$[Scratch6] R6
STM M$[Scratch7] R7
STM M$[Scratch3] R3
STM M$[Scratch2] R2
STM M$[Scratch4] R4

STJ .empty_sym
JEQ R3 0x0000 ; If symbol buffer length is 0, exit

LDM R5 M$[LEX_SYM_PTR] ; Grab the symbol character
ADD R6 0x3000 R5 ; Combine Type Flag (0x3000)
CAL EmitWordR6

.empty_sym:
LDM R2 M$[Scratch2]
LDM R3 M$[Scratch3]
LDM R4 M$[Scratch4]
LDM R5 M$[Scratch5]
LDM R6 M$[Scratch6]
LDM R7 M$[Scratch7]
RET
dealWithString:
    STM M$[Scratch0] R0
    STM M$[Scratch1] R1
    STM M$[Scratch2] R2
    STM M$[Scratch3] R3
    STM M$[Scratch4] R4
    STM M$[Scratch5] R5
    STM M$[Scratch6] R6
    STM M$[Scratch7] R7

    ; R1 = end of string buffer
    ; R2 = string length
    ADD R2 0x0000 LEX_STR_PTR
    SUB R2 R1 R2

    ; Empty string is still a valid string.
    ; Emit 0x4000 + length.
    ADD R4 0x4000 R2
    CAL EmitWordR4

    ; R3 = string-buffer read pointer
    ADD R3 0x0000 LEX_STR_PTR

.string_emit_loop:
    STJ .string_emit_done
    JGE R3 R1

    LDM R0 M$[R3]
    CAL EmitWordR0

    ADD R3 R3 0x0001

    STJ .string_emit_loop
    JMP

.string_emit_done:

    LDM R0 M$[Scratch0]
    LDM R1 M$[Scratch1]
    LDM R2 M$[Scratch2]
    LDM R3 M$[Scratch3]
    LDM R4 M$[Scratch4]
    LDM R5 M$[Scratch5]
    LDM R6 M$[Scratch6]
    LDM R7 M$[Scratch7]

    RET
    EmitWordR0:
    STM M$[scratch7] R7
    STM M$[scratch0] R0

    LDM R7 M$[token_stream_ptr]
    STM M$[R7] R0

    ADD R7 R7 0x0001
    STM M$[token_stream_ptr] R7

    LDM R7 M$[scratch7]
    LDM R0 M$[scratch0]

    RET
; --- Modular Token Emitter Utilities ---
EmitWordR6:
STM M$[scratch7] R7
STM M$[scratch6] R6
LDM R7 M$[token_stream_ptr]
STM M$[R7] R6
ADD R7 R7 0x0001
STM M$[token_stream_ptr] R7
LDM R7 M$[scratch7]
LDM R6 M$[scratch6]
RET

EmitWordR5:
STM M$[scratch7] R7
STM M$[scratch5] R5
LDM R7 M$[token_stream_ptr]
STM M$[R7] R5
ADD R7 R7 0x0001
STM M$[token_stream_ptr] R7
LDM R7 M$[scratch7]
LDM R5 M$[scratch5]
RET

EmitWordR4:
STM M$[scratch7] R7
STM M$[scratch4] R4
LDM R7 M$[token_stream_ptr]
STM M$[R7] R4
ADD R7 R7 0x0001
STM M$[token_stream_ptr] R7
LDM R7 M$[scratch7]
LDM R4 M$[scratch4]
RET

; =====================================================================
; STAGE 2: THE RECURSIVE DESCENT PARSER FRONT-END DISPATCHER
; =====================================================================
advanceToken:
LDM R5 M$[R6] ; Load Word 0 (The Header Word)
STJ .end_of_stream
JEQ R5 0x0000 ; Out of tokens -> EOF

AND R5 R5 0xF000 ; Isolate upper nibble token type

STJ .parse_symbol
JEQ R5 0x3000
STJ .parse_identifier
JEQ R5 0x1000
STJ .parse_number
JEQ R5 0x2000
STJ .parse_string
JEQ R5 0x4000
RET

.parse_symbol:
LDM R4 M$[R6]
AND R4 R4 0x0FFF ; Get raw ASCII operator char
ADD R6 R6 0x0001
RET

.parse_identifier:
ADD R6 R6 0x0001
LDM R2 M$[R6] ; R2 = 32-bit Hash High Word
ADD R6 R6 0x0001
LDM R4 M$[R6] ; R4 = 32-bit Hash Low Word
ADD R6 R6 0x0001
RET
.parse_string:
    ADD R6 R6 0x0001
    LDM R4 M$[R6]          ; R4 = length

    ADD R6 R6 0x0001
    ADD R7 R6 0x0000       ; R7 = string data pointer

    ; Advance R6 beyond the string payload.
    ADD R6 R6 R4

    RET
.parse_number:
ADD R6 R6 0x0001
LDM R4 M$[R6] ; R4 = High 16-bits payload
ADD R6 R6 0x0001
LDM R3 M$[R6] ; R3 = Low 16-bits payload
ADD R6 R6 0x0001
RET

.end_of_stream:
XOR R5 R5 R5
XOR R4 R4 R4
RET

parse_program:
ADD R6 0x0000 TOKEN_ARRAY_START
CAL advanceToken

parser_main_loop:
STJ parser_success
JEQ R5 0x0000 ; Reached EOF cleanly

CAL parser_statement_dispatcher
STJ parser_main_loop
JMP

parser_statement_dispatcher:
STJ .match_id
JEQ R5 0x1000
STJ .match_sym
JEQ R5 0x3000
CAL trigger_syntax_error
STJ parser_fail
JMP

.match_id:
 STJ .not_if
    JNE R2 HASH_IF_HIGH

    STJ .not_if
    JNE R4 HASH_IF_LOW

    CAL compile_if_statement
    RET
    .not_if:
 STJ .not_while
    JNE R2 HASH_WHILE_HIGH

    STJ .not_while
    JNE R4 HASH_WHILE_LOW

    CAL compile_while_loop
    RET


.not_while:
 STJ .not_for_loop
    JNE R2 HASH_FOR_HIGH

    STJ .not_for_loop
    JNE R4 HASH_FOR_LOW

    CAL compile_for_loop
    RET
.not_for_loop:

STJ .not_func_declaration
    JNE R2 HASH_FUNC_HIGH

    STJ .not_func_declaration
    JNE R4 HASH_FUNC_LOW

    CAL parse_function_declaration
    RET


.not_func_declaration:

    ; ============================================================
    ; FUNCTION CALL
    ;
    ; R2 = hash high
    ; R4 = hash low
    ; check_if_function_exists returns result in R3
    ; ============================================================

    ADD R1 R2 0x0000
    ADD R0 R4 0x0000

    CAL check_if_function_exists

    STJ .not_a_function_call
    JEQ R3 0x0000

    CAL compile_function_call
    RET


.not_a_function_call:

    ; ============================================================
    ; PRINT
    ; ============================================================

    STJ .not_print
    JNE R2 HASH_PRINT_HIGH

    STJ .not_print
    JNE R4 HASH_PRINT_LOW

    CAL compile_print_statement
    RET


.not_print:

    ; ============================================================
    ; Otherwise it is treated as an assignment
    ; ============================================================

    CAL compile_assignment
    RET


.match_sym:

    CAL trigger_syntax_error
    STJ parser_fail
    JMP
parser_success:
ADD R0 0x0055 0x0000
RET




; =====================================================================
; STAGE 3: NATIVE COMPILER BACKEND CODE GENERATOR RULES
; =====================================================================
; ---------------------------------------------------------------------
; PARSER RULE: compile_print_statement
; Grammar Syntax Checked: PRINT [variable_or_string];
; Description: Emits the native 16-bit runtime instructions to load 
;              data structures and call the physical UART serial loops.
; ---------------------------------------------------------------------
compile_print_statement:
    CAL advanceToken             ; Consume "PRINT" keyword, fetch target token

    ; --- PATH A: COMPILE PRINT STRING LITERAL ---
    STJ .emit_string_print
    JEQ R5 0x4000                ; Check if token type is 0x4000 (String Literal)

    ; --- PATH B: COMPILE PRINT VARIABLE ---
    STJ .print_syntax_error
    JNE R5 0x1000                ; If it's not a string, it MUST be a Variable ID

    ADD R1 R4 0x0000             ; R1 = Target Variable Name Hash
    CAL get_variable_address     ; Look up its absolute address in your compiled data pool
    STM M$[Print_Target_Addr] R3 ; Cache variable storage offset RAM location address

    ; 1. Emit Runtime Memory Load: Fetch variable from RAM into register R4 at runtime
    ; Generates packed machine code: LDM R4, M$[Print_Target_Addr]
    ADD R1 0x0009 0x0000              ; Opcode 9 (LDM)
    ADD R2 0x00004 0x0000              ; Destination register = R4
    XOR R3 R3 R3
    XOR R4 R4 R4
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    LDM R1 M$[Print_Target_Addr]
    CAL emit_word                ; Append the inline absolute RAM data address word

    ; 2. Emit Runtime Subroutine Call: CAL print_string_hardware
    ; Generates packed machine code: CAL absolute_print_loop_address
    ADD R1 0x000D 0x0000             ; Opcode 13 (CAL)
    XOR R2 R2 R2
    XOR R3 R3 R3
    XOR R4 R4 R4
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 print_string_hardware ; Target location coordinate link
    CAL emit_word                ; Append absolute inline destination jump pointer

    STJ .print_clean_exit
    JMP

.emit_string_print:
    ; For string literals, advanceToken leaves the compiled address pointer in R3
    ADD R4 R3 0x0000             ; R4 = String Data Address
    
    ; Emit Runtime Subroutine Call straight to your character loop
    ADD R1 13 0x0000             ; Opcode 13 (CAL)
    XOR R2 R2 R2
    XOR R3 R3 R3
    XOR R4 R4 R4
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 print_string_hardware
    CAL emit_word                
    
.print_clean_exit:
    CAL advanceToken             ; Consume the data token parameter frame
    CAL advanceToken             ; Consume the trailing statement semicolon ';'
    RET

.print_syntax_error:
    CAL trigger_syntax_error
    STJ parser_fail
    JMP

; ---------------------------------------------------------------------
; PARSER RULE: compile_if_statement
; ---------------------------------------------------------------------
compile_if_statement:
CAL advanceToken ; Consume "if"
STJ .if_syntax_error
JNE R5 0x3000
JNE R4 0x0028 ; Expect opening parenthesis '('
CAL advanceToken

CAL compile_expression ; Compile internal condition -> leaves result inside a free register (R5)

STJ .if_syntax_error
JNE R5 0x3000
JNE R4 0x0029 ; Expect closing parenthesis ')'
CAL advanceToken
; currentToken is now sitting on '{' - parse_code_block consumes it
; itself, so we must NOT call advanceToken again here (that was
; skipping past '{' entirely and making parse_code_block's own brace
; check fail on every single if-statement).

; --- EMIT CONDITIONAL JUMP OUT IF FALSE ---
LDM R7 M$[COMPILED_BINARY_BASE]
STM M$[If_Placeholder_Address] R7 ; Cache placeholder slot for backpatching

; Emit blank Opcode 12 branch instruction: JEQ [Condition_Reg], R0, 0x0000
ADD R1 12 0x0000 ; Opcode 12 (Jump)
ADD R2 R5 0x0000 ; Dest = Verified expression register target
XOR R3 R3 R3 ; SrcX = R0 (Checking if it equals 0/False)
XOR R4 R4 R4 ; SrcY = 0
XOR R5 R5 R5 ; Flag mask = 0
CAL pack_and_emit_instruction

CAL parse_code_block ; Recursively compile inner statement machine instructions

; --- BACKPATCH OUT POINTER LANDING TARGET ---
LDM R1 M$[If_Placeholder_Address]
LDM R2 M$[COMPILED_BINARY_BASE] ; Current absolute compilation address
CAL backpatch_jump ; Patch forward branch
RET

.if_syntax_error:
CAL trigger_syntax_error
STJ parser_fail
JMP

; ---------------------------------------------------------------------
; PARSER RULE: compile_while_loop
; ---------------------------------------------------------------------
compile_while_loop:
CAL advanceToken ; Consume "while"
STJ .while_syntax_error
JNE R5 0x3000
JNE R4 0x0028 ; Check '('
CAL advanceToken

; --- RECORD REWIND ANCHOR ---
LDM R7 M$[COMPILED_BINARY_BASE]
STM M$[Loop_Start_Anchor] R7 ; Anchor pointer destination for loop rewinding

CAL compile_expression ; Compile the iteration conditional verification logic

STJ .while_syntax_error
JNE R5 0x3000
JNE R4 0x0029 ; Check ')'
CAL advanceToken
; currentToken is now sitting on '{' - see note in compile_if_statement
; above; parse_code_block consumes it itself.

; --- EMIT FAILURE BREAKOUT BRANCH ---
LDM R7 M$[COMPILED_BINARY_BASE]
STM M$[Loop_Exit_Placeholder] R7 ; Cache address layout for exit patch

; Emit blank Opcode 12 branch out instruction: JEQ [Condition_Reg], R0, 0x0000
ADD R1 12 0x0000 ; Opcode 12
ADD R2 R5 0x0000 ; Target loop condition evaluation register
XOR R3 R3 R3  
XOR R4 R4 R4 
XOR R5 R5 R5
CAL pack_and_emit_instruction

CAL parse_code_block ; Compile the loop payload statements sequentially

; --- EMIT REWIND LOOP UNCONDITIONAL JUMP ---
ADD R1 12 0x0000 ; Opcode 12
XOR R2 R2 R2  
XOR R3 R3 R3  
XOR R4 R4 R4  
XOR R5 R5 R5
CAL pack_and_emit_instruction

LDM R1 M$[COMPILED_BINARY_BASE]
SUB R1 R1 0x0001 ; Target the final emitted opcode word
LDM R2 M$[Loop_Start_Anchor]
CAL backpatch_jump

; --- BACKPATCH THE EXIT BREAK TARGET ---
LDM R1 M$[Loop_Exit_Placeholder]
LDM R2 M$[COMPILED_BINARY_BASE]
CAL backpatch_jump ; Patch forward branch landing zone
RET

.while_syntax_error:
CAL trigger_syntax_error
STJ parser_fail
JMP

; ---------------------------------------------------------------------
; PARSER RULE: compile_assignment
; ---------------------------------------------------------------------
compile_assignment:
ADD R1 R4 0x0000 ; R1 = Target Variable Hash
CAL get_variable_address ; Returns dynamic linked RAM pointer inside R3
STM M$[Target_Var_Address] R3

CAL advanceToken
CAL advanceToken ; Consume variable name and '='
CAL compile_expression ; Returns compiled execution register inside R5

; Emit: STM [Target_Var_Address], R5   (opcode 10, form N_R_R:
;   field2/X = target address -> immediate, LX flag set
;   field3/Y = value register -> R5, no LY flag)
; Previously this hand-rolled the packing inline using the multiplier
; coprocessor with the operands backwards (M$[value] address instead
; of M$[address] value) and never placed R5 into the correct field at
; all. Using pack_and_emit_instruction directly matches how every
; other instruction in this file is emitted.
LDM R3 M$[Target_Var_Address]
ADD R1 0x000A 0x0000 ; Opcode 10 (STM)
XOR R2 R2 R2         ; dest field unused for STM
XOR R3 R3 R3         ; srcX unused directly - address goes via LX + emit_word below
ADD R4 R5 0x0000     ; srcY = value register (R5, from compile_expression)
ADD R5 0x0080 0x0000 ; flags = LX only (0x80) - field2/address is immediate
CAL pack_and_emit_instruction
LDM R1 M$[Target_Var_Address]
CAL emit_word         ; Append inline absolute tracking address target word
CAL free_register
CAL advanceToken
RET

; ---------------------------------------------------------------------
; PARSER RULE: compile_for_loop
; ---------------------------------------------------------------------
compile_for_loop:
CAL advanceToken ; Consume "FOR", fetch loop variable ID
ADD R1 R4 0x0000 ; R1 = Loop Counter Variable Hash
STM M$[For_Var_Backup] R1

CAL advanceToken 
CAL advanceToken ; Consume variable and '='
CAL compile_expression ; Compile start expression -> leaves value reg in R5

; Setup counter: STM R5, Variable_RAM  (see compile_assignment note
; above - same fix applied here.)
LDM R1 M$[For_Var_Backup]
CAL get_variable_address ; R3 = variable's RAM address
STM M$[Target_Var_Address] R3
ADD R1 0x000A 0x0000 ; Opcode 10 (STM)
XOR R2 R2 R2
XOR R3 R3 R3
ADD R4 R5 0x0000
ADD R5 0x0080 0x0000
CAL pack_and_emit_instruction
LDM R1 M$[Target_Var_Address]
CAL emit_word
CAL free_register
CAL advanceToken ; Consume "TO"

; --- RECORD LOOP ANCHOR ---
LDM R7 M$[COMPILED_BINARY_BASE]  
STM M$[For_Condition_Anchor] R7

CAL compile_expression ; Compile end threshold expression -> Reg R5

; --- EMIT RECOMPARE & BRANCH BREAKOUT ---
LDM R7 M$[COMPILED_BINARY_BASE]  
STM M$[For_Exit_Placeholder] R7
ADD R1 12 0x0000 
XOR R2 R2 R2  
XOR R3 R3 R3 
XOR R4 R4 R4 
XOR R5 R5 R5  
CAL pack_and_emit_instruction

CAL parse_code_block ; Compile body contents (consumes '{' itself)

; --- EMIT LOOP-VARIABLE INCREMENT ---
; The original codegen never incremented the loop counter here at all,
; which made every "for" loop either infinite or entirely dependent on
; the body incrementing it by hand. Emit: var = var + 1.
LDM R1 M$[For_Var_Backup]
CAL get_variable_address        ; R3 = loop variable's RAM address
STM M$[Target_Var_Address] R3

ADD R1 0x0009 0x0000            ; Opcode 9 (LDM)
CAL allocate_register
ADD R2 R0 0x0000                ; R2 = freshly allocated temp register
XOR R3 R3 R3
XOR R4 R4 R4
XOR R5 R5 R5
CAL pack_and_emit_instruction
LDM R1 M$[Target_Var_Address]
CAL emit_word                   ; LDM temp, [loop_var]

ADD R1 0x0001 0x0000            ; Opcode 1 (ADD)
ADD R3 R2 0x0000                ; srcX = temp
ADD R4 0x0001 0x0000            ; RHS immediate: +1
ADD R5 0x0008 0x0000            ; LY flag - RHS is immediate, not register
CAL pack_and_emit_instruction
ADD R1 0x0001 0x0000
CAL emit_word                   ; ADD temp, temp, #1

ADD R1 0x000A 0x0000            ; Opcode 10 (STM)
XOR R2 R2 R2
XOR R3 R3 R3
ADD R4 R2 0x0000
ADD R5 0x0080 0x0000
CAL pack_and_emit_instruction
LDM R1 M$[Target_Var_Address]
CAL emit_word                   ; STM [loop_var], temp

ADD R1 R2 0x0000
CAL free_register

; --- EMIT REWIND JUMP BACK TO CONDITION ---
ADD R1 12 0x0000  
XOR R2 R2 R2 
XOR R3 R3 R3  
XOR R4 R4 R4 
XOR R5 R5 R5  
CAL pack_and_emit_instruction
LDM R1 M$[COMPILED_BINARY_BASE]  
SUB R1 R1 0x0001
LDM R2 M$[For_Condition_Anchor] 
CAL backpatch_jump

; --- BACKPATCH BREAKOUT LANDING ZONE ---
LDM R1 M$[For_Exit_Placeholder]  
LDM R2 M$[COMPILED_BINARY_BASE]  
CAL backpatch_jump 
RET

compile_function_call:
ADD R1 13 0x0000 ; Opcode 13 (CAL)
XOR R2 R2 R2 
XOR R3 R3 R3  
XOR R4 R4 R4 
XOR R5 R5 R5
CAL pack_and_emit_instruction

LDM R1 M$[COMPILED_BINARY_BASE] 
SUB R1 R1 0x0001
LDM R2 M$[Target_Func_Anchor_Address]  
CAL backpatch_jump  
RET

parse_code_block:
STJ .brace_error
JNE R5 0x3000
JNE R4 0x007B ; Check '{'
CAL advanceToken

.statement_loop:
STJ .block_done
JEQ R5 0x3000
STJ .continue_parsing
JMP

.continue_parsing:
STJ .brace_error
JEQ R5 0x0000 ; Catch open un-closed blocks
CAL parser_statement_dispatcher
STJ .statement_loop
JMP

.block_done:
STJ .continue_parsing
JNE R4 0x007D ; Break loop if '}'
CAL advanceToken
RET

.brace_error:
CAL trigger_syntax_error
STJ parser_fail
JMP

parse_function_declaration:
CAL advanceToken
STJ .func_syntax_error
JNE R5 0x1000 ; Expect identifier name
ADD R1 R4 0x0000 ; R1 = Function Name Hash

LDM R7 M$[FUNCTION_TABLE_BASE]
STM M$[R7] R1
ADD R7 R7 0x0001
STM M$[R7] R6 ; Write entry point code offset tracking coordinate anchor
ADD R7 R7 0x0001
STM M$[FUNCTION_TABLE_BASE] R7

CAL advanceToken
STJ .func_syntax_error
JNE R5 0x3000
JNE R4 0x0028 ; Check '('
CAL advanceToken
STJ .func_syntax_error
JNE R5 0x3000
JNE R4 0x0029 ; Check ')'
CAL advanceToken

CAL skip_code_block ; Skip body declaration definition step compilation pass
RET

.func_syntax_error:
CAL trigger_syntax_error 
 STJ parser_fail  
JMP

; =====================================================================
; STAGE 4: HARDWARE-ACCELERATED EXPRESSION COMPILER BACKEND
; =====================================================================
compile_expression:
STJ .left_is_variable   
JEQ R5 0x1000
STJ .left_is_literal_num   
JEQ R5 0x2000
CAL trigger_syntax_error 
STJ parser_fail  
 JMP

.left_is_variable:
ADD R1 R4 0x0000
CAL get_variable_address
CAL allocate_register  
ADD R5 R0 0x0000 ; R5 = LHS runtime register

; Emit code for: LDM R5, M$[Variable_Address]
ADD R1 0x0009 0x0000 ; Opcode 9 (LDM)
ADD R2 R5 0x0000  
XOR R3 R3 R3  
XOR R4 R4 R4   
XOR R5 R5 R5   
CAL pack_and_emit_instruction
ADD R1 R3 0x0000   
CAL emit_word
STJ .check_for_operator   
JMP

.left_is_literal_num:
CAL allocate_register
ADD R5 R0 0x0000
ADD R2 R5 0x0000
ADD R3 R3 0x0000
CAL compile_load_immediate ; Emit literal load into register R5 at runtime
STJ .check_for_operator
JMP

.check_for_operator:
CAL advanceToken
STJ .expression_done
JNE R5 0x3000
JEQ R4 0x003B
JEQ R4 0x0029

ADD R1 R4 0x0000 ; R1 = Operator symbol
CAL advanceToken
STJ .right_is_variable
JEQ R5 0x1000
STJ .right_is_literal
JEQ R5 0x2000
CAL trigger_syntax_error
STJ parser_fail
JMP

.right_is_variable:
STM M$[Scratch1] R1
STM M$[Scratch2] R5
STM M$[Scratch3] R3
ADD R1 R4 0x0000
CAL get_variable_address
CAL allocate_register
ADD R6 R0 0x0000 ; R6 = RHS runtime register

; Emit: LDM R6, M$[RHS_Variable_Address]
ADD R1 9 0x0000
ADD R2 R6 0x0000
XOR R3 R3 R3
XOR R4 R4 R4
XOR R5 R5 R5
CAL pack_and_emit_instruction

ADD R1 R3 0x0000
CAL emit_word
NIL
LDM R1 M$[Scratch1]
LDM R2 M$[Scratch2]
LDM R4 M$[Scratch3]
STJ .emit_math_instructions
JMP

.right_is_literal:
CAL allocate_register
ADD R6 R0 0x0000
ADD R2 R6 0x0000
CAL compile_load_immediate ; Emit code to load RHS literal into register R6 at runtime
STJ .emit_math_instructions
JMP

; =====================================================================
; MASTER CODE GENERATION EMITTER HUB
; =====================================================================
.emit_math_instructions:
    STJ .emit_subtraction
    JEQ R1 0x002D                ; ASCII '-' character
    
    STJ .emit_multiplication
    JEQ R1 0x002A                ; ASCII '*' character
    
    STJ .emit_bitwise_and
    JEQ R1 0x0026                ; ASCII '&' character
    
    STJ .emit_bitwise_or
    JEQ R1 0x007C                
    ; ASCII '|' character
    NIL 
    STJ .emit_equality
    JEQ R1 0x003D                
    ; ASCII '=' character

    STJ .emit_less_than
    JEQ R1 0x003C                ; ASCII '<' character
    
    STJ .emit_greater_than
    JEQ R1 0x003E                ; ASCII '>' character

    ; --- 1. DEFAULT LOGIC: EMIT NATIVE REGISTER ADDITION ---
    ; Compiles: ADD LHS_Reg, LHS_Reg, RHS_Reg
    ADD R1 0x0001 0x0000         ; Opcode 1 (ADD)
    ADD R3 R2 0x0000             ; Source X = LHS Register Code
    ADD R4 R6 0x0000             ; Source Y = RHS Register Code
    XOR R5 R5 R5                 ; Control Flags = 0 (Register-to-Register)
    CAL pack_and_emit_instruction
    
    ; Free the temporary RHS register so Ralloc can reuse it
    ADD R1 R6 0x0000             
    CAL free_register
    ADD R5 R2 0x0000             ; Return our finalized value register index inside R5
    STJ .expression_done
    JMP

; ---------------------------------------------------------------------
; 2. NATIVE COPROCESSOR MULTIPLICATION GENERATOR
; ---------------------------------------------------------------------
.emit_multiplication:
    ; Emit runtime context shift: EAM.SET 0x07FF
    ADD R1 0x0800 0x0000         ; Pack Opcode 0 + M_flag active
    CAL emit_word                

    ; Emit code to load LHS register value into Mult Staging input lane A: STM LHS_Reg, M$[0xFFFD]
    ADD R1 10 0x0000             ; Opcode 10 (STM)
    ADD R2 R2 0x0000             ; Source = LHS Register
    XOR R3 R3 R3 
    XOR R4 R4 R4 
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 0xFFFD         ; Hardware Port: MULT_REG_A
    CAL emit_word

    ; Emit code to load RHS register value into Mult Staging input lane B: STM RHS_Reg, M$[0xFFFC]
    ADD R1 10 0x0000             ; Opcode 10 (STM)
    ADD R2 R6 0x0000             ; Source = RHS Register
    XOR R3 R3 R3 
    XOR R4 R4 R4 
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 0xFFFC         ; Hardware Port: MULT_REG_B
    CAL emit_word

    ; Emit code to fire execution command lane: STM R0, M$[0xFFE9] (Writes 0 using R0)
    ADD R1 10 0x0000             ; Opcode 10 (STM)
    XOR R2 R2 R2                 ; Source = R0 (Static Zero)
    XOR R3 R3 R3 
    XOR R4 R4 R4 
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 0xFFE9         ; Multiplication Execute Trigger
    CAL emit_word

    ; Emit code to harvest computed product result back into LHS register: LDM LHS_Reg, M$[0xFFFB]
    ADD R1 9 0x0000              ; Opcode 9 (LDM)
    ADD R2 R2 0x0000             ; Destination = LHS Register
    XOR R3 R3 R3 
    XOR R4 R4 R4 
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 0xFFFB         ; Hardware Port: MULT_REG_OUT
    CAL emit_word

    ; Emit runtime bank restore: EAM.SET 0x0000
    XOR R1 R1 R1                 ; Opcode 0, clear flags
    CAL emit_word                

    ; Clean up register tracking
    ADD R1 R6 0x0000             
    CAL free_register            
    ADD R5 R2 0x0000             ; Return destination register in R5
    STJ .expression_done
    JMP

; ---------------------------------------------------------------------
; 3. NATIVE COPROCESSOR SUBTRACTION GENERATOR
; ---------------------------------------------------------------------
.emit_subtraction:
    ADD R1 0x0800 0x0000         ; Opcode 0 + M_flag active (EAM.SET 0x07FF)
    CAL emit_word

    ; Emit Low Word Write: STM LHS_Reg, M$[0xFFED]
    ADD R1 10 0x0000             
    ADD R2 R2 0x0000
    XOR R3 R3 R3 
    XOR R4 R4 R4  
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 0xFFED         
    CAL emit_word
    
    ; Emit High Word Write: STM RHS_Reg, M$[0xFFEA]
    ADD R1 10 0x0000
    ADD R2 R6 0x0000
    XOR R3 R3 R3 
    XOR R4 R4 R4
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 0xFFEA         
    CAL emit_word
    
    ; Fire subtraction trigger: STM R0, M$[0xFFE9] with payload 0x0002
    ADD R1 10 0x0000
    XOR R2 R2 R2
    XOR R3 R3 R3  
    XOR R4 R4 R4   
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 0xFFE9
    CAL emit_word

    ; Harvest calculation low word back into register via LDM
    ADD R1 9 0x0000              ; Opcode 9 (LDM)
    ADD R2 R2 0x0000
    XOR R3 R3 R3  
    XOR R4 R4 R4  
    XOR R5 R5 R5
    CAL pack_and_emit_instruction
    ADD R1 0x0000 0xFFE8         
    CAL emit_word

    ; Reset runtime memory bank (EAM.SET 0x0000)
    XOR R1 R1 R1 
    CAL emit_word
    
    ADD R1 R6 0x0000             
    CAL free_register
    ADD R5 R2 0x0000             
    STJ .expression_done
    JMP

; ---------------------------------------------------------------------
; 4. BITWISE ENGINE GENERATORS
; ---------------------------------------------------------------------
.emit_bitwise_and:
    ADD R1 3 0x0000              ; Opcode 3 (Bitwise AND)
    ADD R3 R2 0x0000   
    ADD R4 R6 0x0000  
    XOR R5 R5 R5  
    CAL pack_and_emit_instruction
    ADD R1 R6 0x0000  
    CAL free_register 
    ADD R5 R2 0x0000 
    STJ .expression_done 
    JMP

.emit_bitwise_or:
    ADD R1 4 0x0000              ; Opcode 4 (Bitwise OR)
    ADD R3 R2 0x0000   
    ADD R4 R6 0x0000  
    XOR R5 R5 R5  
    CAL pack_and_emit_instruction
    ADD R1 R6 0x0000  
    CAL free_register 
    ADD R5 R2 0x0000  
    STJ .expression_done 
    JMP

; ---------------------------------------------------------------------
; 5. RELATIONAL LOGIC AND COMPARISON GENERATORS (==, <, >)
; ---------------------------------------------------------------------
.emit_equality:
    ; Emit Runtime Subtraction: LHS = LHS - RHS
    ADD R1 2 0x0000              ; Opcode 2 (SUB)
    ADD R3 R2 0x0000 
    ADD R4 R6 0x0000
    XOR R5 R5 R5
    CAL pack_and_emit_instruction

    LDM R7 M$[COMPILED_BINARY_BASE] 
    STM M$[Rel_Placeholder_Address] R7
    
    ; Emit blank Opcode 12 (JNE LHS_Reg, R0, BLANK) -> Jumps to False block if result != 0
    ADD R1 12 0x0000  
    ADD R2 R2 0x0000 
    XOR R3 R3 R3
    XOR R4 R4 R4 
    XOR R5 R5 R5
    CAL pack_and_emit_instruction

    ; TRUE BLOCK: Load 1 into register at runtime
    ADD R3 0x0001 0x0000
    CAL compile_load_immediate
    LDM R7 M$[COMPILED_BINARY_BASE]
    STM M$[Rel_Skip_Placeholder] R7
    
    ; Emit absolute JMP forward past False block
    ADD R1 12 0x0000
    XOR R2 R2 R2
    XOR R3 R3 R3
    XOR R4 R4 R4 
    XOR R5 R5 R5 
    CAL pack_and_emit_instruction

    ; FALSE BLOCK: Land here if they aren't equal
    LDM R1 M$[Rel_Placeholder_Address]   
    LDM R2 M$[COMPILED_BINARY_BASE] 
    CAL backpatch_jump
    ADD R3 0x0000 0x0000 
    CAL compile_load_immediate

    ; CLOSE REPL PIPELINE BOUNDARIES
    LDM R1 M$[Rel_Skip_Placeholder]
    LDM R2 M$[COMPILED_BINARY_BASE]   
    CAL backpatch_jump
    ADD R1 R6 0x0000   
    CAL free_register 
    ADD R5 R2 0x0000 
    STJ .expression_done 
    JMP

.emit_less_than:
    ; Emit Runtime Subtraction: LHS = LHS - RHS
    ADD R1 2 0x0000              ; Opcode 2 (SUB)
    ADD R3 R2 0x0000 
    ADD R4 R6 0x0000 
    XOR R5 R5 R5
    CAL pack_and_emit_instruction

    LDM R7 M$[COMPILED_BINARY_BASE] 
    STM M$[Rel_Placeholder_Address] R7
    
    ; Emit blank Opcode 12 (JGE LHS_Reg, R0, BLANK) -> Jumps to False block if result >= 0
    ADD R1 12 0x0000   
    ADD R2 R2 0x0000 
    XOR R3 R3 R3 
    XOR R4 R4 R4 
    XOR R5 R5 R5  
    CAL pack_and_emit_instruction

    ; TRUE BLOCK: Load 1 into LHS_Reg at runtime
    ADD R3 0x0001 0x0000  
    CAL compile_load_immediate
    LDM R7 M$[COMPILED_BINARY_BASE]   
    STM M$[Rel_Skip_Placeholder] R7
    
    ; Emit absolute JMP forward
    ADD R1 12 0x0000   
    XOR R2 R2 R2  
    XOR R3 R3 R3  
    XOR R4 R4 R4  
    XOR R5 R5 R5 
    CAL pack_and_emit_instruction

    ; FALSE BLOCK landing zone
    LDM R1 M$[Rel_Placeholder_Address]   
    LDM R2 M$[COMPILED_BINARY_BASE] 
    CAL backpatch_jump
    ADD R3 0x0000 0x0000
    CAL compile_load_immediate

    ; CLOSE REPL PIPELINE BOUNDARIES
    LDM R1 M$[Rel_Skip_Placeholder] 
    LDM R2 M$[COMPILED_BINARY_BASE] 
    CAL backpatch_jump
    ADD R1 R6 0x0000   
    CAL free_register 
    ADD R5 R2 0x0000  
    STJ .expression_done 
    JMP

.emit_greater_than:
    ; Emit Runtime Subtraction: LHS = LHS - RHS
    ADD R1 2 0x0000              ; Opcode 2 (SUB)
    ADD R3 R2 0x0000 
    ADD R4 R6 0x0000  
    XOR R5 R5 R5 
    CAL pack_and_emit_instruction

    LDM R7 M$[COMPILED_BINARY_BASE]   
    STM M$[Rel_Placeholder_Address] R7
    
    ; Emit blank Opcode 12 (JLE LHS_Reg, R0, BLANK) -> Jumps to False block if result <= 0
    ADD R1 12 0x0000   
    ADD R2 R2 0x0000   
    XOR R3 R3 R3 
    XOR R4 R4 R4 
    XOR R5 R5 R5   
     CAL pack_and_emit_instruction

    ; TRUE BLOCK: Load 1 into LHS_Reg at runtime
    ADD R3 0x0001 0x0000          
    CAL compile_load_immediate
    LDM R7 M$[COMPILED_BINARY_BASE]  
    STM M$[Rel_Skip_Placeholder] R7
    
    ; Emit absolute JMP forward
    ADD R1 12 0x0000  
    XOR R2 R2 R2  
    XOR R3 R3 R3  
    XOR R4 R4 R4 
    XOR R5 R5 R5  
    CAL pack_and_emit_instruction

    ; FALSE BLOCK landing zone
    LDM R1 M$[Rel_Placeholder_Address]   
    LDM R2 M$[COMPILED_BINARY_BASE] 
    CAL backpatch_jump
    ADD R3 0x0000 0x0000         
    CAL compile_load_immediate

    ; CLOSE REPL PIPELINE BOUNDARIES
    LDM R1 M$[Rel_Skip_Placeholder]  
    LDM R2 M$[COMPILED_BINARY_BASE] 
    CAL backpatch_jump
    ADD R1 R6 0x0000   
    CAL free_register  
    ADD R5 R2 0x0000  
    STJ .expression_done  
    JMP

.expression_done:
    RET

; =====================================================================
; STAGE 5: COMPILER UTILITY SYSTEM DRIVER LAYER
; =====================================================================
skip_code_block:
STJ .skip_brace_error
JNE R5 0x3000
JNE R4 0x007B
ADD R1 0x0001 0x0000

.skip_loop:
CAL advanceToken
STJ .skip_eof_error
JEQ R5 0x0000
STJ .check_symbol
JEQ R5 0x3000
STJ .skip_loop
JMP

.check_symbol:
STJ .found_open_brace
JEQ R4 0x007B
STJ .found_close_brace
JEQ R4 0x007D
STJ .skip_loop
JMP

.found_open_brace:
ADD R1 R1 0x0001
STJ .skip_loop
JMP

.found_close_brace:
SUB R1 R1 0x0001
STJ .check_depth_done
JEQ R1 0x0000
STJ .skip_loop
JMP

.check_depth_done:
CAL advanceToken
RET

.skip_brace_error:
.skip_eof_error:
CAL trigger_syntax_error
STJ parser_fail
JMP

get_variable_address:
; --- REMOVED TRAP: NATIVE DATA-SEGMENT ADDRESS POOL ALLOCATOR ---
CAL get_variable
STJ .allocate_new_data_slot
JMP

.allocate_new_data_slot:
LDM R3 M$[COMPILED_BINARY_BASE] ; Pull absolute free space address pointer (e.g. 0x0060'0000)
XOR R2 R2 R2 ; High Word = 0x0000
CAL set_variable ; Record mapping link permanently inside database
ADD R3 R3 0x0002 ; Increment pool boundary pointer by 4 bytes (2 words)
STM M$[COMPILED_BINARY_BASE] R3
SUB R3 R3 0x0002 ; Rewind tracker to return absolute target allocation address
RET

get_variable:
ADD R7 0x0000 SYMBOL_TABLE_BASE

.local_search_loop:
LDM R0 M$[R7]
STJ .global_fallback_setup
JEQ R0 0x0000

STJ .check_local_scope
JEQ R0 R1

.advance_local_row:
ADD R7 R7 0x0004
STJ .local_search_loop
JMP

.check_local_scope:
ADD R7 R7 0x0001
LDM R0 M$[R7]
SUB R7 R7 0x0001
STJ .extract_value
JEQ R0 R5
STJ .advance_local_row
JMP

.global_fallback_setup:
ADD R7 0x0000 SYMBOL_TABLE_BASE

.global_search_loop:
LDM R0 M$[R7] ; Read Variable Name Hash
STJ .variable_undefined_error
JEQ R0 0x0000 ; Not found globally either? Variable does not exist!

STJ .check_global_scope
JEQ R0 R1 ; Name matches!

.advance_global_row:
ADD R7 R7 0x0004 ; Move to next 4-word row frame
STJ .global_search_loop
JMP

.check_global_scope:
ADD R7 R7 0x0001 ; Move to Word 1 (Scope ID slot)
LDM R0 M$[R7] ; Read Scope ID
SUB R7 R7 0x0001 ; Rewind pointer to Word 0

STJ .extract_value
JEQ R0 0x0000 ; If Scope ID is exactly 0 (Global), we harvest it!
STJ .advance_global_row ; Otherwise, it belongs to a different function -> keep moving
JMP

.extract_value:
ADD R7 R7 0x0002 ; Skip past Name and Scope straight to High Value Word
LDM R2 M$[R7] ; Pull High Word into R2
ADD R7 R7 0x0001 ; Move to Low Value Word
LDM R3 M$[R7] ; Pull Low Word into R3
RET ; Clean return. R2/R3 contains your variables!

.variable_undefined_error:
CAL trigger_syntax_error ; Broadcast 'ERR' over UART
STJ parser_fail
JMP

; ---------------------------------------------------------------------
; BACKEND DIRECTORY LOOKUP: lookup_function_anchor
; Input: R1 = Target Function Name Hash
; Output: R0 = Token Stream Code Start Address Anchor
; ---------------------------------------------------------------------
lookup_function_anchor:
ADD R7 0x0000 FUNCTION_TABLE_BASE ; Point to your function directory base

.func_lookup_loop:
LDM R0 M$[R7] ; Read registered function name hash
STJ .function_not_found_error
JEQ R0 0x0000 ; Hit unallocated empty space -> function doesn't exist!

STJ .found_func_match
JEQ R0 R1 ; Found the function match!

ADD R7 R7 0x0003 ; Move pointer forward by 3 words (High + Low + Code Anchor)
STJ .func_lookup_loop
JMP

.found_func_match:
ADD R7 R7 0x0002 ; Advance to Word 2 (Token offset code anchor location)
LDM R0 M$[R7] ; Pull the token code anchor coordinate into R0
RET

.function_not_found_error:
CAL trigger_syntax_error ; Stream 'ERR' out over UART
STJ parser_fail
JMP

; ---------------------------------------------------------------------
; SUBROUTINE: check_if_function_exists (Upgraded 32-Bit Safe Scan Pass)
; Input: R1 = Hash High Word, R0 = Hash Low Word
; Output: R3 = 1 if it is a registered function, 0 if it is a variable
; ---------------------------------------------------------------------
check_if_function_exists:
ADD R7 0x0000 FUNCTION_TABLE_BASE ; Point to your function table base address

.func_check_loop:
LDM R5 M$[R7] ; Read Function Hash High Word from table row
STJ .is_a_variable
JEQ R5 0x0000 ; Hit unallocated empty space -> it's a variable!

STJ .check_low_word
JEQ R5 R1 ; High word matches! Go check the low word signature.

.advance_func_check_row:
ADD R7 R7 0x0003 ; Move pointer forward by 3 words
STJ .func_check_loop
JMP

.check_low_word:
ADD R7 R7 0x0001 ; Advance pointer to Word 1 (Low Word slot)
LDM R5 M$[R7] ; Read Function Hash Low Word
SUB R7 R7 0x0001 ; Rewind pointer back to Word 0 for layout safety

STJ .is_a_function
JEQ R5 R0 ; Both High AND Low words match completely! Found it!
STJ .advance_func_check_row ; Low word mismatch -> skip to next row entry
JMP

.is_a_function:
ADD R3 0x0001 0x0000 ; Output 1 (True: this name belongs to a function)
RET

.is_a_variable:
XOR R3 R3 R3 ; Output 0 (False: this name belongs to a regular variable)
RET

; ---------------------------------------------------------------------
; SUBROUTINE: set_variable (With Local Scoping & 32-Bit Alignment)
; Input: R1 = Variable Hash, R5 = Current Scope, R2 = Val High, R3 = Val Low
; ---------------------------------------------------------------------
set_variable:
ADD R7 0x0000 SYMBOL_TABLE_BASE

.set_search_loop:
LDM R0 M$[R7] ; Read the Variable Name Hash at current row
STJ .append_new
JEQ R0 0x0000 ; Reached unallocated slot -> append new variable

STJ .check_set_scope
JEQ R0 R1 ; Name matches, but does the scope match?

.advance_set_row:
ADD R7 R7 0x0004 ; Move to next 4-word row frame
STJ .set_search_loop
JMP

.check_set_scope:
ADD R7 R7 0x0001 ; Advance to Word 1 (Scope ID slot)
LDM R0 M$[R7] ; Read the Scope ID from the table row
SUB R7 R7 0x0001 ; Rewind pointer back to Word 0 for uniform layout

STJ .update_existing
JEQ R0 R5 ; Both Name Hash AND Scope match! Go overwrite it.
STJ .advance_set_row ; Scope mismatch (same name, different function) -> skip
JMP

.update_existing:
ADD R7 R7 0x0002 ; Move past Hash and Scope to High Value Word
STM M$[R7] R2 ; Write High Word
ADD R7 R7 0x0001 ; Move to Low Value Word
STM M$[R7] R3 ; Write Low Word
RET

.append_new:
LDM R7 M$[SYMBOL_TABLE_BASE]
STM M$[R7] R1 ; Word 0: Variable Name Hash
ADD R7 R7 0x0001
STM M$[R7] R5 ; Word 1: Active Scope ID (R5)
ADD R7 R7 0x0001
STM M$[R7] R2 ; Word 2: High Value Word
ADD R7 R7 0x0001
STM M$[R7] R3 ; Word 3: Low Value Word
ADD R7 R7 0x0001
STM M$[SYMBOL_TABLE_BASE] R7 ; Update global free slot tracker
RET

; =====================================================================
; STAGE 6: COMPILER BACK-END UTILITIES (ALLOCATOR & EMITTERS)
; =====================================================================
emit_word:
LDM R7 M$[COMPILED_BINARY_BASE]
STM M$[R7] R1 ; Write raw compiled instruction opcode to target RAM
ADD R7 R7 0x0001
STM M$[COMPILED_BINARY_BASE] R7 ; Advance generation tracker address
RET

compile_load_immediate:
XOR R1 R1 R1
ADD R1 0x1008 0x0000 ; Base Header: Opcode 1 (ADD) + LY flag active (Fetch inline literal)
EAM.SET 0x07FF
STM M$[MULT_REG_A] R2 ; Shift register ID left by 8 bits into destination field
STM M$[MULT_REG_B] 0x0100
LDM R0 M$[MULT_REG_OUT]
EAM.SET 0x0000
OR R1 R1 R0 ; Pack register token header
CAL emit_word
ADD R1 R3 0x0000 ; Append numerical payload word
CAL emit_word
RET

allocate_register:
LDM R5 M$[free_register_mask] ; Load allocator mask tracking bit pattern
ADD R0 0x0001 0x0000 ; Search indices start at register 1 (Skip static R0)

.alloc_search_loop:
EAM.SET 0x07FF
STM  M$[MULT_REG_A] 0x0001
STM  M$[MULT_REG_B] R0 ; Generate 1 << R0 selector tester bitmask dynamically
LDM R2 M$[MULT_REG_OUT]
EAM.SET 0x0000

AND R1 R5 R2 ; Isolate target bit position
STJ .found_free_reg
JEQ R1 0x0000 ; If bit position evaluates to 0, register is free! Claim it.

ADD R0 R0 0x0001 ; Step search forward
STJ .alloc_search_loop
JLT R0 0x0007 ; Keep scanning up until register R7 threshold boundary

CAL trigger_syntax_error ; All registers full (Register Spill required) -> Fail
STJ parser_fail
JMP

.found_free_reg:
OR R5 R5 R2 ; Force claim lock flag onto mask tracking bit position
STM M$[free_register_mask] R5
RET

free_register:
EAM.SET 0x07FF
STM M$[MULT_REG_A] 0x0001 
STM M$[MULT_REG_B] R1 
LDM R2 M$[MULT_REG_OUT] ; Compute mask = 1 << register_id
EAM.SET 0x0000
XOR R2 R2 0xFFFF ; Invert mask bits to clear targeting slot
LDM R5 M$[free_register_mask]
AND R5 R5 R2 ; Free claimed slot back to bitmask allocator
STM M$[free_register_mask] R5
RET

backpatch_jump:
LDM R5 M$[R1] ; Fetch old placeholder jump opcode from binary line buffer track
AND R5 R5 0xF000 ; Lock up opcode field, strip placeholder zeros
OR R5 R5 R2 ; Stitch real absolute target address pointer parameter right into slot
STM M$[R1] R5 ; Permanent write-back patch step
RET

pack_and_emit_instruction:
EAM.SET 0x07FF
STM M$[MULT_REG_A] R1 ; Shift Opcode fields up to bits 15-12
STM M$[MULT_REG_B] 0x1000 
LDM R1 M$[MULT_REG_OUT]

STM  M$[MULT_REG_A] R2; Shift Destination field up to bits 10-8
STM  M$[MULT_REG_B] 0x0100
LDM R2 M$[MULT_REG_OUT]

STM  M$[MULT_REG_A] R3; Shift Source X field up to bits 6-4

STM M$[MULT_REG_B] 0x0010
LDM R3 M$[MULT_REG_OUT]
EAM.SET 0x0000
OR R1 R1 R2
OR R1 R1 R3
OR R1 R1 R4 ; Merge Source Y register code byte
OR R1 R1 R5 ; Merge LX/LY operational control flags
CAL emit_word ; Stream finalized binary opcode directly to cache track location
RET
; =====================================================================
; STAGE 7: LOW-LEVEL SILICON CORE SYSTEM COMMUNICATIONS
; =====================================================================
transmit_ready_prompt:

ADD R3 0x0000 prompt_text
CAL print_string_hardware
RET
print_string_hardware:
.stream_loop:
LDM R0 M$[R3]
STJ .string_done
JEQ R0 0x0000 ; Break stream loops at terminating null byte word
EAM.SET 0x07FF
STM M$[0xFFFF] R0 ; Output hardware character byte to UART Tx port matrix line
EAM.SET 0x0000
ADD R3 R3 0x0001 ; Increment string buffer offset tracker index pointer
STJ .stream_loop
JMP
.string_done:
RET
trigger_syntax_error:
EAM.SET 0x07FF
STM M$[0xFFFF] 0x0045 ; Output 'E' to UART Tx
STM M$[0xFFFF] 0x0052 ; Output 'R' to UART Tx
STM M$[0xFFFF] 0x0052 ; Output 'R' to UART Tx
STM M$[0xFFFF] 0x004F ; Output 'O' to UART Tx
STM M$[0xFFFF] 0x0052 ; Output 'R' to UART Tx
STM M$[0xFFFF] 0x000D ; Carriage Return
STM M$[0xFFFF] 0x000A ; Line Feed
EAM.SET 0x0000
RET
parser_fail:
CAL trigger_syntax_error ; Dump absolute critical failure diagnostic out over UART line
ADD R0 0x0054 0xDEAD ; Diagnostic trace step tracking setup
ADD R0 0xDEAC 0x0000 ; Staging flag
ADD R0 R0 0x0001
ADD R0 R0 0x0000
HLT ; Engage hardware halt state cycle loop on CPU core
