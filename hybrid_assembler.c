#define _CRT_SECURE_NO_WARNINGS
#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <stdbool.h>
#include <assert.h>
#if defined(_WIN32)
#include <windows.h>
#else
#include <unistd.h>
#endif
#define SHIFT_OPCODE  12
#define SHIFT_M_FLAG  11
#define SHIFT_REG_D      8
#define MASK_LX       (1 << 7)
#define SHIFT_REG_X     4
#define MASK_LY       (1 << 3)
#define MASK_REG_Y     0x0007
#define BANK_SIZE 0x10000
#define MASK_M_FLAG (1 << SHIFT_M_FLAG)
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#define MAX_INCLUDE_DEPTH 64

#ifndef _WIN32
/* TEMPORARY COMPATIBILITY SHIM - for testing on Linux only.
   strncpy_s/strcpy_s are MSVC "secure CRT" extensions, not part of
   standard C and not implemented by glibc. The real fix in your source
   should be to either wrap these in #ifdef _WIN32 / #else with the
   plain strncpy/strcpy, or write your own portable safe-copy helper -
   not to leave a hard dependency on a Windows-only function if you
   want this to build anywhere else. */
static int strcpy_s(char* dest, size_t destsz, const char* src)
{
    if (!dest || !src || destsz == 0)
        return 1;

    size_t len = strlen(src);

    if (len >= destsz)
    {
        dest[0] = '\0';
        return 1;
    }

    memcpy(dest, src, len + 1);
    return 0;
}

static int strncpy_s(char* dest, size_t destsz,
    const char* src, size_t count)
{
    if (!dest || !src || destsz == 0)
        return 1;

    if (count >= destsz)
    {
        dest[0] = '\0';
        return 1;
    }

    size_t len = strlen(src);
    size_t copy = (len < count) ? len : count;

    memcpy(dest, src, copy);
    dest[copy] = '\0';

    return 0;
}

#endif
//ATokenType: Named as such to avoid conflict with existing TokenType definitions 
typedef enum {
    TOKEN_MNEMONIC,
    TOKEN_REGISTER,
    TOKEN_IMMEDIATE,
    TOKEN_COMMA,
    TOKEN_NEWLINE,
    TOKEN_EOF
} ATokenType;

// The operation feilds an instruction uses
typedef enum {
    FMT_R_R_R,
    FMT_R_R_N,
    FMT_N_R_R,
    FMT_R_N_R,
    FMT_N_R_N,
    FMT_N_N_N,
    FMT_UNKOWN
} InstForm;

typedef struct {
    char name[32];
    int reg_num;
} Variable;
typedef struct {
    unsigned short bank;
    unsigned short offset;
} Address;


typedef struct {
    char name[64];
    Address address;
} Label;

// for includes
typedef struct {
    char path[PATH_MAX];
} IncludeEntry;


// used in directives
typedef struct {
    char name[64];
    unsigned int value;
} Constant;


typedef struct {
    const char* mnemonic;
    unsigned short base_opcode;
    InstForm form;
} Opcode_entry;


typedef struct
{
    int words;
    int bank_prefix_words;
    int main_words;
    int immediate_words;
    int bank_reset_words;
} InstructionLayout;




/*
 * Calculate exactly how many words Pass 2 will emit for one instruction.
 *
 * This mirrors compile_instruction_safe():
 *
 *   optional bank prefix:
 *       EAM.SET bank       = 2 words
 *
 *   main instruction:
 *       opcode             = 1 word
 *       each immediate     = 1 payload word
 *
 *   optional bank reset:
 *       EAM.SET 0          = 2 words
 */

Constant* constant_table = NULL;
size_t constant_count = 0;
size_t constant_capacity = 0;
IncludeEntry include_stack[MAX_INCLUDE_DEPTH];
int include_depth = 0;
unsigned int actual_output_words = 0;
/// <summary>
/// returns 1 if a file is in the include stack, and 0 otherwise
/// </summary>
/// <param name="file"></param>
/// <returns>
/// 0: Not in stack
/// 1: In stack
/// other: problem 
/// </returns>
int already_included(const char* file)
{
    for (int i = 0; i < include_depth; i++)
    {
        if (strcmp(include_stack[i].path, file) == 0)
            return 1;
    }

    return 0;
}
/// <summary>
/// adds a new constant, given a name and value 
/// </summary>
/// <param name="name"></param>
/// <param name="value"></param>
void add_constant(const char* name, unsigned int value)
{
    if (constant_count >= constant_capacity)
    {
        size_t new_capacity =
            constant_capacity == 0 ? 64 : constant_capacity * 2;

        Constant* new_table =
            realloc(constant_table,
                new_capacity * sizeof(Constant));

        if (!new_table)
        {
            fprintf(stderr, "Out of memory adding constant\n");
            exit(1);
        }

        constant_table = new_table;
        constant_capacity = new_capacity;
    }

    strncpy_s(constant_table[constant_count].name,
        sizeof(constant_table[constant_count].name),
        name,
        sizeof(constant_table[constant_count].name) - 1);

    constant_table[constant_count].name[
        sizeof(constant_table[constant_count].name) - 1] = '\0';

    constant_table[constant_count].value = value;

    constant_count++;
}
/// <summary>
/// looks in the constant table to see if that constant is defined given a name, and can set it a value if found 
/// </summary>
/// <param name="name"></param>
/// <param name="value"></param>
/// <returns>
/// true: constant is known
/// false: unkown constant
/// </returns>
bool lookup_constant(const char* name, unsigned int* value)
{
    for (size_t i = 0; i < constant_count; i++)
    {
        if (strcmp(constant_table[i].name, name) == 0)
        {
            *value = constant_table[i].value;
            return true;
        }
    }

    return false;
}


