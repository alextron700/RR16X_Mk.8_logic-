// Code your design here
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

    // Mk.8.2 carry latch - set/cleared by every ADD/SUB/SHL/SHR (see
    // opcodes 0x1/0x2/0x7/0x8), consumed by ADD.C/SUB.C. Not saved
    // across interrupts by design (see spec discussion).
    reg carry_latch;

    reg [15:0] PC;
    reg [15:0] IR;

    reg [26:0] JR;
    reg [26:0] IVR;

    reg [10:0] PROGRAM_EAM;
    reg [10:0] DATA_EAM;

    // Hardware call / interrupt stack.
    // 256 entries, as required by the ISA.
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

    // Condition selector:
    //
    // M is the high bit of the condition nibble.
    //
    // 0-7 = signed
    // 8-D = unsigned
    // E-F = unused
    //
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

    // ================================================================
    // INSTRUCTION ADDRESSING
    // ================================================================

    // PC always points to the current instruction while S_EXECUTE
    // is active.
    //
    // next_pc is constructed after immediate acquisition.
    reg [15:0] instruction_pc;
    reg [15:0] next_pc;
    reg [16:0] instruction_length;

    // ================================================================
    // MEMORY TRANSACTION STATE
    // ================================================================

    reg [26:0] effective_address;

    // ================================================================
    // INTERRUPT EDGE DETECTION
    // ================================================================

    reg ext_interrupt_d;

    wire interrupt_edge =
        ext_interrupt && !ext_interrupt_d;

    // ================================================================
    // STACK HELPERS
    // ================================================================

    wire stack_empty = (stack_sp == 9'h00);

    // With an 8-bit SP, 0xFF is the final directly addressable entry.
    // Overflow/underflow behavior is implementation-defined by the ISA.
    wire stack_full = (stack_sp == 9'hFF);

    // ================================================================
    // BRANCH CONDITION EVALUATION
    // ================================================================

    reg condition_met;

    always @* begin
        condition_met = 1'b0;

        case (condition_code)

            // --------------------------------------------------------
            // Signed conditions
            // --------------------------------------------------------

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

            // --------------------------------------------------------
            // Unsigned conditions
            // --------------------------------------------------------

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

            // CE / CF unused.
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

    //
    // Program memory:
    //
    //   PROGRAM_EAM : PC
    //
    // Data memory:
    //
    //   DATA_EAM : effective_address[15:0]
    //

   assign mem_addr =
    (state == S_LDM_READ || state == S_STM_WRITE)
        ? effective_address
        :
    (state == S_IMM_X)
        ? {PROGRAM_EAM, instruction_pc + 16'd1}
        :
    (state == S_IMM_Y)
        ? {PROGRAM_EAM,
           instruction_pc + (flag_LX ? 16'd2 : 16'd1)}
        :
          {PROGRAM_EAM, PC};

    assign mem_write_en =
     (!dma_active &&
      state == S_STM_WRITE);

    assign mem_write_data =
        operand_y;

    // ================================================================
    // INTERRUPT EDGE REGISTER
    // ================================================================

    always @(posedge clk or posedge rst) begin
        if (rst)
            ext_interrupt_d <= 1'b0;
        else
            ext_interrupt_d <= ext_interrupt;
    end

    // ================================================================
    // MAIN CPU
    // ================================================================

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            PC               <= 16'h0000;
            IR               <= 16'h0000;

            JR               <= 27'h0000000;
            IVR              <= 27'h0000000;

            PROGRAM_EAM      <= 11'h000;
            DATA_EAM         <= 11'h000;

            immediate_x      <= 16'h0000;
            immediate_y      <= 16'h0000;

            instruction_pc   <= 16'h0000;
            next_pc          <= 16'h0000;
            instruction_length <= 17'd1;

            effective_address <= 27'h0000000;

            stack_sp         <= 9'h00;

            interrupt_enable <= 1'b1;

            carry_latch      <= 1'b0;

            halted           <= 1'b0;

            state            <= S_FETCH;

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
                    else if (interrupt_edge && interrupt_enable) begin
                        state <= S_INTERRUPT;
                    end
                    else begin

                        //
                        // PC is NOT incremented here.
                        //
                        // It remains the architectural address of
                        // this instruction until execution completes.
                        //

                        instruction_pc <= PC;

                        IR <= mem_read_data;

                        state <= S_DECODE;
                    end
                end

                // ====================================================
                // DECODE / IMMEDIATE FETCH
                // ====================================================

                S_DECODE: begin

                    //
                    // Immediate X is always fetched before immediate Y.
                    //

                    if (flag_LX)
                        state <= S_IMM_X;

                    else if (flag_LY)
                        state <= S_IMM_Y;

                    else
                        state <= S_EXECUTE;
                end

                S_IMM_X: begin

                    immediate_x <= mem_read_data;

                    if (flag_LY)
                        state <= S_IMM_Y;
                    else
                        state <= S_EXECUTE;
                end

                S_IMM_Y: begin

                    immediate_y <= mem_read_data;

                    state <= S_EXECUTE;
                end

                // ====================================================
                // EXECUTE
                // ====================================================

                S_EXECUTE: begin

                    case (opcode)

                        // =================================================
                        // 0x0 : EAM.SET
                        // =================================================

                        4'h0: begin
                            if (flag_M)
                                IVR <= {DATA_EAM, operand_x};
                            else
                                DATA_EAM <= operand_x[10:0];
                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x1 : ADD
                        // =================================================

                        4'h1: begin

                            reg [16:0] add_result;

                            add_result =
                                {1'b0, operand_x} +
                                {1'b0, operand_y} +
                                (flag_M ? {16'b0, carry_latch} : 17'b0);

                            R[reg_D]    <= add_result[15:0];
                            carry_latch <= add_result[16];

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x2 : SUB
                        // =================================================

                        4'h2: begin

                            reg [16:0] sub_result;

                            sub_result =
                                {1'b0, operand_x} -
                                {1'b0, operand_y} -
                                (flag_M ? {16'b0, carry_latch} : 17'b0);

                            R[reg_D]    <= sub_result[15:0];
                            carry_latch <= sub_result[16]; // 1 = underflow/borrow

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x3 : AND
                        // =================================================

                        4'h3: begin

                            R[reg_D] <=
                                operand_x &
                                (flag_M ? ~operand_y : operand_y);

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x4 : OR
                        // =================================================

                        4'h4: begin

                            R[reg_D] <=
                                operand_x |
                                (flag_M ? ~operand_y : operand_y);

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x5 : NOT
                        // =================================================

                        4'h5: begin

                            if (flag_M)
                                R[reg_D] <= ~operand_x + 16'h0001;
                            else
                                R[reg_D] <= ~operand_x;

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x6 : XOR
                        // =================================================

                        4'h6: begin

                            R[reg_D] <=
                                operand_x ^
                                (flag_M ? ~operand_y : operand_y);

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x7 : SHL / ROL
                        // =================================================

                        4'h7: begin

                            reg [3:0] amount;

                            amount = operand_y[3:0];

                            if (flag_M) begin

                                if (amount == 0)
                                    R[reg_D] <= operand_x;
                                else
                                    R[reg_D] <=
                                        (operand_x << amount) |
                                        (operand_x >> (16 - amount));

                            end
                            else begin

                                R[reg_D] <=
                                    operand_x << amount;

                                // Mk.8.2: carry_latch = last bit shifted
                                // out. For a left shift by N, that's bit
                                // (16-N) of the original value. amount==0
                                // means nothing shifted - latch holds.
                                if (amount != 0)
                                    carry_latch <= operand_x[16 - amount];

                            end

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x8 : SHR / ROR
                        // =================================================

                        4'h8: begin

                            reg [3:0] amount;

                            amount = operand_y[3:0];

                            if (flag_M) begin

                                if (amount == 0)
                                    R[reg_D] <= operand_x;
                                else
                                    R[reg_D] <=
                                        (operand_x >> amount) |
                                        (operand_x << (16 - amount));

                            end
                            else begin

                                R[reg_D] <=
                                    operand_x >> amount;

                                // Mk.8.2: carry_latch = last bit shifted
                                // out. For a right shift by N, that's bit
                                // (N-1) of the original value.
                                if (amount != 0)
                                    carry_latch <= operand_x[amount - 1];

                            end

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x9 : LDM
                        // =================================================

                        4'h9: begin

                            //
                            // Calculate EA BEFORE post-increment.
                            //

                            effective_address <=
                                {DATA_EAM, operand_x};

                            state <= S_LDM_READ;
                        end

                        // =================================================
                        // 0xA : STM
                        // =================================================

                      4'hA: begin
                            effective_address <= {DATA_EAM, operand_x};
                            state <= S_STM_WRITE;
                        end

                        // =================================================
                        // 0xB : STJ
                        // =================================================

                        4'hB: begin

                            //
                            // Architectural assumption:
                            //
                            // JR is 27 bits, while the source operand
                            // is 16 bits.
                            //
                            // We therefore preserve the current
                            // ProgramEAM and replace the low 16 bits.
                            //
                            // M = 1 additionally means "low 16 bits only",
                            // matching the latest ISA wording.
                            //

                            JR[15:0] <= operand_x;

                            if (!flag_M)
                                JR[26:16] <= PROGRAM_EAM;

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0xC : BRANCH / NIL
                        // =================================================

                        4'hC: begin

                            //
                            // C000 is NIL.
                            //

                            if (IR[14:8] == 7'h00) begin

                                //
                                // NIL
                                //
                                state <= S_COMMIT;

                            end
                            else begin

                                //
                                // C700 is JMP.
                                //
                                // Other valid C opcodes are conditions.
                                //

                                if (condition_code == 4'h7) begin

                                    PC <= JR[15:0];

                                    PROGRAM_EAM <= JR[26:16];

                                end
                                else if (condition_met) begin

                                    PC <= JR[15:0];

                                    PROGRAM_EAM <= JR[26:16];

                                end
                                else begin

                                    //
                                    // Not taken:
                                    // normal PC advancement occurs
                                    // in COMMIT.
                                    //

                                end

                                state <= S_COMMIT;
                            end
                        end

                        // =================================================
                        // 0xD : CAL
                        // =================================================

                        4'hD: begin

                            //
                            // Return address is the address immediately
                            // following all encoded immediate words.
                            //
                            // At this point we have not modified PC.
                            //

                            if (!stack_full) begin

                                call_stack[stack_sp[7:0]] <=
                                    {
                                        PROGRAM_EAM,
                                        PC + instruction_length[15:0]
                                    };

                                stack_sp <= stack_sp + 9'd1;

                            end

                            //
                            // Target comes from supplied operand.
                            //

                            PC <= operand_x;

                            //
                            // ISA wording:
                            // if M is disabled, ProgramEAM does not change.
                            //
                            // If M is enabled, use DATA_EAM as the target
                            // bank. This preserves the bank mechanism used
                            // by the existing design.
                            //

                            if (flag_M)
                                PROGRAM_EAM <= DATA_EAM;

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0xE : RET / RET.C
                        // =================================================

                        4'hE: begin

                            if (!stack_empty) begin

                                stack_sp <= stack_sp - 9'd1;

                                PC <=
                                    call_stack[stack_sp - 9'd1][15:0];

                                PROGRAM_EAM <=
                                    call_stack[stack_sp - 9'd1][26:16];

                            end

                            //
                            // E000 = RET => interrupts enabled
                            // E800 = RET.C => interrupts disabled
                            //
                            interrupt_enable <=
                                (IR[11] ? 1'b0 : 1'b1);

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0xF : HLT
                        // =================================================

                        4'hF: begin

                            halted <= 1'b1;

                            state <= S_HALT;
                        end

                        default: begin

                            //
                            // Undefined opcodes execute as NIL.
                            //

                            state <= S_COMMIT;
                        end

                    endcase
                end

                // ========================================================
                // LDM READ
                // ========================================================

                S_LDM_READ: begin

                    R[reg_D] <= mem_read_data;

                    //
                    // M + register address => post-increment.
                    //
                    // Immediate addresses are never incremented.
                    //

                    if (flag_M && !flag_LX)
                        R[reg_X] <= R[reg_X] + 16'h0001;

                    state <= S_COMMIT;
                end

                // ========================================================
                // COMMIT / NEXT PC
                // ========================================================

                S_COMMIT: begin

                    //
                    // The default path is the architectural
                    // post-instruction increment.
                    //
                    // Control-transfer instructions that explicitly
                    // changed PC are identified below.
                    //

                    case (opcode)

                        4'hC: begin

                            //
                            // Branch/JMP:
                            //
                            // A taken branch has already written PC,
                            // therefore suppress normal increment.
                            //
                            // We need to determine whether this was
                            // NIL (C000), JMP, or a conditional branch.
                            //

                            if (IR[14:8] == 7'h00) begin
                                PC <= PC + instruction_length[15:0];
                            end
                            else if (condition_code == 4'h7) begin
                                // JMP: PC already written.
                            end
                            else if (condition_met) begin
                                // Taken branch: PC already written.
                            end
                            else begin
                                // Not taken.
                                PC <= PC + instruction_length[15:0];
                            end
                        end

                        4'hD: begin

                            //
                            // CAL already supplied target PC.
                            //
                            // Suppress normal increment.
                            //

                        end

                        4'hE: begin

                            //
                            // RET already supplied return PC.
                            //
                            // Suppress normal increment.
                            //

                        end

                        default: begin

                            PC <=
                                PC + instruction_length[15:0];

                        end

                    endcase

                    //
                    // LDM/STM M post-increment is performed after
                    // the memory operation.
                    //

                    if (opcode == 4'hA) begin

                        if (flag_M && !flag_LX)
                            R[reg_X] <= R[reg_X] + 16'h0001;

                    end

                    //
                    // Continue to interrupt boundary.
                    //

                    state <= S_FETCH;
                end

                // ========================================================
                // INTERRUPT ENTRY
                // ========================================================

                S_INTERRUPT: begin

                    //
                    // Preserve the address of the NEXT instruction.
                    //
                    // Since PC is architectural and has not yet been
                    // advanced for the instruction currently being
                    // fetched, the interrupt is taken only between
                    // instructions, so PC is already the next PC here.
                    //

                    if (!stack_full) begin

                        call_stack[stack_sp] <=
                            {PROGRAM_EAM, PC};

                        stack_sp <= stack_sp + 9'd1;

                    end

                    PC <= IVR[15:0];

                    PROGRAM_EAM <= IVR[26:16];

                    interrupt_enable <= 1'b0;

                    state <= S_FETCH;
                end

                // ========================================================
                // HALT
                // ========================================================

                S_HALT: begin

                    //
                    // Wake behavior is implementation-defined.
                    //
                    // This implementation wakes on an interrupt edge
                    // when interrupts are enabled.
                    //

                    if (interrupt_edge && interrupt_enable) begin

                        halted <= 1'b0;

                        state <= S_INTERRUPT;

                    end
                    else begin

                        state <= S_HALT;

                    end
                end
                S_STM_WRITE: begin
                    state <= S_COMMIT;
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
    //
    // Must be determined after IR is known and before CAL needs the
    // return address.
    //
    // 1 word instruction
    // + immediate X
    // + immediate Y
    //

    always @* begin

        instruction_length = 17'd1;

        if (flag_LX)
            instruction_length = instruction_length + 17'd1;

        if (flag_LY)
            instruction_length = instruction_length + 17'd1;

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
// Arithmetic:
//   IEEE-754 binary32
//   round-to-nearest, ties-to-even
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

    // ============================================================
    // MEMORY-MAPPED STATE
    // ============================================================

    reg [31:0] operand_a;
    reg [31:0] operand_b;
    reg [31:0] result;

    reg [3:0] control_reg;

    // [0] div-by-zero
    // [1] overflow
    // [2] underflow
    // [3] invalid
    reg [3:0] status_reg;

    // Holds the packed {status[3:0], result[31:0]} from fp_calculate so we
    // only evaluate the function once per STATE_EXEC cycle, and so we're not
    // indexing directly off a function call's return value (unsupported by
    // Icarus, and risky for synthesis tool compatibility in general).
    reg [35:0] fp_result;

    // ============================================================
    // FSM
    // ============================================================

    localparam
        STATE_IDLE = 2'd0,
        STATE_EXEC = 2'd1,
        STATE_DONE = 2'd2;

    reg [1:0] state;

    // ============================================================
    // IEEE-754 HELPER
    // ============================================================

    //
    // Shift a 27-bit significand right while preserving sticky.
    //
    // Layout:
    //
    //   [26:3] = 24-bit significand
    //   [2]    = guard
    //   [1]    = round
    //   [0]    = sticky
    //
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

                shift_right_sticky = 27'h0;
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


    // ============================================================
    // PACK / ROUND
    // ============================================================
    //
    // Input:
    //
    //   sign
    //   biased exponent
    //   27-bit normalized significand
    //
    // Output:
    //
    //   {status[3:0], result[31:0]}
    //
    // ============================================================

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

            // ----------------------------------------------------
            // Exact zero
            // ----------------------------------------------------

            if (mant == 27'h0000000) begin

                out = {sign_in, 31'h00000000};

            end

            else begin

                // ------------------------------------------------
                // Move tiny results into the subnormal range.
                // ------------------------------------------------

                if (exp_work <= 0) begin

                    shift_amt = 1 - exp_work;

                    mant = shift_right_sticky(
                        mant,
                        shift_amt
                    );

                    exp_work = 1;

                end

                // ------------------------------------------------
                // Round-to-nearest-even.
                //
                // Increment if:
                //
                //   guard && (round || sticky || LSB)
                //
                // ------------------------------------------------

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
                    rounded_sig = {1'b0, sig24} + 25'd1;
                else
                    rounded_sig = {1'b0, sig24};

                // ------------------------------------------------
                // Rounding overflowed the significand:
                //
                // 1.111... + rounding
                //       ->
                // 10.000...
                // ------------------------------------------------

                if (rounded_sig[24]) begin

                    rounded_sig = 25'h1000000;
                    exp_work = exp_work + 1;

                end

                // ------------------------------------------------
                // Exponent overflow
                // ------------------------------------------------

                if (exp_work >= 255) begin

                    out = {
                        sign_in,
                        8'hFF,
                        23'h000000
                    };

                    stat[1] = 1'b1;

                end

                // ------------------------------------------------
                // Normal result
                // ------------------------------------------------

                else if (exp_work > 1) begin

                    out = {
                        sign_in,
                        exp_work[7:0],
                        rounded_sig[22:0]
                    };

                end

                // ------------------------------------------------
                // Minimum normal / subnormal region
                // ------------------------------------------------

                else begin

                    //
                    // exp_work == 1.
                    //
                    // If hidden bit is present, this is the
                    // minimum normal range.
                    //

                    if (rounded_sig[23]) begin

                        out = {
                            sign_in,
                            8'h01,
                            rounded_sig[22:0]
                        };

                    end

                    else begin

                        //
                        // Subnormal.
                        //

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


    // ============================================================
    // MAIN IEEE-754 CALCULATOR
    // ============================================================
    //
    // Returns:
    //
    //   [35:32] = status
    //   [31:0]  = result
    //
    // ============================================================

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

        reg [35:0] packed_val;

        integer ea;
        integer eb;
        integer exp_work;
        integer diff;
        integer k;

        begin

            // ----------------------------------------------------
            // Defaults
            // ----------------------------------------------------

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

            packed_val = 36'h0;

            // ----------------------------------------------------
            // Effective exponent.
            //
            // For zero/subnormal the working exponent is 1.
            // ----------------------------------------------------

            if (expa == 0)
                ea = 1;
            else
                ea = expa;

            if (expb == 0)
                eb = 1;
            else
                eb = expb;

            // ----------------------------------------------------
            // Effective significands.
            //
            // Normal:
            //     1.fraction
            //
            // Subnormal:
            //     0.fraction
            // ----------------------------------------------------

            if (expa == 0)
                siga = {1'b0, fra};
            else
                siga = {1'b1, fra};

            if (expb == 0)
                sigb = {1'b0, frb};
            else
                sigb = {1'b1, frb};


            // ====================================================
            // NaN INPUT
            // ====================================================

            if (a_nan || b_nan) begin

                fp_calculate = {
                    4'b1000,
                    32'h7FC00000
                };

            end

            // ====================================================
            // ADD
            // ====================================================

            else if (op == 2'b00) begin

                // ------------------------------------------------
                // Infinity
                // ------------------------------------------------

                if (a_inf && b_inf) begin

                    if (sign_a != sign_b) begin

                        // +Inf + -Inf = NaN

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

                // ------------------------------------------------
                // Zero
                // ------------------------------------------------

                else if (a_zero && b_zero) begin

                    //
                    // -0 + -0 = -0
                    // Otherwise +0.
                    //

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

                // ------------------------------------------------
                // Finite ADD
                // ------------------------------------------------

                else begin

                    ma = {siga, 3'b000};
                    mb = {sigb, 3'b000};

                    // Align smaller exponent.

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

                    // ------------------------------------------------
                    // Same sign: addition.
                    // ------------------------------------------------

                    if (sign_a == sign_b) begin

                        sum =
                            {1'b0, ma} +
                            {1'b0, mb};

                        sign_res = sign_a;

                        if (sum[27]) begin

                            //
                            // Carry:
                            //
                            // 10.xxxxx
                            //
                            // Shift right with sticky.
                            //

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

                    // ------------------------------------------------
                    // Opposite signs: magnitude subtraction.
                    // ------------------------------------------------

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

                            //
                            // Exact cancellation.
                            //
                            // Round-to-nearest-even gives +0.
                            //

                            mant = 27'h0000000;
                            sign_res = 1'b0;

                        end

                        //
                        // Normalize left.
                        //

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

            // ====================================================
            // SUB
            // ====================================================

            else if (op == 2'b01) begin

                //
                // A - B = A + (-B)
                //

                sign_b_eff = ~sign_b;

                // ------------------------------------------------
                // Infinity
                // ------------------------------------------------

                if (a_inf && b_inf) begin

                    if (sign_a == sign_b) begin

                        //
                        // Inf - Inf = NaN
                        //

                        fp_calculate = {
                            4'b1000,
                            32'h7FC00000
                        };

                    end
                    else begin

                        //
                        // +Inf - -Inf = +Inf
                        // -Inf - +Inf = -Inf
                        //

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

                // ------------------------------------------------
                // Zero
                // ------------------------------------------------

                else if (a_zero && b_zero) begin

                    //
                    // +0 - +0 = +0
                    // -0 - -0 = +0
                    // +0 - -0 = +0
                    // -0 - +0 = -0
                    //

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

                    // ------------------------------------------------
                    // A and -B have same sign -> add magnitudes.
                    // ------------------------------------------------

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

                    // ------------------------------------------------
                    // Different signs -> subtract magnitudes.
                    // ------------------------------------------------

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

            // ====================================================
            // MUL
            // ====================================================

            else if (op == 2'b10) begin

                sign_res = sign_a ^ sign_b;

                // ------------------------------------------------
                // 0 * Inf = NaN
                // ------------------------------------------------

                if ((a_zero && b_inf) ||
                    (a_inf && b_zero)) begin

                    fp_calculate = {
                        4'b1000,
                        32'h7FC00000
                    };

                end

                // ------------------------------------------------
                // Infinity
                // ------------------------------------------------

                else if (a_inf || b_inf) begin

                    fp_calculate = {
                        4'b0000,
                        sign_res,
                        8'hFF,
                        23'h000000
                    };

                end

                // ------------------------------------------------
                // Zero
                // ------------------------------------------------

                else if (a_zero || b_zero) begin

                    fp_calculate = {
                        4'b0000,
                        sign_res,
                        31'h00000000
                    };

                end

                else begin

                    //
                    // 24 x 24 = 48 bit exact product.
                    //

                    product = siga * sigb;

                    //
                    // Initial exponent.
                    //

                    exp_work =
                        ea + eb - 127;

                    //
                    // Product >= 2.0
                    //

                    if (product[47]) begin

                        mant = {
                            product[47:24],
                            product[23],
                            product[22],
                            |product[21:0]
                        };

                        exp_work = exp_work + 1;

                    end

                    //
                    // Product in [1.0, 2.0)
                    //

                    else begin

                        mant = {
                            product[46:23],
                            product[22],
                            product[21],
                            |product[20:0]
                        };

                    end

                    //
                    // A subnormal operand can result in a product
                    // whose leading bit is still zero.
                    //

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

            // ====================================================
            // DIV
            // ====================================================

            else begin

                sign_res = sign_a ^ sign_b;

                // ------------------------------------------------
                // 0 / 0 = NaN
                // Inf / Inf = NaN
                // ------------------------------------------------

                if ((a_zero && b_zero) ||
                    (a_inf && b_inf)) begin

                    fp_calculate = {
                        4'b1000,
                        32'h7FC00000
                    };

                end

                // ------------------------------------------------
                // finite non-zero / zero = Inf
                // ------------------------------------------------

                else if (b_zero) begin

                    stat[0] = 1'b1;

                    fp_calculate = {
                        stat,
                        sign_res,
                        8'hFF,
                        23'h000000
                    };

                end

                // ------------------------------------------------
                // zero / finite = zero
                // ------------------------------------------------

                else if (a_zero) begin

                    fp_calculate = {
                        4'b0000,
                        sign_res,
                        31'h00000000
                    };

                end

                // ------------------------------------------------
                // Inf / finite = Inf
                // ------------------------------------------------

                else if (a_inf) begin

                    fp_calculate = {
                        4'b0000,
                        sign_res,
                        8'hFF,
                        23'h000000
                    };

                end

                // ------------------------------------------------
                // finite / Inf = zero
                // ------------------------------------------------

                else if (b_inf) begin

                    fp_calculate = {
                        4'b0000,
                        sign_res,
                        31'h00000000
                    };

                end

                else begin

                    //
                    // Generate 27 useful quotient bits.
                    //
                    // 24-bit significand << 26 provides:
                    //
                    //   24 significant bits
                    //   + G
                    //   + R
                    //   + S
                    //
                    numerator =
                        {26'h0000000, siga} << 26;

                    quotient =
                        numerator / sigb;

                    remainder =
                        numerator % sigb;

                    //
                    // Initial exponent.
                    //

                    exp_work =
                        ea - eb + 127;

                    //
                    // quotient is either:
                    //
                    //   [1.x] or [0.1x]
                    //
                    // Normalize to [1.x].
                    //

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

                    //
                    // Handle subnormal operands/results.
                    //

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

    // ============================================================
    // MEMORY-MAPPED WRITE INTERFACE
    // ============================================================

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

                //
                // Automatically clear START.
                //

                control_reg[2] <= 1'b0;

            end

        end

    end


    // ============================================================
    // MEMORY-MAPPED READ INTERFACE
    // ============================================================

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


    // ============================================================
    // MAIN FSM
    // ============================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state      <= STATE_IDLE;
            busy       <= 1'b0;
            result     <= 32'h00000000;
            status_reg <= 4'h0;

        end
        else begin

            case (state)

                // ------------------------------------------------
                // IDLE
                // ------------------------------------------------

                STATE_IDLE: begin

                    busy <= 1'b0;

                    if (control_reg[2]) begin

                        busy  <= 1'b1;
                        state <= STATE_EXEC;

                    end

                end

                // ------------------------------------------------
                // EXECUTE
                // ------------------------------------------------

                STATE_EXEC: begin

                    //
                    // One deterministic arithmetic transaction.
                    //

                    // Blocking assign: fp_result is a same-cycle scratch
                    // value, not a pipeline register, so it must resolve
                    // immediately within this always-block evaluation
                    // rather than waiting for the next clock edge like the
                    // non-blocking assigns below.
                    fp_result =
                        fp_calculate(
                            operand_a,
                            operand_b,
                            control_reg[1:0]
                        );

                    result     <= fp_result[31:0];
                    status_reg <= fp_result[35:32];

                    state <= STATE_DONE;

                end

                // ------------------------------------------------
                // DONE
                // ------------------------------------------------

                STATE_DONE: begin

                    busy  <= 1'b0;
                    state <= STATE_IDLE;

                end

                default: begin

                    busy  <= 1'b0;
                    state <= STATE_IDLE;

                end

            endcase

        end

    end

endmodule
