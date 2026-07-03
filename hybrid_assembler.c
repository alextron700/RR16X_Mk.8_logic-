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
    TOKEN_MNEMONIC,
    TOKEN_REGISTER,
    TOKEN_IMMEDIATE,
    TOKEN_COMMA,
    TOKEN_NEWLINE,
    TOKEN_EOF
} TokenType;

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
    char name[64];
    unsigned short address;
} Label;

Label label_table[100];
int label_count = 0;

typedef struct {
    const char* mnemonic;
    unsigned short base_opcode;
    InstForm form;
} Opcode_entry;

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

unsigned short resolve_value(const char* token) {
    if (!token || strlen(token) == 0) return 0;

    for (int i = 0; i < label_count; i++) {
        if (strcmp(label_table[i].name, token) == 0) {
            return label_table[i].address;
        }
    }
    return (unsigned short)strtol(token, NULL, 0);
}

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

void compile_instruction_safe(Opcode_entry* op, char* op1, char* op2, char* op3, FILE* output_file, const char* raw_mnemonic) {
    unsigned short machine_word = op->base_opcode;
    unsigned short immediate_queue[2] = { 0 };
    int immediate_count = 0;
    char clean_op_buffer[64];
    int defer_bank_reset = 0;

    if (op->form == FMT_R_N_R || op->form == FMT_R_R_N || op->form == FMT_N_R_N) {
        char* target_check = NULL;
        if (op->form == FMT_N_R_N)      target_check = op1;
        else if (op->form == FMT_R_R_N) target_check = op3;
        else                            target_check = op2;

        if (target_check && (strncmp(target_check, "0x", 2) == 0 || strncmp(target_check, "0X", 2) == 0)) {
            unsigned long full_addr = strtoul(target_check, NULL, 16);

            if (full_addr > 0xFFFF) {
                unsigned short target_bank = (unsigned short)((full_addr >> 16) & 0x7FF);

                Opcode_entry* eam_op = lookup_opcode("EAM.SET");
                char bank_str[16];
                sprintf(bank_str, "0x%04X", target_bank);
                compile_instruction_safe(eam_op, bank_str, NULL, NULL, output_file, "EAM.SET");

                sprintf(clean_op_buffer, "0x%04X", (unsigned short)(full_addr & 0xFFFF));
                if (op->form == FMT_N_R_N)      op1 = clean_op_buffer;
                else if (op->form == FMT_R_R_N) op3 = clean_op_buffer;
                else                            op2 = clean_op_buffer;

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
                immediate_queue[immediate_count++] = resolve_value(target_op);
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
                immediate_queue[immediate_count++] = (resolve_value(target_op3) & 0xFFFF);
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

int main() {
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
        return 1;
    }

    char line[256];
    unsigned short current_hardware_address = 0;

    while (fgets(line, sizeof(line), source_file)) {
        char* cursor = line;
        while (*cursor == ' ' || *cursor == '\t' || *cursor == '\r' || *cursor == '\n') cursor++;

        if (strlen(cursor) == 0 || cursor[0] == ';' || cursor[0] == '#') continue;

        if (strchr(cursor, ':') != NULL) {
            char func_name[64];
            sscanf(cursor, "%[^:]", func_name);
            strcpy(label_table[label_count].name, func_name);
            label_table[label_count].address = current_hardware_address;
            label_count++;
            continue;
        }

        int instruction_words = 0;

        if (strncmp(cursor, "call ", 5) == 0) {
            instruction_words = 2;
            current_hardware_address += instruction_words;
            continue;
        }
        else if (strncmp(cursor, "print", 5) == 0) {
            instruction_words = 6;
            current_hardware_address += instruction_words;
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
            current_hardware_address += instruction_words;
            continue;
        }
        else {
            instruction_words = 1;
            char temp[256]; strcpy(temp, cursor);
            char* mnemonic = strtok(temp, " ,\t");
            char* o1 = strtok(NULL, " ,\t");
            char* o2 = strtok(NULL, " ,\t");
            char* o3 = strtok(NULL, " ,\t");

            Opcode_entry* op = lookup_opcode(mnemonic);
            if (op) {
                instruction_words += check_immediate_bank_extension(op, o1, o2, o3);

                if (op->form == FMT_R_R_N) {
                    if (o3 && parse_register(o3) == -1) instruction_words++;
                    else if (!o3 && o2 && parse_register(o2) == -1) instruction_words++;
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
        current_hardware_address += instruction_words;
    }
    fclose(source_file);

    // =========================================================================
    // PASS 2: GENERATE MACHINE HEX CODES
    // =========================================================================
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
        if (strchr(cursor, ':') != NULL) continue;

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
                    char addr_str[16]; sprintf(addr_str, "0x%04X", target_address);
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

        compile_instruction_safe(op, op1, op2, op3, output_file, mnemonic);
    }

    fclose(source_file);
    fclose(output_file);
    printf("\nSuccess! Saved to '%s'\n", output_filename);
    return 0;
}