Label* label_table = NULL;
size_t label_capacity = 0;
size_t label_count = 0;
Address current_address = { 0, 0 };
/// <summary>
/// turns a label token to an address
/// </summary>
/// <param name="token"></param>
/// <returns>
/// Address: The resolved address 
/// </returns>
Address resolve_address(const char* token)
{
    //printf("RESOLVE REQUEST [%s]\n", token);
    Address result = { 0,0 };

    if (!token || token[0] == '\0')
        return result;


    // Labels first
    for (size_t i = 0; i < label_count; i++)
    {
        if (strcmp(label_table[i].name, token) == 0)
        {
           // printf("LABEL MATCH [%s] -> %04X:%04X (index %zu)\n",
            //    label_table[i].name,
             //   label_table[i].address.bank,
             //   label_table[i].address.offset,
              //  i);

            return label_table[i].address;
        }
    }


    // Constants second
    unsigned int value;

    if (lookup_constant(token, &value))
    {
        result.bank = (value >> 16) & 0xFFFF;
        result.offset = value & 0xFFFF;

       // printf("RESOLVE CONST %s = %04X:%04X\n",
       //     token,
       //     result.bank,
       //     result.offset);

        return result;
    }


    // Literal
    value = strtoul(token, NULL, 0);

    result.bank = (value >> 16) & 0xFFFF;
    result.offset = value & 0xFFFF;

    /* printf("RESOLVE LITERAL %s = %04X:%04X\n",
         token,
         result.bank,
         result.offset);
         */
    return result;
}

void compile_instruction_safe(
    Opcode_entry* op,
    char* op1,
    char* op2,
    char* op3,
    FILE* output_file,
    const char* raw_mnemonic);

unsigned short resolve_operand_with_bank(
    const char* operand,
    FILE* output_file,
    int* defer_bank_reset);

static const char* get_target_operand(
    Opcode_entry* op,
    const char* op1,
    const char* op2,
    const char* op3);
/// <summary>
/// advances a banked address
/// </summary>
/// <param name="words"></param>
void advance_address(unsigned int words)
{
    unsigned int full = current_address.offset + words;

    current_address.bank += full >> 16;
    current_address.offset = full & 0xFFFF;
}

/// <summary>
/// converts an Address to 32-bit number
/// </summary>
/// <param name="addr"></param>
/// <returns></returns>
unsigned int address_to_u32(Address addr)
{
    return ((unsigned int)addr.bank << 16) |
        addr.offset;
}
// the acceptable opcodes
Opcode_entry optable[] =
{
    {"EAM.SET",   0x0000, FMT_N_R_N},
    {"IVR.SET",   0x0800, FMT_N_R_N},
    {"ADD",       0x1000, FMT_R_R_R},
    {"SUB",       0x2000, FMT_R_R_R},
    {"AND",       0x3000, FMT_R_R_R},
    {"OR",        0x4000, FMT_R_R_R},
    {"NOT",       0x5000, FMT_R_R_N},
    {"XOR",       0x6000, FMT_R_R_R},
    {"SHL",       0x7000, FMT_R_R_N},
    {"SHR",       0x8000, FMT_R_R_N},
    {"LDM",       0x9000, FMT_R_R_N},
    {"STM",       0xA000, FMT_N_R_R},
    {"STJ",       0xB000, FMT_N_R_N},
    {"NIL",       0xC000, FMT_N_N_N},
    {"JLT",       0xC100, FMT_N_R_R},
    {"JEQ",       0xC200, FMT_N_R_R},
    {"JLE",       0xC300, FMT_N_R_R},
    {"JGT",       0xC400, FMT_N_R_R},
    {"JNE",       0xC500, FMT_N_R_R},
    {"JGE",       0xC600, FMT_N_R_R},
    {"JMP",       0xC700, FMT_N_N_N},
    {"JLT.U",     0xC800, FMT_N_R_R},
    {"JEQ.U",     0xC900, FMT_N_R_R},
    {"JLE.U",     0xCA00, FMT_N_R_R},
    {"JGT.U",     0xCB00, FMT_N_R_R},
    {"JNE.U",     0xCC00, FMT_N_R_R},
    {"JGE.U",     0xCD00, FMT_N_R_R},
    {"JGT.E",     0xCE00, FMT_N_R_R},
    {"JGT.UE",    0xCF00, FMT_N_R_R},
    {"CAL",       0xD000, FMT_N_R_N},
    {"RET",       0xE000, FMT_N_N_N},
    {"HLT",       0xF000, FMT_N_N_N},
    {NULL,        0x0000, FMT_UNKOWN}
};
/// <summary>
/// Uses a mnemonic to search the optable for it's opcode and format
/// </summary>
/// <param name="mnemonic"></param>
/// <returns></returns>
Opcode_entry* lookup_opcode(const char* mnemonic) {
    int i = 0;
    char base_mnemonic[128];
    strncpy_s(base_mnemonic, sizeof(base_mnemonic), mnemonic, sizeof(base_mnemonic) - 1);
    base_mnemonic[sizeof(base_mnemonic) - 1] = '\0';

    if (base_mnemonic[0] != 'J' && base_mnemonic[0] != 'j') {
        char* dot = strchr(base_mnemonic, '.');
        if (dot && (strcmp(dot, ".C") == 0 || strcmp(dot, ".SHORT") == 0)) {
            *dot = '\0';
        }
    }

    while (optable[i].mnemonic != NULL) {
        if (strcmp(optable[i].mnemonic, base_mnemonic) == 0) {
            return &optable[i];
        }
        i++;
    }
    return NULL;
}
/// <summary>
/// takes a token to see if it's a valid register 
/// </summary>
/// <param name="token"></param>
/// <returns>
/// register number, or -1 if not found
/// </returns>
int parse_register(const char* token) {
    if (!token || (token[0] != 'R' && token[0] != 'r')) return -1;
    int reg_num = token[1] - '0';
    if (reg_num >= 0 && reg_num <= 7 && token[2] == '\0') return reg_num;
    return -1;
}

