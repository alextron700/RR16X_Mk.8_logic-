/*
 * RR16X BASIC - standalone C interpreter
 *
 * This is a genuine standalone interpreter: it lexes and executes BASIC
 * source directly on the host CPU. It does NOT emit RR16X machine code -
 * that's a deliberate divergence from the assembly JIT, made so this can
 * run on any platform without an RR16X emulator (see conversation for why).
 *
 * Language covered: assignment, PRINT (string literal or variable),
 * if (cond) { ... }, while (cond) { ... }, for (var = start To end) { ... },
 * func name() { ... } declarations and no-arg calls.
 *
 * Variables are plain 32-bit signed integers (long). There is currently no
 * string-variable support - PRINT on a variable prints its numeric value.
 * This diverges from the assembly's design (which treats a printed
 * variable's value as a pointer to stream characters from), because that
 * behavior depends on a string-assignment codepath that doesn't exist yet
 * in either version - printing a numeric value is the only behavior that's
 * actually well-defined right now.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ================================================================
 * Keyword hashes (DJB2, hash = 0x1505; hash = hash*33 + c per char)
 * Keywords are lowercased before hashing - see fold_lower() - so
 * "IF", "If", "if" all match the same keyword.
 * ================================================================ */
#define HASH_IF     0x00597834UL   /* "if"    */
#define HASH_WHILE  0x10A3387EUL   /* "while" */
#define HASH_FOR    0x0B88738CUL   /* "for"   */
#define HASH_FUNC   0x7C96FE71UL   /* "func"  */
#define HASH_PRINT  0x102A0912UL   /* "print" */
#define HASH_TO     0x005979A8UL   /* "to"    */

/* ================================================================
 * Tokens
 * ================================================================ */

typedef enum {
    TOKEN_EOF,
    TOKEN_ID,
    TOKEN_NUMBER,
    TOKEN_SYMBOL,
    TOKEN_STRING
} TokenType;

typedef struct { unsigned long hash; }               IDtoken;
typedef struct { long value; }                       NumToken;
typedef struct { char value; }                        SymToken;
typedef struct { size_t length; const char *data; }   StrToken;

typedef struct {
    TokenType type;
    union {
        IDtoken  id;
        NumToken number;
        SymToken symbol;
        StrToken str;
    };
} Token;

#define MAX_TOKENS 65536
static Token  Tokens[MAX_TOKENS];
static size_t tokenCount = 0;
static size_t token_Position = 0;
static Token  currentToken;

/* ================================================================
 * Lexer
 * ================================================================ */

typedef enum {
    MODE_IDLE   = 0,
    MODE_ID     = 1,
    MODE_NUMBER = 2,
    MODE_SYMBOL = 3,
    MODE_STRING = 4
} LexMode;

#define LEXBUF_SIZE 4096
static char idBuffer[LEXBUF_SIZE];
static char numBuffer[LEXBUF_SIZE];

static void dealWithID(const char *buf, int len)
{
    if (len == 0) return;
    unsigned long long h = 0x1505;
    for (int i = 0; i < len; i++) {
        char c = buf[i];
        if (c >= 'A' && c <= 'Z') c = (char)(c - 'A' + 'a'); /* case-fold */
        h = h * 33 + (unsigned char)c;
    }
    Token t;
    t.type = TOKEN_ID;
    t.id.hash = (unsigned long)(h & 0xFFFFFFFFUL);
    if (tokenCount < MAX_TOKENS) Tokens[tokenCount++] = t;
}

static void dealWithNum(const char *buf, int len)
{
    if (len == 0) return;
    long value = 0;
    for (int i = 0; i < len; i++) value = value * 10 + (buf[i] - '0');
    Token t;
    t.type = TOKEN_NUMBER;
    t.number.value = value;
    if (tokenCount < MAX_TOKENS) Tokens[tokenCount++] = t;
}

static void dealWithSym(char c)
{
    Token t;
    t.type = TOKEN_SYMBOL;
    t.symbol.value = c;
    if (tokenCount < MAX_TOKENS) Tokens[tokenCount++] = t;
}

