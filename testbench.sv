
// ================================================================
// GATEWAY DRUG CPU + FP32 COPROCESSOR
// ================================================================
//
// SystemVerilog source. ( USE ICARUS 12.0) 
//
// ================================================================


// ################################################################
// # RR16X GATEWAY CPU
// ################################################################

module gateway_drug_cpu (
    input  wire        clk,
    input  wire        rst,
    input  wire        ext_interrupt,

    output wire [26:0] mem_addr,
    input  wire [15:0] mem_read_data,
    output wire [15:0] mem_write_data,
    output wire        mem_write_en,

    input  wire        dma_active
);

    // ================================================================
    // RR16X ARCHITECTURAL STATE
    // ================================================================

    reg [15:0] R [0:7];

    reg [15:0] PC;
    reg [15:0] IR;

    reg [26:0] JR;
    reg [26:0] IVR;

    reg [10:0] PROGRAM_EAM;
    reg [10:0] DATA_EAM;

    // 256-entry call/interrupt stack.
    //
    // SP is 0..256:
    //   0     = empty
    //   1     = one entry
    //   256   = full
    //
    // The actual stack index is SP[7:0].
    reg [26:0] call_stack [0:255];
    reg  [8:0] stack_sp;

    reg interrupt_enable;
    reg halted;

    // ================================================================
    // DECODE
    // ================================================================

    wire [3:0] opcode = IR[15:12];
    wire       flag_M = IR[11];

    wire [2:0] reg_D = IR[10:8];

    wire       flag_LX = IR[7];
    wire [2:0] reg_X = IR[6:4];

    wire       flag_LY = IR[3];
    wire [2:0] reg_Y = IR[2:0];

    wire [3:0] condition_code = {flag_M, reg_D};

    // ================================================================
    // IMMEDIATE STORAGE
    // ================================================================

    reg [15:0] immediate_x;
    reg [15:0] immediate_y;

    wire [15:0] operand_x =
        flag_LX ? immediate_x : R[reg_X];

    wire [15:0] operand_y =
        flag_LY ? immediate_y : R[reg_Y];

    // ================================================================
    // FSM
    // ================================================================

    localparam
        S_FETCH       = 4'd0,
        S_DECODE      = 4'd1,
        S_IMM_X       = 4'd2,
        S_IMM_Y       = 4'd3,
        S_EXECUTE     = 4'd4,
        S_LDM_READ    = 4'd5,
        S_STM_WRITE   = 4'd6,
        S_COMMIT      = 4'd7,
        S_INTERRUPT   = 4'd8,
        S_HALT        = 4'd9;

    reg [3:0] state;
	wire [3:0] current_state = state;
    // ================================================================
    // INSTRUCTION ADDRESSING
    // ================================================================

    reg [15:0] instruction_pc;
    reg [15:0] next_pc;
    reg [16:0] instruction_length;

    // ================================================================
    // MEMORY TRANSACTION STATE
    // ================================================================

    reg [26:0] effective_address;

    // ================================================================
    // INTERRUPT STATE
    // ================================================================

    reg ext_interrupt_d;
    reg interrupt_pending;

    wire interrupt_edge =
        ext_interrupt && !ext_interrupt_d;

    // ================================================================
    // STACK HELPERS
    // ================================================================

    wire stack_empty =
        (stack_sp == 9'h000);

    wire stack_full =
        (stack_sp == 9'h100);

    // ================================================================
    // BRANCH CONDITION EVALUATION
    // ================================================================

    reg condition_met;

    always @* begin
        condition_met = 1'b0;

        case (condition_code)

            // Signed conditions
            4'h0:
                condition_met = 1'b0;

            4'h1:
                condition_met =
                    ($signed(operand_x) < $signed(operand_y));

            4'h2:
                condition_met =
                    (operand_x == operand_y);

            4'h3:
                condition_met =
                    ($signed(operand_x) <= $signed(operand_y));

            4'h4:
                condition_met =
                    ($signed(operand_x) > $signed(operand_y));

            4'h5:
                condition_met =
                    (operand_x != operand_y);

            4'h6:
                condition_met =
                    ($signed(operand_x) >= $signed(operand_y));

            4'h7:
                condition_met = 1'b1;

            // Unsigned conditions
            4'h8:
                condition_met =
                    (operand_x < operand_y);

            4'h9:
                condition_met =
                    (operand_x == operand_y);

            4'hA:
                condition_met =
                    (operand_x <= operand_y);

            4'hB:
                condition_met =
                    (operand_x > operand_y);

            4'hC:
                condition_met =
                    (operand_x != operand_y);

            4'hD:
                condition_met =
                    (operand_x >= operand_y);

            4'hE,
            4'hF:
                condition_met = 1'b0;

            default:
                condition_met = 1'b0;

        endcase
    end

    // ================================================================
    // MEMORY BUS
    // ================================================================

    assign mem_addr =
        (state == S_LDM_READ || state == S_STM_WRITE)
            ? effective_address
            :
        (state == S_IMM_X)
            ? {PROGRAM_EAM, instruction_pc + 16'd1}
            :
        (state == S_IMM_Y)
            ? {
                PROGRAM_EAM,
                instruction_pc +
                (flag_LX ? 16'd2 : 16'd1)
              }
            :
              {PROGRAM_EAM, PC};

    assign mem_write_en =
        (!dma_active &&
         state == S_STM_WRITE);

    assign mem_write_data =
        operand_x;

    // ================================================================
    // INTERRUPT EDGE / PENDING REGISTER
    // ================================================================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ext_interrupt_d <= 1'b0;
            interrupt_pending <= 1'b0;
        end
        else begin
            ext_interrupt_d <= ext_interrupt;

            // Capture an interrupt edge even if DMA is active.
            if (interrupt_edge && interrupt_enable)
                interrupt_pending <= 1'b1;

            // Clear when actually entering the handler.
            if (state == S_INTERRUPT)
                interrupt_pending <= 1'b0;
        end
    end

    // ================================================================
    // MAIN CPU
    // ================================================================

    integer i;

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            PC                 <= 16'h0000;
            IR                 <= 16'h0000;

            JR                 <= 27'h0000000;
            IVR                <= 27'h0000000;

            PROGRAM_EAM        <= 11'h000;
            DATA_EAM           <= 11'h000;

            immediate_x        <= 16'h0000;
            immediate_y        <= 16'h0000;

            instruction_pc     <= 16'h0000;
            next_pc            <= 16'h0000;
            instruction_length <= 17'd1;

            effective_address  <= 27'h0000000;

            stack_sp           <= 9'h000;

            interrupt_enable   <= 1'b1;
            halted             <= 1'b0;

            state              <= S_FETCH;

            for (i = 0; i < 8; i = i + 1)
                R[i] <= 16'h0000;

        end

        else if (!dma_active) begin

            case (state)

                // ====================================================
                // FETCH
                // ====================================================

                S_FETCH: begin

                    if (halted) begin
                        state <= S_HALT;
                    end

                    else if (interrupt_pending &&
                             interrupt_enable) begin

                        state <= S_INTERRUPT;

                    end

                    else begin

                        instruction_pc <= PC;

                        IR <= mem_read_data;

                        state <= S_DECODE;

                    end
                end

                // ====================================================
                // DECODE
                // ====================================================

                S_DECODE: begin

                    if (flag_LX)
                        state <= S_IMM_X;

                    else if (flag_LY)
                        state <= S_IMM_Y;

                    else
                        state <= S_EXECUTE;

                end

                // ====================================================
                // IMMEDIATE X
                // ====================================================

                S_IMM_X: begin

                    immediate_x <= mem_read_data;

                    if (flag_LY)
                        state <= S_IMM_Y;
                    else
                        state <= S_EXECUTE;

                end

                // ====================================================
                // IMMEDIATE Y
                // ====================================================

                S_IMM_Y: begin

                    immediate_y <= mem_read_data;

                    state <= S_EXECUTE;

                end

                // ====================================================
                // EXECUTE
                // ====================================================

                S_EXECUTE: begin

                    case (opcode)

                        // ------------------------------------------------
                        // 0x0 : EAM.SET
                        // ------------------------------------------------

                        4'h0: begin

                            if (flag_M)
                                IVR <= {DATA_EAM, operand_x};
                            else
                                DATA_EAM <= operand_x[10:0];

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x1 : ADD
                        // ------------------------------------------------

                        4'h1: begin

                            R[reg_D] <=
                                operand_x +
                                operand_y +
                                (flag_M ? 16'h0001 : 16'h0000);

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x2 : SUB
                        // ------------------------------------------------

                        4'h2: begin

                            R[reg_D] <=
                                operand_x -
                                operand_y -
                                (flag_M ? 16'h0001 : 16'h0000);

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x3 : AND / ANDN
                        // ------------------------------------------------

                        4'h3: begin

                            R[reg_D] <=
                                operand_x &
                                (flag_M ? ~operand_y : operand_y);

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x4 : OR / ORN
                        // ------------------------------------------------

                        4'h4: begin

                            R[reg_D] <=
                                operand_x |
                                (flag_M ? ~operand_y : operand_y);

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x5 : NOT / NEG
                        // ------------------------------------------------

                        4'h5: begin

                            if (flag_M)
                                R[reg_D] <=
                                    ~operand_x + 16'h0001;
                            else
                                R[reg_D] <=
                                    ~operand_x;

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x6 : XOR / XNOR
                        // ------------------------------------------------

                        4'h6: begin

                            R[reg_D] <=
                                operand_x ^
                                (flag_M ? ~operand_y : operand_y);

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x7 : SHL / ROL
                        // ------------------------------------------------

                        4'h7: begin : exec_shl

                            reg [3:0] amount;

                            amount = operand_y[3:0];

                            if (flag_M) begin

                                if (amount == 0) begin

                                    R[reg_D] <= operand_x;

                                end
                                else begin

                                    R[reg_D] <=
                                        (operand_x << amount) |
                                        (operand_x >> (16 - amount));

                                end

                            end
                            else begin

                                R[reg_D] <=
                                    operand_x << amount;

                            end

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x8 : SHR / ROR
                        // ------------------------------------------------

                        4'h8: begin : exec_shr

                            reg [3:0] amount;

                            amount = operand_y[3:0];

                            if (flag_M) begin

                                if (amount == 0) begin

                                    R[reg_D] <= operand_x;

                                end
                                else begin

                                    R[reg_D] <=
                                        (operand_x >> amount) |
                                        (operand_x << (16 - amount));

                                end

                            end
                            else begin

                                R[reg_D] <=
                                    operand_x >> amount;

                            end

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0x9 : LDM
                        // ------------------------------------------------

                        4'h9: begin

                            effective_address <=
                                {DATA_EAM, operand_x};

                            state <= S_LDM_READ;

                        end

                        // ------------------------------------------------
                        // 0xA : STM
                        // ------------------------------------------------

                        4'hA: begin

                            effective_address <=
                                {DATA_EAM, operand_x};

                            state <= S_STM_WRITE;

                        end

                        // ------------------------------------------------
                        // 0xB : STJ
                        // ------------------------------------------------

                        4'hB: begin

                            JR[15:0] <= operand_x;

                            if (!flag_M)
                                JR[26:16] <= PROGRAM_EAM;

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0xC : BRANCH / NIL
                        // ------------------------------------------------

                        4'hC: begin

                            // C000 = NIL
                            if (IR[14:8] == 7'h00) begin

                                state <= S_COMMIT;

                            end

                            else begin

                                // JMP or conditional branch
                                if (condition_code == 4'h7) begin

                                    PC <= JR[15:0];
                                    PROGRAM_EAM <= JR[26:16];

                                end

                                else if (condition_met) begin

                                    PC <= JR[15:0];
                                    PROGRAM_EAM <= JR[26:16];

                                end

                                state <= S_COMMIT;

                            end

                        end

                        // ------------------------------------------------
                        // 0xD : CAL
                        // ------------------------------------------------

                        4'hD: begin

                            if (!stack_full) begin

                                call_stack[stack_sp[7:0]] <=
                                    {
                                        PROGRAM_EAM,
                                        PC + instruction_length[15:0]
                                    };

                                stack_sp <= stack_sp + 9'd1;

                            end

                            PC <= operand_x;

                            if (flag_M)
                                PROGRAM_EAM <= DATA_EAM;

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0xE : RET / RET.C
                        // ------------------------------------------------

                        4'hE: begin

                            if (!stack_empty) begin

                                stack_sp <= stack_sp - 9'd1;

                                PC <=
                                    call_stack[
                                        stack_sp[7:0] - 8'd1
                                    ][15:0];

                                PROGRAM_EAM <=
                                    call_stack[
                                        stack_sp[7:0] - 8'd1
                                    ][26:16];

                            end

                            interrupt_enable <=
                                flag_M ? 1'b0 : 1'b1;

                            state <= S_COMMIT;

                        end

                        // ------------------------------------------------
                        // 0xF : HLT
                        // ------------------------------------------------

                        4'hF: begin

                            halted <= 1'b1;

                            state <= S_HALT;

                        end

                        default: begin

                            state <= S_COMMIT;

                        end

                    endcase

                end

                // ====================================================
                // LDM READ
                // ====================================================

                S_LDM_READ: begin

                    R[reg_D] <= mem_read_data;

                    if (flag_M && !flag_LX)
                        R[reg_X] <= R[reg_X] + 16'h0001;

                    state <= S_COMMIT;

                end

                // ====================================================
                // STM WRITE
                // ====================================================

                S_STM_WRITE: begin

                    state <= S_COMMIT;

                end

                // ====================================================
                // COMMIT
                // ====================================================

                S_COMMIT: begin

                    case (opcode)

                        4'hC: begin

                            if (IR[14:8] == 7'h00) begin

                                PC <=
                                    PC + instruction_length[15:0];

                            end

                            else if (condition_code == 4'h7) begin

                                // JMP: PC already updated.

                            end

                            else if (condition_met) begin

                                // Taken branch: PC already updated.

                            end

                            else begin

                                PC <=
                                    PC + instruction_length[15:0];

                            end

                        end

                        4'hD: begin

                            // CAL already loaded target PC.

                        end

                        4'hE: begin

                            // RET already loaded PC.

                        end

                        default: begin

                            PC <=
                                PC + instruction_length[15:0];

                        end

                    endcase

                    // STM post-increment.
                    if ((opcode == 4'hA) &&
                        flag_M &&
                        !flag_LX) begin

                        R[reg_X] <=
                            R[reg_X] + 16'h0001;

                    end

                    state <= S_FETCH;

                end

                // ====================================================
                // INTERRUPT ENTRY
                // ====================================================

                S_INTERRUPT: begin

                    if (!stack_full) begin

                        call_stack[stack_sp[7:0]] <=
                            {PROGRAM_EAM, PC};

                        stack_sp <= stack_sp + 9'd1;

                    end

                    PC <= IVR[15:0];

                    PROGRAM_EAM <= IVR[26:16];

                    interrupt_enable <= 1'b0;

                    state <= S_FETCH;

                end

                // ====================================================
                // HALT
                // ====================================================

                S_HALT: begin

                    if (interrupt_pending &&
                        interrupt_enable) begin

                        halted <= 1'b0;

                        state <= S_INTERRUPT;

                    end
                    else begin

                        state <= S_HALT;

                    end

                end

                default: begin

                    state <= S_FETCH;

                end

            endcase

        end

    end

    // ================================================================
    // INSTRUCTION LENGTH
    // ================================================================

    always @* begin

        instruction_length = 17'd1;

        if (flag_LX)
            instruction_length =
                instruction_length + 17'd1;

        if (flag_LY)
            instruction_length =
                instruction_length + 17'd1;

    end

endmodule



// ================================================================
// FP32 IEEE-754 BINARY32 COPROCESSOR
// ================================================================
//
// Memory map:
//
//   0x0 : Operand A low  16 bits
//   0x1 : Operand A high 16 bits
//   0x2 : Operand B low  16 bits
//   0x3 : Operand B high 16 bits
//
//   0x4 : Control
//         [1:0] operation
//               00 = ADD
//               01 = SUB
//               10 = MUL
//               11 = DIV
//         [2]   START
//
//   0x5 : Result low  16 bits
//   0x6 : Result high 16 bits
//
//   0x7 : Status
//         [0] divide by zero
//         [1] overflow
//         [2] underflow
//         [3] invalid operation
//
// ================================================================

module fp32_coprocessor (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [3:0]  addr,
    input  wire [15:0] din,
    input  wire        write_en,

    output reg  [15:0] dout,
    output reg         busy
);

// ================================================================
// MEMORY-MAPPED STATE
// ================================================================

reg [31:0] operand_a;
reg [31:0] operand_b;
reg [31:0] result;

reg [3:0] control_reg;

// [0] divide-by-zero
// [1] overflow
// [2] underflow
// [3] invalid
reg [3:0] status_reg;

// ================================================================
// FSM
// ================================================================

localparam
    STATE_IDLE = 2'd0,
    STATE_EXEC = 2'd1,
    STATE_DONE = 2'd2;

reg [1:0] state;

// ================================================================
// FUNCTION: SHIFT RIGHT WITH STICKY
// ================================================================

function [26:0] shift_right_sticky;

    input [26:0] value;
    input integer amount;

    reg sticky;
    integer k;

    begin

        sticky = 1'b0;

        if (amount <= 0) begin

            shift_right_sticky = value;

        end
        else if (amount >= 27) begin

            for (k = 0; k < 27; k = k + 1)
                sticky = sticky | value[k];

            shift_right_sticky = 27'h0000000;
            shift_right_sticky[0] = sticky;

        end
        else begin

            shift_right_sticky = value >> amount;

            for (k = 0; k < 27; k = k + 1) begin

                if (k < amount)
                    sticky = sticky | value[k];

            end

            shift_right_sticky[0] =
                shift_right_sticky[0] | sticky;

        end

    end

endfunction

// ================================================================
// FUNCTION: PACK / ROUND FP32
// ================================================================

function [35:0] pack_fp32;

    input        sign_in;
    input integer exp_in;
    input [26:0] mant_in;
    input [3:0]  status_in;

    reg [26:0] mant;
    reg [23:0] sig24;
    reg [24:0] rounded_sig;

    reg round_up;
    reg inexact;

    reg [31:0] out;
    reg [3:0]  stat;

    integer exp_work;
    integer shift_amt;

    begin

        out  = 32'h00000000;
        stat = status_in;

        mant     = mant_in;
        exp_work = exp_in;

        // --------------------------------------------------------
        // Exact zero
        // --------------------------------------------------------

        if (mant == 27'h0000000) begin

            out = {
                sign_in,
                31'h00000000
            };

        end
        else begin

            // ----------------------------------------------------
            // Move tiny results into subnormal range.
            // ----------------------------------------------------

            if (exp_work <= 0) begin

                shift_amt = 1 - exp_work;

                mant = shift_right_sticky(
                    mant,
                    shift_amt
                );

                exp_work = 1;

            end

            // ----------------------------------------------------
            // Round-to-nearest-even.
            // ----------------------------------------------------

            round_up =
                mant[2] &&
                (
                    mant[1] ||
                    mant[0] ||
                    mant[3]
                );

            inexact =
                mant[2] ||
                mant[1] ||
                mant[0];

            sig24 = mant[26:3];

            if (round_up)
                rounded_sig =
                    {1'b0, sig24} + 25'd1;
            else
                rounded_sig =
                    {1'b0, sig24};

            // ----------------------------------------------------
            // Rounding overflow.
            // ----------------------------------------------------

            if (rounded_sig[24]) begin

                rounded_sig = 25'h1000000;
                exp_work = exp_work + 1;

            end

            // ----------------------------------------------------
            // Exponent overflow.
            // ----------------------------------------------------

            if (exp_work >= 255) begin

                out = {
                    sign_in,
                    8'hFF,
                    23'h000000
                };

                stat[1] = 1'b1;

            end

            // ----------------------------------------------------
            // Normal result.
            // ----------------------------------------------------

            else if (exp_work > 1) begin

                out = {
                    sign_in,
                    exp_work[7:0],
                    rounded_sig[22:0]
                };

            end

            // ----------------------------------------------------
            // Minimum-normal / subnormal region.
            // ----------------------------------------------------

            else begin

                if (rounded_sig[23]) begin

                    out = {
                        sign_in,
                        8'h01,
                        rounded_sig[22:0]
                    };

                end
                else begin

                    out = {
                        sign_in,
                        8'h00,
                        rounded_sig[22:0]
                    };

                    if (inexact)
                        stat[2] = 1'b1;

                end

            end

        end

        pack_fp32 = {
            stat,
            out
        };

    end

endfunction

// ================================================================
// FUNCTION: FP32 CALCULATE
// ================================================================

function [35:0] fp_calculate;

    input [31:0] a;
    input [31:0] b;
    input [1:0]  op;

    reg sign_a;
    reg sign_b;
    reg sign_b_eff;
    reg sign_res;

    reg [7:0] expa;
    reg [7:0] expb;

    reg [22:0] fra;
    reg [22:0] frb;

    reg [23:0] siga;
    reg [23:0] sigb;

    reg a_zero;
    reg b_zero;

    reg a_inf;
    reg b_inf;

    reg a_nan;
    reg b_nan;

    reg [26:0] ma;
    reg [26:0] mb;
    reg [26:0] mant;

    reg [27:0] sum;

    reg [47:0] product;

    reg [49:0] numerator;
    reg [49:0] quotient;
    reg [49:0] remainder;

    reg [3:0] stat;

    integer ea;
    integer eb;
    integer exp_work;
    integer diff;
    integer k;

    begin

        // --------------------------------------------------------
        // Decode operands
        // --------------------------------------------------------

        sign_a = a[31];
        sign_b = b[31];

        expa = a[30:23];
        expb = b[30:23];

        fra = a[22:0];
        frb = b[22:0];

        a_zero =
            (expa == 8'h00) &&
            (fra  == 23'h000000);

        b_zero =
            (expb == 8'h00) &&
            (frb  == 23'h000000);

        a_inf =
            (expa == 8'hFF) &&
            (fra  == 23'h000000);

        b_inf =
            (expb == 8'hFF) &&
            (frb  == 23'h000000);

        a_nan =
            (expa == 8'hFF) &&
            (fra != 23'h000000);

        b_nan =
            (expb == 8'hFF) &&
            (frb != 23'h000000);

        stat = 4'h0;

        // --------------------------------------------------------
        // Effective exponents
        // --------------------------------------------------------

        if (expa == 0)
            ea = 1;
        else
            ea = expa;

        if (expb == 0)
            eb = 1;
        else
            eb = expb;

        // --------------------------------------------------------
        // Effective significands
        // --------------------------------------------------------

        if (expa == 0)
            siga = {1'b0, fra};
        else
            siga = {1'b1, fra};

        if (expb == 0)
            sigb = {1'b0, frb};
        else
            sigb = {1'b1, frb};

        // ========================================================
        // NaN
        // ========================================================

        if (a_nan || b_nan) begin

            fp_calculate = {
                4'b1000,
                32'h7FC00000
            };

        end

        // ========================================================
        // ADD
        // ========================================================

        else if (op == 2'b00) begin

            if (a_inf && b_inf) begin

                if (sign_a != sign_b) begin

                    fp_calculate = {
                        4'b1000,
                        32'h7FC00000
                    };

                end
                else begin

                    fp_calculate = {
                        4'b0000,
                        sign_a,
                        8'hFF,
                        23'h000000
                    };

                end

            end
            else if (a_inf) begin

                fp_calculate = {
                    4'b0000,
                    sign_a,
                    8'hFF,
                    23'h000000
                };

            end
            else if (b_inf) begin

                fp_calculate = {
                    4'b0000,
                    sign_b,
                    8'hFF,
                    23'h000000
                };

            end
            else if (a_zero && b_zero) begin

                fp_calculate = {
                    4'b0000,
                    sign_a & sign_b,
                    31'h00000000
                };

            end
            else if (a_zero) begin

                fp_calculate = {
                    4'b0000,
                    b
                };

            end
            else if (b_zero) begin

                fp_calculate = {
                    4'b0000,
                    a
                };

            end
            else begin

                ma = {siga, 3'b000};
                mb = {sigb, 3'b000};

                if (ea > eb) begin

                    diff = ea - eb;

                    mb = shift_right_sticky(
                        mb,
                        diff
                    );

                    exp_work = ea;

                end
                else if (eb > ea) begin

                    diff = eb - ea;

                    ma = shift_right_sticky(
                        ma,
                        diff
                    );

                    exp_work = eb;

                end
                else begin

                    exp_work = ea;

                end

                if (sign_a == sign_b) begin

                    sum =
                        {1'b0, ma} +
                        {1'b0, mb};

                    sign_res = sign_a;

                    if (sum[27]) begin

                        mant = shift_right_sticky(
                            sum[27:1],
                            1
                        );

                        exp_work = exp_work + 1;

                    end
                    else begin

                        mant = sum[26:0];

                    end

                end
                else begin

                    if (ma > mb) begin

                        mant = ma - mb;
                        sign_res = sign_a;

                    end
                    else if (mb > ma) begin

                        mant = mb - ma;
                        sign_res = sign_b;

                    end
                    else begin

                        mant = 27'h0000000;
                        sign_res = 1'b0;

                    end

                    for (k = 0; k < 27; k = k + 1) begin

                        if ((mant != 0) &&
                            !mant[26] &&
                            (exp_work > 1)) begin

                            mant = mant << 1;
                            exp_work = exp_work - 1;

                        end

                    end

                end

                fp_calculate =
                    pack_fp32(
                        sign_res,
                        exp_work,
                        mant,
                        stat
                    );

            end

        end

        // ========================================================
        // SUB
        // ========================================================

        else if (op == 2'b01) begin

            sign_b_eff = ~sign_b;

            if (a_inf && b_inf) begin

                if (sign_a == sign_b) begin

                    fp_calculate = {
                        4'b1000,
                        32'h7FC00000
                    };

                end
                else begin

                    fp_calculate = {
                        4'b0000,
                        sign_a,
                        8'hFF,
                        23'h000000
                    };

                end

            end
            else if (a_inf) begin

                fp_calculate = {
                    4'b0000,
                    sign_a,
                    8'hFF,
                    23'h000000
                };

            end
            else if (b_inf) begin

                fp_calculate = {
                    4'b0000,
                    sign_b_eff,
                    8'hFF,
                    23'h000000
                };

            end
            else if (a_zero && b_zero) begin

                fp_calculate = {
                    4'b0000,
                    sign_a & ~sign_b,
                    31'h00000000
                };

            end
            else if (a_zero) begin

                fp_calculate = {
                    4'b0000,
                    ~sign_b,
                    b[30:0]
                };

            end
            else if (b_zero) begin

                fp_calculate = {
                    4'b0000,
                    a
                };

            end
            else begin

                ma = {siga, 3'b000};
                mb = {sigb, 3'b000};

                if (ea > eb) begin

                    diff = ea - eb;

                    mb = shift_right_sticky(
                        mb,
                        diff
                    );

                    exp_work = ea;

                end
                else if (eb > ea) begin

                    diff = eb - ea;

                    ma = shift_right_sticky(
                        ma,
                        diff
                    );

                    exp_work = eb;

                end
                else begin

                    exp_work = ea;

                end

                if (sign_a == sign_b_eff) begin

                    sum =
                        {1'b0, ma} +
                        {1'b0, mb};

                    sign_res = sign_a;

                    if (sum[27]) begin

                        mant = shift_right_sticky(
                            sum[27:1],
                            1
                        );

                        exp_work = exp_work + 1;

                    end
                    else begin

                        mant = sum[26:0];

                    end

                end
                else begin

                    if (ma > mb) begin

                        mant = ma - mb;
                        sign_res = sign_a;

                    end
                    else if (mb > ma) begin

                        mant = mb - ma;
                        sign_res = sign_b_eff;

                    end
                    else begin

                        mant = 27'h0000000;
                        sign_res = 1'b0;

                    end

                    for (k = 0; k < 27; k = k + 1) begin

                        if ((mant != 0) &&
                            !mant[26] &&
                            (exp_work > 1)) begin

                            mant = mant << 1;
                            exp_work = exp_work - 1;

                        end

                    end

                end

                fp_calculate =
                    pack_fp32(
                        sign_res,
                        exp_work,
                        mant,
                        stat
                    );

            end

        end

        // ========================================================
        // MUL
        // ========================================================

        else if (op == 2'b10) begin

            sign_res = sign_a ^ sign_b;

            if ((a_zero && b_inf) ||
                (a_inf && b_zero)) begin

                fp_calculate = {
                    4'b1000,
                    32'h7FC00000
                };

            end
            else if (a_inf || b_inf) begin

                fp_calculate = {
                    4'b0000,
                    sign_res,
                    8'hFF,
                    23'h000000
                };

            end
            else if (a_zero || b_zero) begin

                fp_calculate = {
                    4'b0000,
                    sign_res,
                    31'h00000000
                };

            end
            else begin

                product = siga * sigb;

                exp_work =
                    ea + eb - 127;

                if (product[47]) begin

                    mant = {
                        product[47:24],
                        product[23],
                        product[22],
                        |product[21:0]
                    };

                    exp_work = exp_work + 1;

                end
                else begin

                    mant = {
                        product[46:23],
                        product[22],
                        product[21],
                        |product[20:0]
                    };

                end

                for (k = 0; k < 27; k = k + 1) begin

                    if ((mant != 0) &&
                        !mant[26] &&
                        (exp_work > 1)) begin

                        mant = mant << 1;
                        exp_work = exp_work - 1;

                    end

                end

                fp_calculate =
                    pack_fp32(
                        sign_res,
                        exp_work,
                        mant,
                        stat
                    );

            end

        end

        // ========================================================
        // DIV
        // ========================================================

        else begin

            sign_res = sign_a ^ sign_b;

            if ((a_zero && b_zero) ||
                (a_inf && b_inf)) begin

                fp_calculate = {
                    4'b1000,
                    32'h7FC00000
                };

            end
            else if (b_zero) begin

                stat[0] = 1'b1;

                fp_calculate = {
                    stat,
                    sign_res,
                    8'hFF,
                    23'h000000
                };

            end
            else if (a_zero) begin

                fp_calculate = {
                    4'b0000,
                    sign_res,
                    31'h00000000
                };

            end
            else if (a_inf) begin

                fp_calculate = {
                    4'b0000,
                    sign_res,
                    8'hFF,
                    23'h000000
                };

            end
            else if (b_inf) begin

                fp_calculate = {
                    4'b0000,
                    sign_res,
                    31'h00000000
                };

            end
            else begin

                numerator =
                    {26'h0000000, siga} << 26;

                quotient =
                    numerator / sigb;

                remainder =
                    numerator % sigb;

                exp_work =
                    ea - eb + 127;

                if (quotient[26]) begin

                    mant = {
                        quotient[26:3],
                        quotient[2],
                        quotient[1],
                        quotient[0] |
                        (remainder != 0)
                    };

                end
                else begin

                    mant = {
                        quotient[25:2],
                        quotient[1],
                        quotient[0],
                        (remainder != 0)
                    };

                    exp_work = exp_work - 1;

                end

                for (k = 0; k < 27; k = k + 1) begin

                    if ((mant != 0) &&
                        !mant[26] &&
                        (exp_work > 1)) begin

                        mant = mant << 1;
                        exp_work = exp_work - 1;

                    end

                end

                fp_calculate =
                    pack_fp32(
                        sign_res,
                        exp_work,
                        mant,
                        stat
                    );

            end

        end

    end

endfunction

// ================================================================
// CALCULATION RESULT WIRE
// ================================================================
//
// Important:
//
// Do not write:
//
//     fp_calculate(...)[31:0]
//
// directly in the sequential block. Some Verilog/SystemVerilog
// compilers reject selecting bits directly from a function call.
//
// ================================================================

wire [35:0] fp_calculate_result;

assign fp_calculate_result =
    fp_calculate(
        operand_a,
        operand_b,
        control_reg[1:0]
    );

// ================================================================
// MEMORY-MAPPED WRITE INTERFACE
// ================================================================

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        operand_a   <= 32'h00000000;
        operand_b   <= 32'h00000000;
        control_reg <= 4'h0;

    end
    else begin

        if (write_en) begin

            case (addr)

                4'h0:
                    operand_a[15:0] <= din;

                4'h1:
                    operand_a[31:16] <= din;

                4'h2:
                    operand_b[15:0] <= din;

                4'h3:
                    operand_b[31:16] <= din;

                4'h4:
                    control_reg <= din[3:0];

                default:
                    begin
                    end

            endcase

        end
        else if (state == STATE_DONE) begin

            // Automatically clear START.

            control_reg[2] <= 1'b0;

        end

    end

end

// ================================================================
// MEMORY-MAPPED READ INTERFACE
// ================================================================

always @(*) begin

    case (addr)

        4'h0:
            dout = operand_a[15:0];

        4'h1:
            dout = operand_a[31:16];

        4'h2:
            dout = operand_b[15:0];

        4'h3:
            dout = operand_b[31:16];

        4'h4:
            dout = {
                8'h00,
                busy,
                control_reg
            };

        4'h5:
            dout = result[15:0];

        4'h6:
            dout = result[31:16];

        4'h7:
            dout = {
                12'h000,
                status_reg
            };

        default:
            dout = 16'h0000;

    endcase

end

// ================================================================
// MAIN FSM
// ================================================================

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        state      <= STATE_IDLE;
        busy       <= 1'b0;
        result     <= 32'h00000000;
        status_reg <= 4'h0;

    end
    else begin

        case (state)

            // ----------------------------------------------------
            // IDLE
            // ----------------------------------------------------

            STATE_IDLE: begin

                busy <= 1'b0;

                if (control_reg[2]) begin

                    busy  <= 1'b1;
                    state <= STATE_EXEC;

                end

            end

            // ----------------------------------------------------
            // EXECUTE
            // ----------------------------------------------------

            STATE_EXEC: begin

                // Use the intermediate 36-bit calculation result.

                result <= fp_calculate_result[31:0];

                status_reg <= fp_calculate_result[35:32];

                state <= STATE_DONE;

            end

            // ----------------------------------------------------
            // DONE
            // ----------------------------------------------------

            STATE_DONE: begin

                busy  <= 1'b0;
                state <= STATE_IDLE;

            end

            // ----------------------------------------------------
            // DEFAULT
            // ----------------------------------------------------

            default: begin

                busy  <= 1'b0;
                state <= STATE_IDLE;

            end

        endcase

    end

end

endmodule