/// <summary>
/// check if a bank switch needs to be implicitly inserted
/// </summary>
/// <param name="addr"></param>
/// <returns>
/// TRUE: needs a bank switch
/// FALSE: does not need a bank switch
/// </returns>
bool needs_bank(Address addr) {
    return addr.bank != 0;
}

// These mirror EXACTLY which operand compile_instruction_safe's FIELD2/FIELD3
// logic treats as the immediate-or-register slot for each instruction form.
// Bank-extension detection MUST use these instead of hardcoded per-form guesses,
// or it can silently disagree with the actual encoding.
const char* field2_slot(InstForm form, const char* op1, const char* op2, const char* op3) {
    (void)op3;
    if (form == FMT_N_R_N || form == FMT_N_R_R) return op1;
    if (form == FMT_R_R_R || form == FMT_R_R_N || form == FMT_R_N_R) return op2;
    return NULL;
}
const char* field3_slot(InstForm form, const char* op1, const char* op2, const char* op3) {
    (void)op1;
    if (form == FMT_N_R_R) return op2;
    if (form == FMT_R_R_R || form == FMT_R_N_R || form == FMT_R_R_N) return op3;
    return NULL;
}
static bool operand_needs_bank(const char* operand)
{
    if (!operand)
        return false;

    if (parse_register(operand) != -1)
        return false;

    Address addr = resolve_address(operand);

    return addr.bank != 0;
}
static bool instruction_needs_bank(
    Opcode_entry* op,
    const char* op1,
    const char* op2,
    const char* op3)
{
    if (!op)
        return false;

    const char* f2 = field2_slot(op->form, op1, op2, op3);
    const char* f3 = field3_slot(op->form, op1, op2, op3);

    if (f2 && parse_register(f2) == -1)
    {
        Address a = resolve_address(f2);

        if (a.bank != 0)
            return true;
    }

    if (f3 && parse_register(f3) == -1)
    {
        Address a = resolve_address(f3);

        if (a.bank != 0)
            return true;
    }

    return false;
}

/// <summary>
/// calculate how many additional words are required 
/// </summary>
/// <param name="op"></param>
/// <param name="o1"></param>
/// <param name="o2"></param>
/// <param name="o3"></param>
/// <returns>
/// int: No. of words 
/// </returns>
/// 
int check_immediate_bank_extension(
    Opcode_entry* op,
    const char* o1,
    const char* o2,
    const char* o3)
{
    int extra_words = 0;
    int bank_needed = 0;

    const char* f2 = field2_slot(op->form, o1, o2, o3);
    const char* f3 = field3_slot(op->form, o1, o2, o3);

    if (f2 && parse_register(f2) == -1)
    {
        Address addr = resolve_address(f2);

        if (addr.bank != 0)
            bank_needed = 1;
    }

    if (f3 && parse_register(f3) == -1)
    {
        Address addr = resolve_address(f3);

        if (addr.bank != 0)
            bank_needed = 1;
    }


    if (bank_needed)
    {
        extra_words += 2; // EAM.SET bank + immediate

        extra_words += 2; // EAM.SET reset + immediate
    }

    return extra_words;
}
/// <summary>
/// determines instruction size
/// </summary>
/// <param name="op"></param>
/// <param name="o1"></param>
/// <param name="o2"></param>
/// <param name="o3"></param>
/// <returns></returns>
int instruction_size(
    Opcode_entry* op,
    const char* o1,
    const char* o2,
    const char* o3)
{
    int words = 1; // opcode

    const char* f2 = field2_slot(op->form, o1, o2, o3);
    const char* f3 = field3_slot(op->form, o1, o2, o3);

    bool bank_needed = false;

    if (f2 && parse_register(f2) == -1) {
        words++;
        Address a = resolve_address(f2);
        if (a.bank != 0)
            bank_needed = true;
    }

    if (f3 && parse_register(f3) == -1) {
        words++;
        Address a = resolve_address(f3);
        if (a.bank != 0)
            bank_needed = true;
    }

    if (bank_needed)
        words += 4;

    return words;
}