static void dealWithString(const char *data, size_t length)
{
    Token t;
    t.type = TOKEN_STRING;
    t.str.data = data;
    t.str.length = length;
    if (tokenCount < MAX_TOKENS) Tokens[tokenCount++] = t;
}

static void trigger_syntax_error(const char *why)
{
    printf("ERROR: %s\n", why ? why : "syntax error");
}

/*
 * Tokenizes the ENTIRE input buffer at once (not line-by-line). This is a
 * deliberate difference from the assembly's single-line REPL: newlines are
 * just ordinary whitespace to this lexer (ASCII <= 0x20), so a multi-line
 * program with real line breaks tokenizes identically to one typed on a
 * single line. That lets if/while/for/func bodies span multiple lines,
 * which is far more usable than requiring one giant line.
 */
static void parse_line(const char *line, size_t length)
{
    tokenCount = 0;
    size_t index = 0;

    int lex_id_offset  = 0;
    int lex_num_offset = 0;
    LexMode mode = MODE_IDLE;

    const char *string_start = NULL;
    size_t string_length = 0;

    while (index < length && line[index] != '\0') {
        char place = line[index];

        if (mode == MODE_STRING) {
            if (place == '"') {
                dealWithString(string_start, string_length);
                mode = MODE_IDLE;
                ++index;
                continue;
            }
            ++string_length;
            ++index;
            continue;
        }

        if ((unsigned char)place <= 0x20) {
            if (mode == MODE_ID)     { dealWithID(idBuffer, lex_id_offset);  lex_id_offset = 0;  mode = MODE_IDLE; }
            else if (mode == MODE_NUMBER) { dealWithNum(numBuffer, lex_num_offset); lex_num_offset = 0; mode = MODE_IDLE; }
            ++index;
            continue;
        }

        if (place == '"') {
            mode = MODE_STRING;
            string_start = &line[index + 1];
            string_length = 0;
            ++index;
            continue;
        }

        if (mode == MODE_ID) {
            if ((place >= 'A' && place <= 'Z') || (place >= 'a' && place <= 'z') ||
                (place >= '0' && place <= '9')) {
                if (lex_id_offset < LEXBUF_SIZE - 1) idBuffer[lex_id_offset++] = place;
                ++index;
                continue;
            }
            dealWithID(idBuffer, lex_id_offset);
            lex_id_offset = 0;
            mode = MODE_IDLE;
            continue; /* reprocess terminating char */
        }

        if (mode == MODE_NUMBER) {
            if (place >= '0' && place <= '9') {
                if (lex_num_offset < LEXBUF_SIZE - 1) numBuffer[lex_num_offset++] = place;
                ++index;
                continue;
            }
            dealWithNum(numBuffer, lex_num_offset);
            lex_num_offset = 0;
            mode = MODE_IDLE;
            continue; /* reprocess terminating char */
        }

        if ((place >= 'A' && place <= 'Z') || (place >= 'a' && place <= 'z')) {
            mode = MODE_ID;
            idBuffer[lex_id_offset++] = place;
            ++index;
            continue;
        }

        if (place >= '0' && place <= '9') {
            mode = MODE_NUMBER;
            numBuffer[lex_num_offset++] = place;
            ++index;
            continue;
        }

        /* symbol: single character, immediate token */
        dealWithSym(place);
        ++index;
    }

    if (mode == MODE_ID)     dealWithID(idBuffer, lex_id_offset);
    else if (mode == MODE_NUMBER) dealWithNum(numBuffer, lex_num_offset);
    else if (mode == MODE_STRING) trigger_syntax_error("unterminated string");
}

static void advanceToken(void)
{
    if (token_Position >= tokenCount) { currentToken.type = TOKEN_EOF; return; }
    currentToken = Tokens[token_Position++];
}


/* ================================================================
 * Variable symbol table (global scope only - see notes on functions
 * below for why there's no local scoping yet)
 * ================================================================ */

#define MAX_VARS 1024
typedef struct { unsigned long hash; long value; int used; } VarSlot;
static VarSlot vars[MAX_VARS];

static int find_var_slot(unsigned long hash)
{
    for (int i = 0; i < MAX_VARS; i++) {
        if (vars[i].used && vars[i].hash == hash) return i;
    }
    return -1;
}

