#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <stdbool.h>
#ifdef _WIN32
#include<windows.h>
#endif
#ifdef linux 
#include<unistd.h>
#endif
#define SHIFT_OPCODE  12
#define SHIFT_M_FLAG  11
#define SHIFT_REG_D      8
#define MASK_LX       (1 << 7)
#define SHIFT_REG_X     4
#define MASK_LY       (1 << 3)
#define MASK_REG_Y     0x0007
#define BANK_SIZE 0x10000

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#define MAX_INCLUDE_DEPTH 64
typedef enum {
    TOKEN_MNEMONIC,
    TOKEN_REGISTER,
    TOKEN_IMMEDIATE,
    TOKEN_COMMA,
    TOKEN_NEWLINE,
    TOKEN_EOF
} ATokenType;

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
    char path[PATH_MAX];
} IncludeEntry;

IncludeEntry include_stack[MAX_INCLUDE_DEPTH];
int include_depth = 0;
int already_included(const char* file)
{
    for (int i = 0; i < include_depth; i++)
    {
        if (strcmp(include_stack[i].path, file) == 0)
            return 1;
    }

    return 0;
}
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

Label* label_table = NULL;
size_t label_capacity = 0;
size_t label_count = 0;
Address current_address = { 0, 0 };
typedef struct {
    const char* mnemonic;
    unsigned short base_opcode;
    InstForm form;
} Opcode_entry;
void advance_address(unsigned int words)
{
    unsigned int full = current_address.offset + words;

    current_address.bank += full >> 16;
    current_address.offset = full & 0xFFFF;
}


unsigned int address_to_u32(Address addr)
{
    return ((unsigned int)addr.bank << 16) |
        addr.offset;
}
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