/// <summary>
/// turns a parsed mnemonic and operands into a word in the output file
/// </summary>
/// <param name="op"></param>
/// <param name="op1"></param>
/// <param name="op2"></param>
/// <param name="op3"></param>
/// <param name="output_file"></param>
/// <param name="raw_mnemonic"></param>
/// 
void compile_instruction_safe(
    Opcode_entry* op,
    char* op1,
    char* op2,
    char* op3,
    FILE* output_file,
    const char* raw_mnemonic)
{
    unsigned short machine_word;
    unsigned short immediate_queue[2];
    int immediate_count;
    int defer_bank_reset;
    const char* target_op;
    int reg;
    Address addr;

    if (op == NULL || output_file == NULL)
        return;

    machine_word = op->base_opcode;
    immediate_count = 0;
    defer_bank_reset = 0;
    target_op = NULL;

    /*
     * ------------------------------------------------------------
     * Determine whether ANY immediate operand requires a bank.
     *
     * This MUST agree with calculate_instruction_layout().
     *
     * FIELD 2:
     *   N,R,N / N,R,R -> op1
     *   R,R,R / R,R,N / R,N,R -> op2
     *
     * FIELD 3:
     *   N,R,R -> op2
     *   R,R,R / R,R,N / R,N,R -> op3
     * ------------------------------------------------------------
     */

    const char* bank_operand = NULL;

    const char* field2 = field2_slot(
        op->form,
        op1,
        op2,
        op3
    );

    const char* field3 = field3_slot(
        op->form,
        op1,
        op2,
        op3
    );

    /*
     * Find the first banked immediate operand.
     */
    if (field2 &&
        parse_register(field2) == -1)
    {
        addr = resolve_address(field2);

        if (addr.bank != 0)
            bank_operand = field2;
    }

    if (field3 &&
        parse_register(field3) == -1)
    {
        addr = resolve_address(field3);

        if (addr.bank != 0)
        {
            if (bank_operand == NULL)
            {
                bank_operand = field3;
            }
            else
            {
                /*
                 * Both immediate operands are banked.
                 *
                 * EAM can only hold one active bank, so they must
                 * resolve to the same bank.
                 */
                Address addr2 = resolve_address(field3);
                Address addr1 = resolve_address(bank_operand);

                if (addr1.bank != addr2.bank)
                {
                    fprintf(
                        stderr,
                        "ERROR: instruction '%s' has immediate operands "
                        "from different banks (%04X and %04X).\n",
                        raw_mnemonic ? raw_mnemonic : op->mnemonic,
                        addr1.bank,
                        addr2.bank
                    );

                    exit(EXIT_FAILURE);
                }
            }
        }
    }

    /*
     * ------------------------------------------------------------
     * BANK PREFIX
     *
     * EAM.SET bank
     * ------------------------------------------------------------
     */

    if (bank_operand != NULL)
    {
        Opcode_entry* eam_op;
        char bank_string[32];

        addr = resolve_address(bank_operand);

        eam_op = lookup_opcode("EAM.SET");

        if (eam_op == NULL)
        {
            fprintf(stderr,
                "ERROR: EAM.SET opcode not found.\n");

            exit(EXIT_FAILURE);
        }

        sprintf(
            bank_string,
            "0x%04X",
            addr.bank
        );

        compile_instruction_safe(
            eam_op,
            bank_string,
            NULL,
            NULL,
            output_file,
            "EAM.SET"
        );

        /*
         * The bank must be reset after the main instruction.
         */
        defer_bank_reset = 1;
    }

    /*
     * ------------------------------------------------------------
     * M FLAG
     * ------------------------------------------------------------
     */

    if (raw_mnemonic != NULL)
    {
        if (strstr(raw_mnemonic, ".C") != NULL ||
            strstr(raw_mnemonic, ".SHORT") != NULL)
        {
            machine_word |= MASK_M_FLAG;
        }
    }

    /*
     * ------------------------------------------------------------
     * FIELD 1: destination register
     * ------------------------------------------------------------
     */

    if (op->form == FMT_R_R_R ||
        op->form == FMT_R_R_N ||
        op->form == FMT_R_N_R)
    {
        if (op1 != NULL)
        {
            reg = parse_register(op1);

            if (reg != -1)
            {
                machine_word |=
                    (unsigned short)(reg << SHIFT_REG_D);
            }
        }
    }

    /*
     * ------------------------------------------------------------
     * FIELD 2
     * ------------------------------------------------------------
     */

    target_op = field2;

    if (target_op != NULL)
    {
        reg = parse_register(target_op);

        if (reg != -1)
        {
            machine_word |=
                (unsigned short)(reg << SHIFT_REG_X);
        }
        else
        {
            machine_word |= MASK_LX;

            immediate_queue[immediate_count] =
                resolve_operand_with_bank(
                    target_op,
                    output_file,
                    &defer_bank_reset
                );

            immediate_count++;
        }
    }

    /*
     * ------------------------------------------------------------
     * FIELD 3
     * ------------------------------------------------------------
     */

    target_op = field3;

    if (target_op != NULL)
    {
        reg = parse_register(target_op);

        if (reg != -1)
        {
            machine_word |=
                (unsigned short)(reg & MASK_REG_Y);
        }
        else
        {
            machine_word |= MASK_LY;

            immediate_queue[immediate_count] =
                resolve_operand_with_bank(
                    target_op,
                    output_file,
                    &defer_bank_reset
                );

            immediate_count++;
        }
    }

    /*
     * ------------------------------------------------------------
     * WRITE MAIN OPCODE
     * ------------------------------------------------------------
     */

    fprintf(
        output_file,
        "%04X\n",
        machine_word
    );

    printf(
        "ACTUAL EMIT: %04X | %s | opcode\n",
        actual_output_words,
        raw_mnemonic
    );

    actual_output_words++;

    /*
     * ------------------------------------------------------------
     * WRITE IMMEDIATE WORDS
     * ------------------------------------------------------------
     */

    for (int i = 0; i < immediate_count; i++)
    {
        printf(
            "ACTUAL EMIT: %04X | %s | immediate = %04X\n",
            actual_output_words,
            raw_mnemonic,
            immediate_queue[i]
        );

        fprintf(
            output_file,
            "%04X\n",
            immediate_queue[i]
        );

        actual_output_words++;
    }

    /*
     * ------------------------------------------------------------
     * BANK RESET
     *
     * EAM.SET 0
     * ------------------------------------------------------------
     */

    if (defer_bank_reset)
    {
        Opcode_entry* eam_op =
            lookup_opcode("EAM.SET");

        compile_instruction_safe(
            eam_op,
            "0x0000",
            NULL,
            NULL,
            output_file,
            "EAM.SET"
        );
    }
}

    
/// <summary>
/// a more advanced resolve_operand, taking into account the bank
/// </summary>
/// <param name="operand"></param>
/// <param name="output_file"></param>
/// <param name="defer_bank_reset"></param>
/// <returns> unsigned short: offset </returns>