static void set_variable(unsigned long hash, long value)
{
    int slot = find_var_slot(hash);
    if (slot < 0) {
        for (int i = 0; i < MAX_VARS; i++) {
            if (!vars[i].used) { slot = i; break; }
        }
        if (slot < 0) { trigger_syntax_error("variable table full"); return; }
        vars[slot].used = 1;
        vars[slot].hash = hash;
    }
    vars[slot].value = value;
}

static int get_variable(unsigned long hash, long *out_value)
{
    int slot = find_var_slot(hash);
    if (slot < 0) return 0;
    *out_value = vars[slot].value;
    return 1;
}

/* ================================================================
 * Function table
 *
 * No parameters/return values/local scope, matching what the
 * assembly's parser actually implements (func name() { ... }, called
 * as name();) - there's no argument-token handling anywhere in
 * parse_function_declaration or compile_function_call to build on.
 * ================================================================ */

#define MAX_FUNCS 256
typedef struct { unsigned long hash; size_t body_start; int used; } FuncSlot;
static FuncSlot funcs[MAX_FUNCS];
static int func_count = 0;

static int find_function(unsigned long hash)
{
    for (int i = 0; i < func_count; i++)
        if (funcs[i].hash == hash) return i;
    return -1;
}

/* ================================================================
 * Statement execution - forward declarations
 * ================================================================ */

/* ================================================================
 * Statement execution - forward declarations
 *
 * Everything here genuinely executes when called; skipping a
 * not-taken branch (false if, function declaration bodies, a
 * finished loop) is handled entirely by skip_block(), which scans
 * for the matching '}' purely by brace-depth counting and never
 * calls into these functions at all. That means there's no need to
 * thread an "am I really executing right now" flag through every
 * statement handler - if a handler runs, it means it.
 * ================================================================ */

static void parser_statement_dispatcher(void);
static long evaluate_expression(void);
static void skip_block(void);
static void execute_block(void);

/* ================================================================
 * Expression evaluator
 * ================================================================ */

static long evaluate_expression(void)
{
    long left;

    if (currentToken.type == TOKEN_ID) {
        if (!get_variable(currentToken.id.hash, &left)) {
            trigger_syntax_error("undefined variable");
            left = 0;
        }
    } else if (currentToken.type == TOKEN_NUMBER) {
        left = currentToken.number.value;
    } else {
        trigger_syntax_error("expected variable or number");
        return 0;
    }

    advanceToken();

    if (currentToken.type != TOKEN_SYMBOL) return left;

    char op = currentToken.symbol.value;
    if (op == ';' || op == ')' || op == '{') return left; /* expression ends here */

    advanceToken();

    long right;
    if (currentToken.type == TOKEN_ID) {
        if (!get_variable(currentToken.id.hash, &right)) {
            trigger_syntax_error("undefined variable");
            right = 0;
        }
    } else if (currentToken.type == TOKEN_NUMBER) {
        right = currentToken.number.value;
    } else {
        trigger_syntax_error("expected variable or number after operator");
        return 0;
    }
    advanceToken();

    switch (op) {
        case '-': return left - right;
        case '*': return left * right;
        case '&': return left & right;
        case '|': return left | right;
        case '=': return (left == right) ? 1 : 0;
        case '<': return (left <  right) ? 1 : 0;
        case '>': return (left >  right) ? 1 : 0;
        default:  return left + right; /* default per assembly's .emit_math_instructions */
    }
}

/* ================================================================
 * PRINT
 * ================================================================ */

static void execute_print_statement(void)
{
    advanceToken(); /* consume "print" */

    if (currentToken.type == TOKEN_STRING) {
        printf("%.*s", (int)currentToken.str.length, currentToken.str.data);
        advanceToken();
    } else if (currentToken.type == TOKEN_ID) {
        long v;
        if (!get_variable(currentToken.id.hash, &v)) {
            trigger_syntax_error("undefined variable");
            return;
        }
        printf("%ld", v);
        advanceToken();
    } else {
        trigger_syntax_error("invalid PRINT target");
        return;
    }

    printf("\n");

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != ';') {
        trigger_syntax_error("expected ';' after PRINT");
        return;
    }
}