Opcode_entry* lookup_opcode(const char* mnemonic) {
    int i = 0;
    char base_mnemonic[128];
    strncpy(base_mnemonic, mnemonic, sizeof(base_mnemonic) - 1);
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

int parse_register(const char* token) {
    if (!token || (token[0] != 'R' && token[0] != 'r')) return -1;
    int reg_num = token[1] - '0';
    if (reg_num >= 0 && reg_num <= 7 && token[2] == '\0') return reg_num;
    return -1;
}

Address resolve_address(const char* token)
{
    Address empty = { 0,0 };

    if (!token || strlen(token) == 0)
        return empty;

    for (size_t i = 0; i < label_count; i++)
    {
        if (strcmp(label_table[i].name, token) == 0)
            return label_table[i].address;
    }


    unsigned int value = strtoul(token, NULL, 0);

    Address result;
    result.bank = (value >> 16) & 0xFFFF;
    result.offset = value & 0xFFFF;

    return result;
}
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

int check_immediate_bank_extension(Opcode_entry* op, const char* o1, const char* o2, const char* o3) {
    const char* f2 = field2_slot(op->form, o1, o2, o3);
    const char* f3 = field3_slot(op->form, o1, o2, o3);
    const char* target_check = NULL;

    if (f2 && (strncmp(f2, "0x", 2) == 0 || strncmp(f2, "0X", 2) == 0)) target_check = f2;
    else if (f3 && (strncmp(f3, "0x", 2) == 0 || strncmp(f3, "0X", 2) == 0)) target_check = f3;

    if (target_check) {
        unsigned long full_addr = strtoul(target_check, NULL, 16);
        Address candidate;
        candidate.bank = (full_addr >> 16) & 0x7FF;
        candidate.offset = full_addr & 0xFFFF;
        if (needs_bank(candidate)) return 2;
    }
    return 0;
}

void compile_instruction_safe(Opcode_entry* op, char* op1, char* op2, char* op3, FILE* output_file, const char* raw_mnemonic) {
    unsigned short machine_word = op->base_opcode;
    unsigned short immediate_queue[2] = { 0 };
    int immediate_count = 0;
    char clean_op_buffer[64];
    int defer_bank_reset = 0;

    {
        const char* f2 = field2_slot(op->form, op1, op2, op3);
        const char* f3 = field3_slot(op->form, op1, op2, op3);
        char* target_check = NULL;

        if (f2 && (strncmp(f2, "0x", 2) == 0 || strncmp(f2, "0X", 2) == 0)) target_check = (char*)f2;
        else if (f3 && (strncmp(f3, "0x", 2) == 0 || strncmp(f3, "0X", 2) == 0)) target_check = (char*)f3;

        if (target_check) {
            unsigned long full_addr = strtoul(target_check, NULL, 16);

            if (full_addr > 0xFFFF) {
                unsigned short target_bank = (unsigned short)((full_addr >> 16) & 0x7FF);

                Opcode_entry* eam_op = lookup_opcode("EAM.SET");
                char bank_str[16];
                sprintf(bank_str, "0x%04X", target_bank);
                compile_instruction_safe(eam_op, bank_str, NULL, NULL, output_file, "EAM.SET");

                sprintf(clean_op_buffer, "0x%04X", (unsigned short)(full_addr & 0xFFFF));
                // target_check is a direct alias of whichever of op1/op2/op3 matched
                // (field2_slot/field3_slot return the pointer itself, not a copy),
                // so identity comparison tells us which one to rewrite.
                if (target_check == op1) op1 = clean_op_buffer;
                else if (target_check == op2) op2 = clean_op_buffer;
                else if (target_check == op3) op3 = clean_op_buffer;

                defer_bank_reset = 1;
            }
        }
    }

    if (strstr(raw_mnemonic, ".C") != NULL || strstr(raw_mnemonic, ".SHORT") != NULL) {
        machine_word |= (1 << SHIFT_M_FLAG);
    }

    // --- FIELD 1: REG_D (Bits 8-10) ---
    if (op->form == FMT_R_R_R || op->form == FMT_R_R_N || op->form == FMT_R_N_R) {
        if (op1 && strlen(op1) > 0) {
            int reg_d = parse_register(op1);
            if (reg_d != -1) {
                machine_word |= (reg_d << SHIFT_REG_D);
            }
        }
    }

    // --- FIELD 2: REG_X / Immediate (Bits 4-6) ---
    if (op->form == FMT_R_R_R || op->form == FMT_R_R_N || op->form == FMT_N_R_R || op->form == FMT_N_R_N || op->form == FMT_R_N_R) {
        char* target_op = (op->form == FMT_N_R_N || op->form == FMT_N_R_R) ? op1 : op2;
        if (target_op && strlen(target_op) > 0) {
            int reg_x = parse_register(target_op);
            if (reg_x == -1) {
                machine_word |= MASK_LX;
                immediate_queue[immediate_count++] = resolve_address(target_op).offset;
            }
            else {
                machine_word |= (reg_x << SHIFT_REG_X);
            }
        }
    }

    // --- FIELD 3: REG_Y / Immediate (Bits 0-2) ---
    if (op->form == FMT_R_R_R || op->form == FMT_R_N_R || op->form == FMT_N_R_R || op->form == FMT_R_R_N) {
        char* target_op3 = (op->form == FMT_N_R_R) ? op2 : op3;
        if (target_op3 && strlen(target_op3) > 0) {
            int reg_y = parse_register(target_op3);
            if (reg_y == -1) {
                machine_word |= MASK_LY;
                immediate_queue[immediate_count++] = resolve_address(target_op3).offset;
            }
            else {
                machine_word |= (reg_y & MASK_REG_Y);
            }
        }
    }

    fprintf(output_file, "%04X\n", machine_word);
    for (int i = 0; i < immediate_count; i++) {
        fprintf(output_file, "%04X\n", immediate_queue[i]);
    }

    if (defer_bank_reset) {
        Opcode_entry* eam_op = lookup_opcode("EAM.SET");
        compile_instruction_safe(eam_op, "0x0000", NULL, NULL, output_file, "EAM.SET");
    }
}

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


    strncpy(label_table[label_count].name,
        name,
        sizeof(label_table[label_count].name) - 1);


    label_table[label_count]
        .name[sizeof(label_table[label_count].name) - 1] = '\0';


    label_table[label_count].address = address;


    label_count++;
}
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

        int instruction_words = 0;
        if (strncmp(cursor, "HEX ", 4) == 0) {
            int words = 1;
            for (char* p = cursor + 4; *p; p++) {
                if (*p == ',')
                    words++;
            }

            advance_address(words);
            continue;
        }else if (strncmp(cursor, "call ", 5) == 0) {
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
                    if (parse_register(arg1) == -1) instruction_words++;
                    if (parse_register(arg2) == -1) instruction_words++;
                }
                else if (items == 1) {
                    instruction_words = 2; // SUB var_d,var_d,var_d (1 word, all regs) + ADD base word
                    if (parse_register(arg1) == -1) instruction_words++; // ADD's immediate operand
                }
            }
            advance_address(instruction_words);
            continue;
        }
        else {
            instruction_words = 1;
            char temp[256]; strcpy(temp, cursor);
            char* mnemonic = strtok(temp, " ,\t");
            char* o1 = strtok(NULL, " ,\t");
            char* o2 = strtok(NULL, " ,\t");
            char* o3 = strtok(NULL, " ,\t");

            if (mnemonic) {
                // Strip trailing newline for clean warning text / mnemonic comparisons
                char clean_line[256];
             
                strncpy(clean_line, cursor, sizeof(clean_line) - 1);
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
                    strncpy(stj_pending_text, clean_line, sizeof(stj_pending_text) - 1);
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
            if (op) {
                instruction_words += check_immediate_bank_extension(op, o1, o2, o3);

                if (op->form == FMT_R_R_R) {
                    if (o2 && parse_register(o2) == -1) instruction_words++;
                    if (o3 && parse_register(o3) == -1) instruction_words++;
                }
                else if (op->form == FMT_R_R_N) {
                    if (o2 && parse_register(o2) == -1) instruction_words++;
                    if (o3 && parse_register(o3) == -1) instruction_words++;
                }
                else if (op->form == FMT_R_N_R) {
                    if (o2 && parse_register(o2) == -1) instruction_words++;
                }
                else if (op->form == FMT_N_R_N) {
                    if (o1 && parse_register(o1) == -1) instruction_words++;
                    //if (o3 && parse_register(o3) == -1) instruction_words++;
                }
                else if (op->form == FMT_N_R_R) {
                    if (o1 && parse_register(o1) == -1) instruction_words++;
                    if (o2 && parse_register(o2) == -1) instruction_words++;
                }
            }
        }
        advance_address(instruction_words);
    }
    // NOTE: do NOT fclose(source_file) here - source_file == expanded_file,
    // and it's needed again for Pass 2. Just rewind it below.
    printf("Finished Pass 1\n");
    printf("Labels found: %zu\n", label_count);
    printf("Starting Pass 2\n");
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

    while (fgets(line, sizeof(line), source_file)) {
        char* cursor = line;

        printf("PASS2: %s\n", cursor);
        while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r' || *cursor == '\n') cursor++;
        cursor[strcspn(cursor, "\r\n")] = 0;
        if (strlen(cursor) == 0 || cursor[0] == ';' || cursor[0] == '#') continue;
        if (strncmp(cursor, "define ", 7) == 0)
        {
            continue;
        }
        if (strchr(cursor, ':') != NULL) continue;
        if (strncmp(cursor, "HEX ", 4) == 0) {
            char buffer[256];
            strcpy(buffer, cursor + 4);

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
        strcpy(tokenize_buffer, cursor);
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
        compile_instruction_safe(op, op1, op2, op3, output_file, mnemonic);
    }

    fclose(expanded_file); // source_file == expanded_file here; closing once is sufficient
    fclose(output_file);
    printf("\nSuccess! Saved to '%s'\n", output_filename);
    printf("The resolved addresses of labels may be useful, so here they are:\n");
    for (size_t i = 0; i < label_count; i++)
    {
        printf("%s is at %04x:%04x\n", label_table[i].name, label_table[i].address.bank, label_table[i].address.offset);
    }
    printf("Type 'exit' then press enter to exit\n");
    char waitForClose[64];
    scanf("%s", waitForClose);
    return 0;
}