unsigned short resolve_operand_with_bank(
    const char* operand,
    FILE* output_file,
    int* defer_bank_reset)
{
    (void)output_file;

    Address addr = resolve_address(operand);

    if (addr.bank != 0)
    {
        if (defer_bank_reset != NULL)
            *defer_bank_reset = 1;
    }

    return addr.offset;
}
/// <summary>
/// deprecated high-level syntax. use at your own risk
/// </summary>
/// <param name="line_buffer"></param>
/// <param name="output_file"></param>
/// <returns>1: success 0:fail </returns>
int process_high_level_compile(const char* line_buffer, FILE* output_file) {
    char left_side[64] = { 0 };
    char right_side[128] = { 0 };

    if (strncmp(line_buffer, "print ", 6) == 0) {
        char ch;
        if (sscanf(line_buffer, "print '%c'", &ch) == 1) {
            Opcode_entry* stm_op = lookup_opcode("STM");
            Opcode_entry* eam_op = lookup_opcode("EAM.SET");
            compile_instruction_safe(eam_op, "0x07FF", NULL, NULL, output_file, "EAM.SET");
            char addr_str[16], val_str[16];
            sprintf(addr_str, "0xFFFF");
            sprintf(val_str, "%d", ch);

            compile_instruction_safe(stm_op, "R0", addr_str, val_str, output_file, "STM.C");
            compile_instruction_safe(eam_op, "0x0000", NULL, NULL, output_file, "EAM.SET");
            return 1;
        }
    }

    if (strchr(line_buffer, '=')) {
        if (sscanf(line_buffer, "%[^=]=%[^\n]", left_side, right_side) == 2) {
            char var_d[64]; sscanf(left_side, "%s", var_d);
            char arg1[64] = { 0 }, op_sign[8] = { 0 }, arg2[64] = { 0 };

            if (sscanf(right_side, "%s %s %s", arg1, op_sign, arg2) == 3) {
                Opcode_entry* op = NULL;
                if (strcmp(op_sign, "+") == 0)      op = lookup_opcode("ADD");
                else if (strcmp(op_sign, "-") == 0) op = lookup_opcode("SUB");
                else if (strcmp(op_sign, "&") == 0) op = lookup_opcode("AND");
                else if (strcmp(op_sign, "|") == 0) op = lookup_opcode("OR");
                else if (strcmp(op_sign, "^") == 0) op = lookup_opcode("XOR");

                if (op) {
                    compile_instruction_safe(op, var_d, arg1, arg2, output_file, op->mnemonic);
                    return 1;
                }
            }
            else if (sscanf(right_side, "%s", arg1) == 1) {
                Opcode_entry* sub_op = lookup_opcode("SUB");
                Opcode_entry* add_op = lookup_opcode("ADD");

                compile_instruction_safe(sub_op, var_d, var_d, var_d, output_file, "SUB");
                compile_instruction_safe(add_op, var_d, var_d, arg1, output_file, "ADD");
                return 1;
            }
        }
    }
    return 0;
}
/// <summary>
/// handles the syntactic sugar of memory operands. 
/// </summary>
/// <param name="operand"></param>
void normalize_memory_sugar(char* operand) {
    if (!operand) return;

    // Match M$[R1] style
    if (strncmp(operand, "M$[", 3) == 0) {
        size_t len = strlen(operand);
        if (len >= 5 && operand[len - 1] == ']') {
            // Extract inside: R1
            memmove(operand, operand + 3, len - 3); // "R1]"
            operand[len - 4] = '\0';                // "R1"
        }
    }
}
/// <summary>
/// turn a .include into a component of the assembled file. 
/// </summary>
/// <param name="input"></param>
/// <param name="output"></param>
/// <param name="path"></param>
void expand_includes(FILE* input, FILE* output, const char* path) {
    char line[256];

    if (already_included(path)) {
        fprintf(stderr, "Error: Includes may not include themselves! '%s'.\n", path);
#ifdef _WIN32
        Sleep(5000);
#else
        sleep(5);
#endif
        exit(1);
    }
    if (include_depth >= MAX_INCLUDE_DEPTH) {
        fprintf(stderr, "Error: Maximum include depth (%d) exceeded at '%s'.\n", MAX_INCLUDE_DEPTH, path);
#ifdef _WIN32
        Sleep(5000);
#else
        sleep(5);
#endif
        exit(1);
    }

    strncpy(include_stack[include_depth].path, path, PATH_MAX - 1);

    include_stack[include_depth].path[PATH_MAX - 1] = '\0';
    include_depth++;

    while (fgets(line, sizeof(line), input)) {
        char* cursor = line;
        while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r' || *cursor == '\n') cursor++;
        if (strncmp(cursor, ".include", 8) == 0) {
            char include_file[256];
            if (sscanf(cursor, ".include \"%255[^\"]\"", include_file) == 1) {
                FILE* inc_file = fopen(include_file, "r");
                if (inc_file) {
                    expand_includes(inc_file, output, include_file);
                    printf("Include success! \n");
                    fclose(inc_file);
                }
                else {
                    fprintf(stderr, "Error: Could not open include file '%s'.\n", include_file);
#ifdef _WIN32
                    Sleep(5000);
#else
                    sleep(5);
#endif 
                    exit(1);
                }
            }
        }
        else {
            fputs(line, output);
        }
    }

}
/// <summary>
/// resolves labels 
/// </summary>
/// <param name="name"></param>
/// <param name="address"></param>
void add_label(const char* name, Address address)
{
    if (label_count >= label_capacity)
    {
        size_t new_capacity =
            label_capacity == 0 ? 64 : label_capacity * 2;


        Label* new_table =
            realloc(label_table,
                new_capacity * sizeof(Label));


        if (!new_table)
        {
            fprintf(stderr,
                "Out of memory adding label\n");
            exit(1);
        }


        label_table = new_table;
        label_capacity = new_capacity;
    }


    strncpy_s(label_table[label_count].name, sizeof(label_table[label_count].name), name, sizeof(label_table[label_count].name) - 1);


    label_table[label_count]
        .name[sizeof(label_table[label_count].name) - 1] = '\0';


    label_table[label_count].address = address;


    label_count++;
}