/* ================================================================
 * Assignment:  name = expr ;
 * ================================================================ */

static void execute_assignment(void)
{
    unsigned long hash = currentToken.id.hash;
    advanceToken(); /* consume name */

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '=') {
        trigger_syntax_error("expected '=' in assignment");
        return;
    }
    advanceToken(); /* consume '=' */

    long value = evaluate_expression();
    set_variable(hash, value);

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != ';') {
        trigger_syntax_error("expected ';' after assignment");
        return;
    }
}

/* ================================================================
 * Block skipping / execution
 *
 * Convention: the caller consumes '(' ... ')' and leaves currentToken
 * sitting on '{'. execute_block()/skip_block() consume the '{', run
 * to the matching '}', and leave currentToken sitting on '}' itself
 * (the caller's own caller - parse_program or execute_block's while
 * loop - advances past it to reach the next statement).
 * ================================================================ */

static void skip_block(void)
{
    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '{') {
        trigger_syntax_error("expected '{'");
        return;
    }
    int depth = 1;
    advanceToken();
    while (depth > 0) {
        if (currentToken.type == TOKEN_EOF) { trigger_syntax_error("unclosed '{'"); return; }
        if (currentToken.type == TOKEN_SYMBOL && currentToken.symbol.value == '{') depth++;
        else if (currentToken.type == TOKEN_SYMBOL && currentToken.symbol.value == '}') { depth--; if (depth == 0) break; }
        advanceToken();
    }
    /* currentToken is now the matching '}' */
}

static void execute_block(void)
{
    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '{') {
        trigger_syntax_error("expected '{'");
        return;
    }
    advanceToken();
    while (!(currentToken.type == TOKEN_SYMBOL && currentToken.symbol.value == '}')) {
        if (currentToken.type == TOKEN_EOF) { trigger_syntax_error("unclosed '{'"); return; }
        parser_statement_dispatcher();
        advanceToken();
    }
    /* currentToken is now '}' */
}

/* ================================================================
 * if (cond) { ... }
 * ================================================================ */

static void compile_if_statement(void)
{
    advanceToken(); /* consume "if" */
    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '(') {
        trigger_syntax_error("expected '(' after if"); return;
    }
    advanceToken();

    long cond = evaluate_expression();

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != ')') {
        trigger_syntax_error("expected ')' after if condition"); return;
    }
    advanceToken(); /* now sitting on '{' */

    if (cond != 0) execute_block();
    else skip_block();
}

/* ================================================================
 * while (cond) { ... }
 * ================================================================ */

static void compile_while_loop(void)
{
    advanceToken(); /* consume "while" */
    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '(') {
        trigger_syntax_error("expected '(' after while"); return;
    }
    advanceToken();

    size_t cond_pos = token_Position - 1; /* position of first cond token */

    for (;;) {
        token_Position = cond_pos;
        advanceToken();

        long cond = evaluate_expression();

        if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != ')') {
            trigger_syntax_error("expected ')' after while condition"); return;
        }
        advanceToken(); /* now sitting on '{' */

        if (cond != 0) {
            execute_block();
        } else {
            skip_block();
            break;
        }
    }
    /* currentToken is now the block's '}' */
}

/* ================================================================
 * for (var = start To end) { ... }
 *
 * NOTE: the assembly version never increments the loop variable
 * anywhere in compile_for_loop - as written it's an infinite loop
 * unless the body itself modifies the counter. This uses standard
 * BASIC semantics (auto-increment by 1 each iteration) since that's
 * the only way "for" is actually usable - flagging this as a real
 * bug to fix in the assembly separately.
 * ================================================================ */

