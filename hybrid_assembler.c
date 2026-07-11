#include <stdio.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>

#define SHIFT_OPCODE  12
#define SHIFT_M_FLAG  11
#define SHIFT_REG_D      8
#define MASK_LX       (1 << 7)
#define SHIFT_REG_X     4
#define MASK_LY       (1 << 3)
#define MASK_REG_Y     0x0007

typedef enum {
    FMT_R_R_R,   // dest, src1, src2          e.g. ADD R1, R2, R3
    FMT_R_R_N,   // dest, src1, imm           e.g. ADD R1, R2, #42
    FMT_N_R_R,   // addr, src1, src2          e.g. STM addr, Rsrc
    FMT_R_N_R,   // dest, imm, src            e.g. LDM Rdest, addr, Rbase
    FMT_N_R_N,   // imm1, reg, imm2           e.g. EAM.SET bank
    FMT_N_N_N,   // no register args          e.g. RET, HLT
    FMT_UNKNOWN
} InstForm;

typedef struct {
    char name[64];
    unsigned short address;
} Label;

Label label_table[256];
int label_count = 0;

typedef struct {
    const char* mnemonic;
    unsigned short base_opcode;
    InstForm form;
    const char* description;
} Opcode_entry;

Opcode_entry optable[] = {
    {"EAM.SET",   0x0000, FMT_N_R_N, "Set external address mode (data bank)"},
    {"IVR.SET",   0x0800, FMT_N_R_N, "Set interrupt vector register"},
    {"ADD",       0x1000, FMT_R_R_R, "Add: dest = src1 + src2"},
    {"SUB",       0x2000, FMT_R_R_R, "Subtract: dest = src1 - src2"},
    {"AND",       0x3000, FMT_R_R_R, "Bitwise AND: dest = src1 & src2"},
    {"OR",        0x4000, FMT_R_R_R, "Bitwise OR: dest = src1 | src2"},
    {"NOT",       0x5000, FMT_R_R_N, "Bitwise NOT: dest = ~src1"},
    {"XOR",       0x6000, FMT_R_R_R, "Bitwise XOR: dest = src1 ^ src2"},
    {"SHL",       0x7000, FMT_R_R_N, "Shift left: dest = src1 << imm"},
    {"SHR",       0x8000, FMT_R_R_N, "Shift right: dest = src1 >> imm"},
    {"LDM",       0x9000, FMT_R_N_R, "Load memory: dest = mem[addr + base]"},
    {"STM",       0xA000, FMT_N_R_R, "Store memory: mem[addr] = src"},
    {"STJ",       0xB000, FMT_N_R_N, "Set jump register"},
    {"NIL",       0xC000, FMT_N_N_N, "No operation"},
    {"JLT",       0xC100, FMT_N_R_R, "Jump if less than"},
    {"JEQ",       0xC200, FMT_N_R_R, "Jump if equal"},
    {"JLE",       0xC300, FMT_N_R_R, "Jump if less or equal"},
    {"JGT",       0xC400, FMT_N_R_R, "Jump if greater than"},
    {"JNE",       0xC500, FMT_N_R_R, "Jump if not equal"},
    {"JGE",       0xC600, FMT_N_R_R, "Jump if greater or equal"},
    {"JMP",       0xC700, FMT_N_N_N, "Unconditional jump (via JR)"},
    {"JLT.U",     0xC800, FMT_N_R_R, "Jump if less than (unsigned)"},
    {"JEQ.U",     0xC900, FMT_N_R_R, "Jump if equal (unsigned)"},
    {"JLE.U",     0xCA00, FMT_N_R_R, "Jump if less or equal (unsigned)"},
    {"JGT.U",     0xCB00, FMT_N_R_R, "Jump if greater than (unsigned)"},
    {"JNE.U",     0xCC00, FMT_N_R_R, "Jump if not equal (unsigned)"},
    {"JGE.U",     0xCD00, FMT_N_R_R, "Jump if greater or equal (unsigned)"},
    {"JGT.E",     0xCE00, FMT_N_R_R, "Jump if greater than (extended)"},
    {"JGT.UE",    0xCF00, FMT_N_R_R, "Jump if greater than (unsigned ext)"},
    {"CAL",       0xD000, FMT_N_R_N, "Call subroutine"},
    {"RET",       0xE000, FMT_N_N_N, "Return from subroutine"},
    {"HLT",       0xF000, FMT_N_N_N, "Halt processor"},
    {NULL,        0x0000, FMT_UNKNOWN, NULL}
};