static InstructionLayout calculate_instruction_layout(
    Opcode_entry* op,
    const char* op1,
    const char* op2,
    const char* op3)
{
    InstructionLayout layout = { 0 };

    if (!op)
        return layout;

    /*
     * Main instruction itself.
     */
    layout.main_words = 1;

    /*
     * FIELD 2.
     */
    const char* f2 =
        field2_slot(op->form, op1, op2, op3);

    /*
     * FIELD 3.
     */
    const char* f3 =
        field3_slot(op->form, op1, op2, op3);

    /*
     * Count immediate payload words.
     */
    if (f2 && parse_register(f2) == -1)
        layout.immediate_words++;

    if (f3 && parse_register(f3) == -1)
        layout.immediate_words++;

    /*
     * Determine whether a bank prefix/reset is required.
     */
    bool bank_needed = false;
    unsigned short bank = 0;

    if (f2 && parse_register(f2) == -1)
    {
        Address a = resolve_address(f2);

        if (a.bank != 0)
        {
            bank_needed = true;
            bank = a.bank;
        }
    }

    if (f3 && parse_register(f3) == -1)
    {
        Address a = resolve_address(f3);

        if (a.bank != 0)
        {
            if (bank_needed && bank != a.bank)
            {
                fprintf(
                    stderr,
                    "ERROR: instruction %s uses different banks "
                    "(%04X and %04X).\n",
                    op->mnemonic,
                    bank,
                    a.bank
                );

                exit(EXIT_FAILURE);
            }

            bank_needed = true;
            bank = a.bank;
        }
    }

    /*
     * EAM.SET bank = 2 words
     * EAM.SET 0    = 2 words
     */
    if (bank_needed)
    {
        layout.bank_prefix_words = 2;
        layout.bank_reset_words = 2;
    }

    layout.words =
        layout.bank_prefix_words +
        layout.main_words +
        layout.immediate_words +
        layout.bank_reset_words;

    return layout;
}