static void compile_for_loop(void)
{
    advanceToken(); /* consume "for" */
    if (currentToken.type != TOKEN_ID) { trigger_syntax_error("expected loop variable"); return; }
    unsigned long var_hash = currentToken.id.hash;
    advanceToken();

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '=') {
        trigger_syntax_error("expected '=' after for variable"); return;
    }
    advanceToken();

    long start = evaluate_expression();
    set_variable(var_hash, start);

    if (currentToken.type != TOKEN_ID || currentToken.id.hash != HASH_TO) {
        trigger_syntax_error("expected 'to' in for loop"); return;
    }
    advanceToken();

    long end_value = evaluate_expression(); /* consumed once, up front, to find '{' */

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '{') {
        trigger_syntax_error("expected '{' after for range"); return;
    }
    size_t body_pos = token_Position - 1;

    long counter = start;
    for (;;) {
        if (counter > end_value) {
            token_Position = body_pos;
            advanceToken();
            skip_block();
            break;
        }
        set_variable(var_hash, counter);
        token_Position = body_pos;
        advanceToken();
        execute_block();
        counter++;
    }
    /* currentToken is now the block's '}' */
}

/* ================================================================
 * func name() { ... }   (declaration only - body is skipped, not run)
 * ================================================================ */

static void parse_function_declaration(void)
{
    advanceToken(); /* consume "func" */
    if (currentToken.type != TOKEN_ID) { trigger_syntax_error("expected function name"); return; }
    unsigned long hash = currentToken.id.hash;
    advanceToken();

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '(') {
        trigger_syntax_error("expected '(' in function declaration"); return;
    }
    advanceToken();
    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != ')') {
        trigger_syntax_error("expected ')' in function declaration (no parameters supported)"); return;
    }
    advanceToken(); /* now sitting on '{' */

    if (func_count < MAX_FUNCS) {
        funcs[func_count].hash = hash;
        funcs[func_count].body_start = token_Position - 1; /* position of '{' */
        funcs[func_count].used = 1;
        func_count++;
    } else {
        trigger_syntax_error("function table full");
    }

    skip_block(); /* declarations never execute their body inline */
}

static void compile_function_call(void)
{
    int idx = find_function(currentToken.id.hash);
    advanceToken(); /* consume function name */

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != '(') {
        trigger_syntax_error("expected '(' in function call"); return;
    }
    advanceToken();
    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != ')') {
        trigger_syntax_error("expected ')' in function call (no arguments supported)"); return;
    }
    advanceToken();

    if (currentToken.type != TOKEN_SYMBOL || currentToken.symbol.value != ';') {
        trigger_syntax_error("expected ';' after function call"); return;
    }

    if (idx < 0) { trigger_syntax_error("call to undefined function"); return; }

    size_t return_pos = token_Position; /* one past the ';' token */
    token_Position = funcs[idx].body_start;
    advanceToken();
    execute_block();

    /* Land back on the ';' that follows the call - same exit
     * convention as every other statement handler. */
    token_Position = return_pos - 1;
    advanceToken();
}

/* ================================================================
 * Statement dispatcher
 * ================================================================ */

static int check_if_function_exists(unsigned long hash)
{
    return find_function(hash) >= 0;
}

static void parser_statement_dispatcher(void)
{
    if (currentToken.type == TOKEN_EOF) return;

    if (currentToken.type != TOKEN_ID) {
        trigger_syntax_error("expected statement");
        return;
    }

    unsigned long hash = currentToken.id.hash;

    if (hash == HASH_IF)    { compile_if_statement();   return; }
    if (hash == HASH_WHILE) { compile_while_loop();      return; }
    if (hash == HASH_FOR)   { compile_for_loop();        return; }
    if (hash == HASH_FUNC)  { parse_function_declaration(); return; }
    if (hash == HASH_PRINT) { execute_print_statement(); return; }
    if (check_if_function_exists(hash)) { compile_function_call(); return; }

    execute_assignment();
}

static void parse_program(void)
{
    token_Position = 0;
    advanceToken();
    while (currentToken.type != TOKEN_EOF) {
        parser_statement_dispatcher();
        advanceToken();
    }
}

/* ================================================================
 * Entry point
 * ================================================================ */

int main(void)
{
    printf("RR16X Mk.8.1 BASIC\nall systems online\nREADY.\n\n");

    static char source[1 << 20];
    size_t len = fread(source, 1, sizeof(source) - 1, stdin);
    source[len] = '\0';

    parse_line(source, len);
    parse_program();

    return 0;
}