/*
 * INSTRUCTION FORMAT (16-bit word):
 *
 *   15 14 13 12  11  10  9  8   7   6  5  4   3   2  1  0
 *  +-----------+----+-------+----+-------+----+-------+
 *  |  OPCODE   | M  | REG_D | LX | REG_X | LY | REG_Y |
 *  |  (4 bits) |flag| (3b)  |flag| (3b)  |flag| (3b)  |
 *  +-----------+----+-------+----+-------+----+-------+
 *
 *  For branches (0xCxxx), bits 11-8 are sub-opcode, not REG_D.
 *  M_FLAG (bit 11): Set by .C or .SHORT suffix for carry/short mode.
 *  LX/LY flags: When set, REG_X/REG_Y field is ignored and value
 *               comes from the following word (long immediate).
 */

Opcode_entry* lookup_opcode(const char* mnemonic) {
    int i = 0;
    char base_mnemonic[128];
    strncpy(base_mnemonic, mnemonic, sizeof(base_mnemonic) - 1);
    base_mnemonic[sizeof(base_mnemonic) - 1] = '\0';

    /* Strip .C and .SHORT suffixes (but NOT branch suffixes like .U, .E) */
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

unsigned short resolve_value(const char* token) {
    if (!token || strlen(token) == 0) return 0;

    for (int i = 0; i < label_count; i++) {
        if (strcmp(label_table[i].name, token) == 0) {
            return label_table[i].address;
        }
    }
    return (unsigned short)strtol(token, NULL, 0);
}

/*
 * Check if an immediate value needs bank extension (> 16 bits).
 * Returns: 0 = fits in 16 bits, 2 = needs bank prefix + suffix.
 */
int check_immediate_bank_extension(Opcode_entry* op, const char* o1, const char* o2, const char* o3) {
    const char* target_check = NULL;
    if (op->form == FMT_N_R_N)      target_check = o1;
    else if (op->form == FMT_R_R_N) target_check = o3;
    else if (op->form == FMT_R_N_R) target_check = o2;

    if (target_check) {
        if (strncmp(target_check, "0x", 2) == 0 || strncmp(target_check, "0X", 2) == 0) {
            unsigned long full_addr = strtoul(target_check, NULL, 16);
            if (full_addr > 0xFFFF) return 2;
        }
    }
    return 0;
}

/*
 * Emit an EAM.SET instruction to set the data bank.
 * Uses compile_instruction_safe to generate proper 2-word format.
 */
 /* Forward declaration */
void compile_instruction_safe(Opcode_entry* op, char* op1, char* op2, char* op3,
    FILE* output_file, const char* raw_mnemonic);


void emit_eam_set(unsigned short bank, FILE* output_file) {
    Opcode_entry* eam_op = lookup_opcode("EAM.SET");
    char bank_str[16];
    sprintf(bank_str, "0x%04X", bank);
    compile_instruction_safe(eam_op, bank_str, NULL, NULL, output_file, "EAM.SET");
}

/*
 * Compile a single instruction to machine code.
 *
 * Operand mapping by format:
 *   FMT_R_R_R:  op1=dest_reg, op2=src1_reg, op3=src2_reg/imm
 *   FMT_R_R_N:  op1=dest_reg, op2=src1_reg, op3=src2_imm
 *   FMT_N_R_R:  op1=addr,     op2=src_reg,  op3=(unused)
 *   FMT_R_N_R:  op1=dest_reg, op2=addr_imm, op3=base_reg
 *   FMT_N_R_N:  op1=imm1,     op2=reg,      op3=imm2 (unused)
 *   FMT_N_N_N:  no operands used
 */
void compile_instruction_safe(Opcode_entry* op, char* op1, char* op2, char* op3,
    FILE* output_file, const char* raw_mnemonic) {
    unsigned short machine_word = op->base_opcode;
    unsigned short immediate_queue[2] = { 0 };
    int immediate_count = 0;
    char clean_op_buffer[64];
    int defer_bank_reset = 0;

    /* --- Handle >16-bit addresses with automatic bank switching --- */
    if (op->form == FMT_R_N_R || op->form == FMT_R_R_N || op->form == FMT_N_R_N) {
        char* target_check = NULL;
        if (op->form == FMT_N_R_N)      target_check = op1;
        else if (op->form == FMT_R_R_N) target_check = op3;
        else                            target_check = op2;

        if (target_check && (strncmp(target_check, "0x", 2) == 0 || strncmp(target_check, "0X", 2) == 0)) {
            unsigned long full_addr = strtoul(target_check, NULL, 16);

            if (full_addr > 0xFFFF) {
                unsigned short target_bank = (unsigned short)((full_addr >> 16) & 0x7FF);
                emit_eam_set(target_bank, output_file);

                sprintf(clean_op_buffer, "0x%04X", (unsigned short)(full_addr & 0xFFFF));
                if (op->form == FMT_N_R_N)      op1 = clean_op_buffer;
                else if (op->form == FMT_R_R_N) op3 = clean_op_buffer;
                else                            op2 = clean_op_buffer;

                defer_bank_reset = 1;
            }
        }
    }

    /* --- Set M_FLAG for .C or .SHORT suffix --- */
    if (strstr(raw_mnemonic, ".C") != NULL || strstr(raw_mnemonic, ".SHORT") != NULL) {
        machine_word |= (1 << SHIFT_M_FLAG);
    }

    /* --- FIELD 1: REG_D (Bits 10-8) --- */
    if (op->form == FMT_R_R_R || op->form == FMT_R_R_N || op->form == FMT_R_N_R) {
        if (op1 && strlen(op1) > 0) {
            int reg_d = parse_register(op1);
            if (reg_d != -1) {
                machine_word |= (reg_d << SHIFT_REG_D);
            }
        }
    }

    /* --- FIELD 2: REG_X or Immediate (Bits 6-4, with LX flag at bit 7) --- */
    if (op->form == FMT_R_R_R || op->form == FMT_R_R_N ||
        op->form == FMT_N_R_R || op->form == FMT_N_R_N || op->form == FMT_R_N_R) {

        char* target_op = NULL;
        switch (op->form) {
        case FMT_N_R_N:
        case FMT_N_R_R:
            target_op = op1;  /* Address/immediate for store/jump */
            break;
        case FMT_R_R_R:
        case FMT_R_R_N:
            target_op = op2;  /* Source 1 register */
            break;
        case FMT_R_N_R:
            target_op = op2;  /* Address immediate for load */
            break;
        default:
            break;
        }

        if (target_op && strlen(target_op) > 0) {
            int reg_x = parse_register(target_op);
            if (reg_x == -1) {
                /* Not a register - use as immediate */
                machine_word |= MASK_LX;
                immediate_queue[immediate_count++] = resolve_value(target_op);
            }
            else {
                machine_word |= (reg_x << SHIFT_REG_X);
            }
        }
    }

    /* --- FIELD 3: REG_Y or Immediate (Bits 2-0, with LY flag at bit 3) --- */
    if (op->form == FMT_R_R_R || op->form == FMT_R_N_R ||
        op->form == FMT_N_R_R || op->form == FMT_R_R_N) {

        char* target_op3 = NULL;
        switch (op->form) {
        case FMT_N_R_R:
            target_op3 = op2;  /* Source register for store */
            break;
        case FMT_R_R_R:
        case FMT_R_R_N:
            target_op3 = op3;  /* Source 2 register/immediate */
            break;
        case FMT_R_N_R:
            target_op3 = op3;  /* Base register for load */
            break;
        default:
            break;
        }

        if (target_op3 && strlen(target_op3) > 0) {
            int reg_y = parse_register(target_op3);
            if (reg_y == -1) {
                /* Not a register - use as immediate */
                machine_word |= MASK_LY;
                immediate_queue[immediate_count++] = (resolve_value(target_op3) & 0xFFFF);
            }
            else {
                machine_word |= (reg_y & MASK_REG_Y);
            }
        }
    }

    /* --- Emit machine word and any immediate follow-up words --- */
    fprintf(output_file, "%04X\n", machine_word);
    for (int i = 0; i < immediate_count; i++) {
        fprintf(output_file, "%04X\n", immediate_queue[i]);
    }

    /* --- Reset bank if we changed it --- */
    if (defer_bank_reset) {
        emit_eam_set(0x0000, output_file);
    }
}

/*
 * High-level syntax compilation (macros and sugar).
 */
int process_high_level_compile(const char* line_buffer, FILE* output_file) {
    char left_side[64] = { 0 };
    char right_side[128] = { 0 };

    /* --- print 'X'  =>  Load char into R0, then STM to console --- */
    if (strncmp(line_buffer, "print ", 6) == 0) {
        char ch;
        if (sscanf(line_buffer, "print '%c'", &ch) == 1) {
            Opcode_entry* add_op = lookup_opcode("ADD");
            Opcode_entry* sub_op = lookup_opcode("SUB");
            Opcode_entry* stm_op = lookup_opcode("STM");

            /* Load character value into R0: R0 = 0 + ch */
            char val_str[16];
            sprintf(val_str, "%d", (unsigned char)ch);

            /* R0 = R0 - R0  (clear R0) */
            compile_instruction_safe(sub_op, "R0", "R0", "R0", output_file, "SUB");
            /* R0 = R0 + ch  (load immediate) */
            compile_instruction_safe(add_op, "R0", "R0", val_str, output_file, "ADD");

            /* Set console bank and store R0 to console address */
            emit_eam_set(0x07FF, output_file);
            /* STM console_addr, R0  =>  mem[0xFFFF] = R0 */
            compile_instruction_safe(stm_op, "0xFFFF", "R0", NULL, output_file, "STM");
            /* Reset bank */
            emit_eam_set(0x0000, output_file);

            return 1;
        }
    }

    /* --- Register assignment: Rx = expr --- */
    if (strchr(line_buffer, '=')) {
        if (sscanf(line_buffer, "%[^=]=%[^\n]", left_side, right_side) == 2) {
            char var_d[64];
            sscanf(left_side, "%s", var_d);
            char arg1[64] = { 0 }, op_sign[8] = { 0 }, arg2[64] = { 0 };

            /* Binary operation: Rx = Ry + Rz  or  Rx = Ry + #imm */
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
            /* Simple assignment: Rx = Ry  or  Rx = #imm */
            else if (sscanf(right_side, "%s", arg1) == 1) {
                Opcode_entry* sub_op = lookup_opcode("SUB");
                Opcode_entry* add_op = lookup_opcode("ADD");

                /* Rx = Rx - Rx  (clear) */
                compile_instruction_safe(sub_op, var_d, var_d, var_d, output_file, "SUB");
                /* Rx = Rx + value  (load) */
                compile_instruction_safe(add_op, var_d, var_d, arg1, output_file, "ADD");
                return 1;
            }
        }
    }
    return 0;
}

/*
 * Count words generated by a high-level construct (for Pass 1 address tracking).
 */
int count_hl_words(const char* cursor) {
    if (strncmp(cursor, "print ", 6) == 0) {
        char ch;
        if (sscanf(cursor, "print '%c'", &ch) == 1) {
            /* SUB(1) + ADD(2) + EAM.SET(2) + STM(2) + EAM.SET(2) = 9 words */
            return 9;
        }
    }

    if (strchr(cursor, '=')) {
        char left_side[128] = { 0 }, right_side[128] = { 0 };
        if (sscanf(cursor, "%[^=]=%[^\n]", left_side, right_side) == 2) {
            char arg1[64] = { 0 }, op_sign[8] = { 0 }, arg2[64] = { 0 };
            int items = sscanf(right_side, "%s %s %s", arg1, op_sign, arg2);

            if (items == 3) {
                /* Binary op: base word + immediate words */
                int words = 1;
                if (parse_register(arg1) == -1) words++;
                if (parse_register(arg2) == -1) words++;
                return words;
            }
            else if (items == 1) {
                /* Assignment: SUB(1) + ADD(1+imm?) */
                int words = 2;  /* SUB + ADD base */
                if (parse_register(arg1) == -1) words++;  /* ADD immediate operand */
                return words;
            }
        }
    }
    return 0;
}

/*
 * Count words for a raw assembly instruction (for Pass 1).
 */
int count_raw_words(const char* cursor) {
    char temp[256];
    strcpy(temp, cursor);
    char* mnemonic = strtok(temp, " ,\t");
    char* o1 = strtok(NULL, " ,\t");
    char* o2 = strtok(NULL, " ,\t");
    char* o3 = strtok(NULL, " ,\t");

    Opcode_entry* op = lookup_opcode(mnemonic);
    if (!op) return 0;

    int words = 1;
    words += check_immediate_bank_extension(op, o1, o2, o3);

    switch (op->form) {
    case FMT_R_R_N:
        if (o2 && parse_register(o2) == -1) words++;
        if (o3 && parse_register(o3) == -1) words++;
        break;
    case FMT_R_N_R:
        if (o2 && parse_register(o2) == -1) words++;
        break;
    case FMT_N_R_N:
        if (o1 && parse_register(o1) == -1) words++;
        break;
    case FMT_N_R_R:
        if (o1 && parse_register(o1) == -1) words++;
        if (o2 && parse_register(o2) == -1) words++;
        break;
    default:
        break;
    }
    return words;
}

int main() {
    char file[256];
    char output_filename[256];

    printf("Enter path to input source file: ");
    if (scanf("%255s", file) != 1) return 1;

    printf("Enter name for the output hex file: ");
    if (scanf("%255s", output_filename) != 1) return 1;

    /* =====================================================================
     * PASS 1: Build label table and compute addresses
     * ===================================================================== */
    FILE* source_file = fopen(file, "r");
    if (!source_file) {
        fprintf(stderr, "Error: Could not open source file '%s'.\n", file);
        return 1;
    }

    char line[256];
    unsigned short current_address = 0;

    while (fgets(line, sizeof(line), source_file)) {
        char* cursor = line;
        while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r' || *cursor == '\n') cursor++;
        cursor[strcspn(cursor, "\r\n")] = 0;

        if (strlen(cursor) == 0 || cursor[0] == ';' || cursor[0] == '#') continue;

        /* Label definition: "name:" */
        if (strchr(cursor, ':') != NULL) {
            char func_name[64];
            sscanf(cursor, "%[^:]", func_name);
            strcpy(label_table[label_count].name, func_name);
            label_table[label_count].address = current_address;
            label_count++;
            continue;
        }

        /* call instruction */
        if (strncmp(cursor, "call ", 5) == 0) {
            current_address += 2;  /* CAL + immediate address */
            continue;
        }

        /* High-level constructs */
        int hl_words = count_hl_words(cursor);
        if (hl_words > 0) {
            current_address += hl_words;
            continue;
        }

        /* Raw assembly */
        current_address += count_raw_words(cursor);
    }
    fclose(source_file);

    /* =====================================================================
     * PASS 2: Generate machine code
     * ===================================================================== */
    source_file = fopen(file, "r");
    FILE* output_file = fopen(output_filename, "w");
    if (!output_file) {
        fclose(source_file);
        return 1;
    }

    while (fgets(line, sizeof(line), source_file)) {
        char* cursor = line;
        while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r' || *cursor == '\n') cursor++;
        cursor[strcspn(cursor, "\r\n")] = 0;

        if (strlen(cursor) == 0 || cursor[0] == ';' || cursor[0] == '#') continue;
        if (strchr(cursor, ':') != NULL) continue;  /* Skip label definitions */

        /* call instruction */
        if (strncmp(cursor, "call ", 5) == 0) {
            char target_func[64];
            if (sscanf(cursor, "call %s", target_func) == 1) {
                int target_address = -1;
                for (int i = 0; i < label_count; i++) {
                    if (strcmp(label_table[i].name, target_func) == 0) {
                        target_address = label_table[i].address;
                        break;
                    }
                }
                if (target_address != -1) {
                    char addr_str[16];
                    sprintf(addr_str, "0x%04X", target_address);
                    Opcode_entry* cal_op = lookup_opcode("CAL");
                    compile_instruction_safe(cal_op, addr_str, NULL, NULL, output_file, "CAL");
                    continue;
                }
            }
        }

        /* High-level: assignment */
        if (strchr(cursor, '=')) {
            if (process_high_level_compile(cursor, output_file)) continue;
        }

        /* High-level: print */
        if (strncmp(cursor, "print", 5) == 0) {
            if (process_high_level_compile(cursor, output_file)) continue;
        }

        /* Raw assembly instruction */
        char tokenize_buffer[256];
        strcpy(tokenize_buffer, cursor);
        char* mnemonic = strtok(tokenize_buffer, " ,\t");
        if (!mnemonic) continue;

        Opcode_entry* op = lookup_opcode(mnemonic);
        if (!op) continue;

        char* op1 = strtok(NULL, " ,\t");
        char* op2 = strtok(NULL, " ,\t");
        char* op3 = strtok(NULL, " ,\t");

        compile_instruction_safe(op, op1, op2, op3, output_file, mnemonic);
    }

    fclose(source_file);
    fclose(output_file);
    printf("\nSuccess! Assembled to '%s'\n", output_filename);
    return 0;
}