/// <summary>
/// main
/// </summary>
/// <returns></returns>
int main()
{
    char file[256];
    char output_filename[256];

    printf("Enter path to input source file: ");
    if (scanf("%255s", file) != 1) return 1;

    printf("Enter name for the output hex file: ");
    if (scanf("%255s", output_filename) != 1) return 1;

    // =========================================================================
    // PASS 1: ADDRESS TRACKING SETUP
    // =========================================================================

    FILE* source_file = fopen(file, "r");
    if (!source_file) {
        fprintf(stderr, "Error: Could not open source file '%s'.\n", file);
#ifdef _WIN32
        Sleep(5000);
#else
        sleep(5);
#endif
        return 1;
    }
    FILE* expanded_file = tmpfile();
    if (!expanded_file) {
        fprintf(stderr, "Error: Could not create temporary file for includes.\n");
#ifdef _WIN32
        Sleep(5000);
#else
        sleep(5);
#endif
        fclose(source_file);
        return 1;
    }

    expand_includes(source_file, expanded_file, file);

    fclose(source_file);
    rewind(expanded_file);
    source_file = expanded_file;
    char line[256];
    current_address.bank = 0;
    current_address.offset = 0;

    int stj_pending = 0;
    int stj_pending_line = 0;
    char stj_pending_text[256] = { 0 };
    int line_number = 0;

    while (fgets(line, sizeof(line), source_file)) {

        line_number++;
        char* cursor = line;
        while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r' || *cursor == '\n') cursor++;
        cursor[strcspn(cursor, "\r\n")] = 0;
        char* comment = strchr(cursor, ';');
        if (comment)
            *comment = '\0';
        // Trim trailing whitespace left over after comment-stripping (or
        // present in the original line) - without this, a label like
        // "start: " (trailing space) would be missed by the strict
        // "colon is the last character" check below, while Pass 2 (which
        // does not require this) would still treat it as a label - a
        // direct Pass1/Pass2 disagreement that corrupts every address
        // after any such line.
        {
            size_t len = strlen(cursor);
            while (len > 0 && (cursor[len - 1] == ' ' || cursor[len - 1] == '\t')) {
                cursor[len - 1] = '\0';
                len--;
            }
        }
        if (strlen(cursor) == 0 || cursor[0] == ';' || cursor[0] == '#') continue;
        char* colon = strchr(cursor, ':');

        if (colon && colon[1] == '\0') {
            char func_name[64];
            sscanf(cursor, "%[^:]", func_name);
            add_label(func_name, current_address);
            if (stj_pending) {
                fprintf(stderr,
                    "Warning: label at line %d follows 'STJ' at line %d (\"%s\") with no intervening conditional jump.\n"
                    "         The stored branch target may be dangling or unintentionally reused.\n",
                    line_number, stj_pending_line, stj_pending_text);
            }
            continue;
        }
        printf("Pass 1 line %d, address = %04x:%04x -> %s\n", line_number, current_address.bank, current_address.offset, line);
        int instruction_words = 0;
        if (strncmp(cursor, "HEX ", 4) == 0) {
            int words = 1;
            for (char* p = cursor + 4; *p; p++) {
                if (*p == ',')
                    words++;
            }

            advance_address(words);
            continue;
        }
        else if (strncmp(cursor, "call ", 5) == 0) {
            if (stj_pending) {
                fprintf(stderr,
                    "Warning: 'call' at line %d intervenes before the 'STJ' at line %d (\"%s\") is consumed by a conditional jump.\n"
                    "         The stored branch target may be clobbered by the callee.\n",
                    line_number, stj_pending_line, stj_pending_text);
            }
            instruction_words = 2;
            advance_address(instruction_words);
            continue;
        }
        else if (strncmp(cursor, "define ", 7) == 0)
        {
            char name[64];
            char value_string[64];

            if (sscanf(cursor, "define %63s %63s", name, value_string) == 2)
            {
                unsigned int value = strtoul(value_string, NULL, 0);
                add_constant(name, value);
            }

            continue;
        }
        else if (strncmp(cursor, "HEX ", 4) == 0)
        {
            int words = 1;

            for (char* p = cursor + 4; *p; p++)
            {
                if (*p == ',')
                    words++;
            }

            advance_address(words);
            continue;
        }
        else if (strncmp(cursor, "print", 5) == 0) {
            instruction_words = 6;
            advance_address(instruction_words);
            continue;
        }
        else if (strchr(cursor, '=') != NULL) {
            instruction_words = 1;
            char left_side[128] = { 0 }, right_side[128] = { 0 };

            if (sscanf(cursor, "%[^=]=%[^\n]", left_side, right_side) == 2) {
                char arg1[64] = { 0 }, op_sign[8] = { 0 }, arg2[64] = { 0 };
                int items = sscanf(right_side, "%s %s %s", arg1, op_sign, arg2);

                if (items == 3) {
                    if (parse_register(arg1) == -1) {
                        instruction_words++;
                        // Check for Bank 1+ / Long Address expansion on arg1
                        Address addr1 = resolve_address(arg1);
                        if (addr1.bank != 0) instruction_words += 4;
                    }
                    if (parse_register(arg2) == -1) {
                        instruction_words++;
                        // Check for Bank 1+ / Long Address expansion on arg2
                        Address addr2 = resolve_address(arg2);
                        if (addr2.bank != 0) instruction_words += 4;
                    }
                }
                else if (items == 1) {
                    instruction_words = 2;
                    if (parse_register(arg1) == -1) {
                        instruction_words++;
                        // Check for Bank 1+ / Long Address expansion on arg1
                        Address addr1 = resolve_address(arg1);
                        if (addr1.bank != 0) instruction_words += 4;
                    }
                }
            }
            advance_address(instruction_words);
            continue;
        }
        else {
            instruction_words = 1;
            char temp[256]; strcpy_s(temp, 256, cursor);
            char* mnemonic = strtok(temp, " ,\t");
            char* o1 = strtok(NULL, " ,\t");
            char* o2 = strtok(NULL, " ,\t");
            char* o3 = strtok(NULL, " ,\t");
            normalize_memory_sugar(o1);
            normalize_memory_sugar(o2);
            normalize_memory_sugar(o3);

            if (mnemonic) {
                // Strip trailing newline for clean warning text / mnemonic comparisons
                char clean_line[256];
                // printf("PASS2: %s\n", cursor);
                strncpy_s(clean_line, sizeof(clean_line), cursor, sizeof(clean_line) - 1);
                clean_line[sizeof(clean_line) - 1] = '\0';
                clean_line[strcspn(clean_line, "\r\n")] = '\0';

                if (strcmp(mnemonic, "STJ") == 0) {
                    if (stj_pending) {
                        fprintf(stderr,
                            "Warning: 'STJ' at line %d overwrites a still-pending 'STJ' from line %d (\"%s\") that was never consumed by a conditional jump.\n",
                            line_number, stj_pending_line, stj_pending_text);
                    }
                    stj_pending = 1;
                    stj_pending_line = line_number;
                    strncpy_s(stj_pending_text, sizeof(stj_pending_text), clean_line, sizeof(stj_pending_text) - 1);
                    stj_pending_text[sizeof(stj_pending_text) - 1] = '\0';
                }
                else if (mnemonic[0] == 'J') {
                    // Any conditional/unconditional jump (JLT, JEQ, ..., JMP, and .U/.E/.UE variants)
                    // consumes the pending stored branch target.
                    stj_pending = 0;
                }
                else if (strcmp(mnemonic, "RET") == 0 || strcmp(mnemonic, "HLT") == 0) {
                    if (stj_pending) {
                        fprintf(stderr,
                            "Warning: '%s' at line %d follows 'STJ' at line %d (\"%s\") with no intervening conditional jump.\n"
                            "         The stored branch target is being abandoned.\n",
                            mnemonic, line_number, stj_pending_line, stj_pending_text);
                    }
                }
            }

            Opcode_entry* op = lookup_opcode(mnemonic);
            if (op)
            {
                InstructionLayout layout =
                    calculate_instruction_layout(
                        op,
                        o1,
                        o2,
                        o3);

                instruction_words = layout.words;
            }
        }
        advance_address(instruction_words);
    }
    // NOTE: do NOT fclose(source_file) here - source_file == expanded_file,
    // and it's needed again for Pass 2. Just rewind it below.
    printf("Starting Pass 2\n");
    actual_output_words = 0;
    // =========================================================================
    // PASS 2: GENERATE MACHINE HEX CODES
    // =========================================================================
    current_address.bank = 0;
    current_address.offset = 0;
    rewind(expanded_file);
    source_file = expanded_file;
    FILE* output_file = fopen(output_filename, "w");
    if (!output_file) {
        fclose(expanded_file);
        return 1;
    }
    int line_no = 1;
    while (fgets(line, sizeof(line), source_file)) {
       // printf(" Pass 2, line %d: %s", line_no, line);
        line_no++;
        char* cursor = line;
        while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r' || *cursor == '\n') cursor++;
        cursor[strcspn(cursor, "\r\n")] = 0;
        char* comment = strchr(cursor, ';');
        if (comment)
            *comment = '\0';
        {
            size_t len = strlen(cursor);
            while (len > 0 && (cursor[len - 1] == ' ' || cursor[len - 1] == '\t')) {
                cursor[len - 1] = '\0';
                len--;
            }
        }
        if (strlen(cursor) == 0 || cursor[0] == ';' || cursor[0] == '#') continue;
        {
            char* colon2 = strchr(cursor, ':');
            if (colon2 && colon2[1] == '\0') continue;
        }
        if (strncmp(cursor, "HEX ", 4) == 0) {
            char buffer[256];
            strcpy_s(buffer, 256, cursor + 4);

            char* token = strtok(buffer, ", ");

            while (token) {
                fprintf(output_file, "%04X\n",
                    (unsigned short)strtoul(token, NULL, 16));

                token = strtok(NULL, ", ");
            }

            continue;
        }

        if (strncmp(cursor, "call ", 5) == 0) {
            char target_func[64];
            if (sscanf(cursor, "call %s", target_func) == 1) {
                unsigned int target_address = 0xFFFFFFFF;
                for (size_t i = 0; i < label_count; i++) {
                    if (strcmp(label_table[i].name, target_func) == 0) {
                        target_address = address_to_u32(label_table[i].address);;
                        break;
                    }
                }
                if (target_address != 0xFFFFFFFF) {
                    char addr_str[32]; sprintf(addr_str, "0x%08X", target_address);
                    Opcode_entry* cal_op = lookup_opcode("CAL");
                    compile_instruction_safe(cal_op, addr_str, NULL, NULL, output_file, "CAL");
                    continue;
                }
            }
        }
        if (strchr(cursor, '=')) {
            if (process_high_level_compile(cursor, output_file)) continue;
        }
        if (strncmp(cursor, "print", 5) == 0) {
            if (process_high_level_compile(cursor, output_file)) continue;
        }

        char tokenize_buffer[256];
        strcpy_s(tokenize_buffer,sizeof(tokenize_buffer), cursor);
        char* mnemonic = strtok(tokenize_buffer, " ,\t");
        if (!mnemonic) continue;

        Opcode_entry* op = lookup_opcode(mnemonic);
        if (!op) continue;

        char* op1 = strtok(NULL, " ,\t");
        char* op2 = strtok(NULL, " ,\t");
        char* op3 = strtok(NULL, " ,\t");
        normalize_memory_sugar(op1);
        normalize_memory_sugar(op2);
        normalize_memory_sugar(op3);
        unsigned int start_output_words = actual_output_words;

        InstructionLayout expected =
            calculate_instruction_layout(op, op1, op2, op3);

      /*  printf(
            "\nADDRESS CHECK: %s\n"
            "  tracked = %04X:%04X\n"
            "  actual output words = %04X\n"
            "  expected words = %d\n",
            mnemonic,
            current_address.bank,
            current_address.offset,
            actual_output_words,
            expected.words
        ); */

        compile_instruction_safe(
            op,
            op1,
            op2,
            op3,
            output_file,
            mnemonic);

        unsigned int emitted =
            actual_output_words - start_output_words;

        printf(
            "  actual after = %04X\n"
            "  emitted = %u\n",
            actual_output_words,
            emitted
        );

        if (emitted != (unsigned int)expected.words)
        {
            fprintf(stderr,
                "\n!!! EMISSION SIZE DIVERGENCE !!!\n"//
                "Line     : %d\n"
                "Address  : %04X:%04X\n"
                "Mnemonic : %s\n"
                "Expected : %d words\n"
                "Actual   : %u words\n"
                "Source   : %s\n",
                line_no,
                current_address.bank,
                current_address.offset,
                mnemonic,
                expected.words,
                emitted,
                cursor);

            assert(emitted == (unsigned int)expected.words);
        }
        
        if (expected.words <= 0)
        {
            fprintf(stderr,
                "\n*** INVALID INSTRUCTION SIZE ***\n"
                "Instruction : %s\n"
                "Address     : %04X:%04X\n"
                "Expected    : %d words\n",
                mnemonic,
                current_address.bank,
                current_address.offset,
                expected.words);

            exit(EXIT_FAILURE);
        }


        

       
        advance_address(expected.words);
    }
    printf("\n========================================\n");
    printf("PASS 2 ACTUAL WORDS: 0x%04X (%u)\n",
        actual_output_words,
        actual_output_words);

    printf("PASS 2 TRACKED ADDRESS: %04X:%04X\n",
        current_address.bank,
        current_address.offset);

    printf("========================================\n");
    fclose(expanded_file); // source_file == expanded_file here; closing once is sufficient
    fclose(output_file);
    printf("\nSuccess! Saved to '%s'\n", output_filename);
    printf("The resolved addresses of labels may be useful, so here they are:\n");
    for (size_t i = 0; i < label_count; i++)
    {
        printf("%s is at %04x:%04x\n", label_table[i].name, label_table[i].address.bank, label_table[i].address.offset);
    }
    printf("Type 'exit' then press the 'enter' or 'return' key to exit\n");
    char waitForClose[64];
    scanf("%s", waitForClose);
    return 0;
}
