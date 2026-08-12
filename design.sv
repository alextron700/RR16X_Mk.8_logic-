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

    reg [15:0] PC;
    reg [15:0] IR;

    reg [26:0] JR;
    reg [26:0] IVR;

    reg [10:0] PROGRAM_EAM;
    reg [10:0] DATA_EAM;

    // Hardware call / interrupt stack.
    // 256 entries, as required by the ISA.
    reg [26:0] call_stack [0:255];
    reg  [7:0] stack_sp;

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
        S_COMMIT      = 4'd6,
        S_INTERRUPT   = 4'd7,
        S_HALT        = 4'd8;

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

    wire stack_empty = (stack_sp == 8'h00);

    // With an 8-bit SP, 0xFF is the final directly addressable entry.
    // Overflow/underflow behavior is implementation-defined by the ISA.
    wire stack_full = (stack_sp == 8'hFF);

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
        (state == S_LDM_READ) ||
        (state == S_EXECUTE && opcode == 4'hA)
            ? {DATA_EAM, effective_address[15:0]}
            : {PROGRAM_EAM, PC};

    // STM only.
    assign mem_write_en =
        (!dma_active &&
         state == S_EXECUTE &&
         opcode == 4'hA);

    // IMPORTANT:
    //
    // STM Address,Rx uses the source register selected by the
    // architectural operand, NOT Rd.
    //
    // For the encoded N,R,R form used by the assembler:
    //
    //   STM address, Rx
    //
    // reg_X is the source register.
    //
    assign mem_write_data =
        R[reg_X];

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

            stack_sp         <= 8'h00;

            interrupt_enable <= 1'b1;

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

                            //
                            // EAM.SET Rx
                            //
                            // ISA: DATA EAM = Rx
                            //

                            DATA_EAM <= operand_x[10:0];

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x1 : ADD
                        // =================================================

                        4'h1: begin

                            R[reg_D] <=
                                operand_x +
                                operand_y +
                                (flag_M ? 16'h0001 : 16'h0000);

                            state <= S_COMMIT;
                        end

                        // =================================================
                        // 0x2 : SUB
                        // =================================================

                        4'h2: begin

                            R[reg_D] <=
                                operand_x -
                                operand_y -
                                (flag_M ? 16'h0001 : 16'h0000);

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

                            //
                            // Address calculation happens first.
                            //
                            // Source is R[reg_X].
                            //

                            effective_address <=
                                {DATA_EAM, operand_x};

                            state <= S_COMMIT;
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

                                call_stack[stack_sp] <=
                                    {
                                        PROGRAM_EAM,
                                        PC + instruction_length[15:0]
                                    };

                                stack_sp <= stack_sp + 8'd1;

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

                                stack_sp <= stack_sp - 8'd1;

                                PC <=
                                    call_stack[stack_sp - 8'd1][15:0];

                                PROGRAM_EAM <=
                                    call_stack[stack_sp - 8'd1][26:16];

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

                        stack_sp <= stack_sp + 8'd1;

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
module fp32_coprocessor (
    input wire clk,
    input wire rst_n,
    input wire [3:0] addr,         // Local 4-bit register address offset
    input wire [15:0] din,         // Data in from CPU Data EAM bus
    input wire write_en,           // CPU writing to coprocessor
    output reg [15:0] dout,        // Data out to CPU Data EAM bus
    output reg busy                // Connected to Interrupt / flagless loop
);

    // --- Internal Staging Storage ---
    reg [31:0] operand_a;
    reg [31:0] operand_b;
    reg [31:0] result;
    reg [3:0]  control_reg;        // Bit [1:0] Opcode: 0=ADD, 1=SUB, 2=MUL, 3=DIV. Bit [2]: Start trigger
    reg [3:0]  status_reg;         // Error flags: Div-by-zero, Overflow, Underflow

    // --- FPU FSM States ---
    localparam STATE_IDLE       = 3'd0,
               STATE_UNPACK     = 3'd1,
               STATE_ALIGN      = 3'd2,
               STATE_EXECUTE    = 3'd3,
               STATE_NORMALIZE  = 3'd4,
               STATE_WRITE_RES  = 3'd5;
               
    reg [2:0] current_state;
    
    // --- IEEE 754 Internal Breakdowns ---
    // Floating point fields: Sign (1 bit), Exponent (8 bits), Mantissa/Significand (23 bits)
    reg sign_a, sign_b, sign_res;
    reg [7:0] exp_a, exp_b, exp_res;
    reg [24:0] mant_a, mant_b;     // 23 bits + 1 implicit leading bit + 1 guard bit
    reg [47:0] mant_large;         // Used for wide multiplication/division calculation

    // --- Memory-Mapped Write Interface ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operand_a   <= 32'h0;
            operand_b   <= 32'h0;
            control_reg <= 4'h0;
        end else if (write_en) begin
            case (addr)
                4'h0: operand_a[15:0]  <= din; // A Low
                4'h1: operand_a[31:16] <= din; // A High
                4'h2: operand_b[15:0]  <= din; // B Low
                4'h3: operand_b[31:16] <= din; // B High
                4'h4: control_reg      <= din[3:0]; // Command Trigger
            endcase
        end else if (current_state == STATE_WRITE_RES) begin
            control_reg[2] <= 1'b0; // Auto-clear the start execution trigger bit
        end
    end

    // --- Memory-Mapped Read Interface ---
    always @(*) begin
        case (addr)
            4'h0: dout = operand_a[15:0];
            4'h1: dout = operand_a[31:16];
            4'h2: dout = operand_b[15:0];
            4'h3: dout = operand_b[31:16];
            4'h4: dout = {11'h0, busy, control_reg};
            4'h5: dout = result[15:0];  // Result Low
            4'h6: dout = result[31:16]; // Result High
            default: dout = 16'h0000;
        endcase
    end

    // --- Multi-Cycle Math Core FSM ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_IDLE;
            busy          <= 1'b0;
            result        <= 32'h0;
            status_reg    <= 4'h0;
        end else begin
            case (current_state)
                
                STATE_IDLE: begin
                    if (control_reg[2]) begin // Start bit set
                        busy          <= 1'b1;
                        current_state <= STATE_UNPACK;
                    end else begin
                        busy          <= 1'b0;
                    end
                end

                STATE_UNPACK: begin
                    // Unpack IEEE 754 structures
                    sign_a <= operand_a[31];
                    sign_b <= operand_b[31];
                    exp_a  <= operand_a[30:23];
                    exp_b  <= operand_b[30:23];
                    
                    // Append implicit bit (if exponent != 0, leading 1 is assumed)
                    mant_a <= (operand_a[30:23] == 8'h0) ? {2'b0, operand_a[22:0]} : {2'b01, operand_a[22:0]};
                    mant_b <= (operand_b[30:23] == 8'h0) ? {2'b0, operand_b[22:0]} : {2'b01, operand_b[22:0]};
                    
                    current_state <= STATE_ALIGN;
                end

                STATE_ALIGN: begin
                    // Align exponents for ADD/SUB operations
                    if (control_reg[1:0] == 2'b00 || control_reg[1:0] == 2'b01) begin
                        if (exp_a > exp_b) begin
                            mant_b   <= mant_b >> (exp_a - exp_b);
                            exp_res  <= exp_a;
                            current_state <= STATE_EXECUTE;
                        end else if (exp_b > exp_a) begin
                            mant_a   <= mant_a >> (exp_b - exp_a);
                            exp_res  <= exp_b;
                            current_state <= STATE_EXECUTE;
                        end else begin
                            exp_res  <= exp_a;
                            current_state <= STATE_EXECUTE;
                        end
                    end else begin
                        // MUL/DIV pass directly to execution
                        current_state <= STATE_EXECUTE;
                    end
                end

                STATE_EXECUTE: begin
                    case (control_reg[1:0])
                        2'b00: begin // ADD
                            sign_res <= sign_a; // Simplification for matching signs
                            mant_large <= mant_a + mant_b;
                        end
                        2'b01: begin // SUB
                            sign_res <= (mant_a >= mant_b) ? sign_a : !sign_a;
                            mant_large <= (mant_a >= mant_b) ? (mant_a - mant_b) : (mant_b - mant_a);
                        end
                        2'b10: begin // MUL (Fixed Syntax Token)
                            sign_res   <= sign_a ^ sign_b;
                            exp_res    <= (exp_a + exp_b) - 8'd127; // Subtract bias
                            mant_large <= mant_a * mant_b;
                        end
                        2'b11: begin // DIV (Fixed Syntax Token)
                            sign_res <= sign_a ^ sign_b;
                            exp_res  <= (exp_a - exp_b) + 8'd127; // Add bias
                            if (operand_b[30:0] == 31'h0) begin
                                status_reg[0] <= 1'b1; // Division by zero flag
                                mant_large    <= 48'hFFFFFFFFFFFF;
                            end else begin
                                mant_large    <= (mant_a << 23) / mant_b;
                            end
                        end
                    endcase
                    current_state <= STATE_NORMALIZE;
                end

                STATE_NORMALIZE: begin
                    // Basic normalization handling (clamping bit boundaries)
                    if (control_reg[1:0] == 2'b10) begin // (Fixed Syntax Token) Handling wide multiply resolution
                        if (mant_large[47]) begin
                            result[22:0] <= mant_large[45:23];
                            result[30:23] <= exp_res + 1;
                        end else begin
                            result[22:0] <= mant_large[44:22];
                            result[30:23] <= exp_res;
                        end
                    end else begin // Handling regular Add/Sub/Div bounds
                        if (mant_large[24]) begin // Mantissa overflowed past implicit bit
                            result[22:0]  <= mant_large[23:1];
                            result[30:23] <= exp_res + 1;
                        end else begin
                            result[22:0]  <= mant_large[22:0];
                            result[30:23] <= exp_res;
                        end
                    end
                    result[31]    <= sign_res;
                    current_state <= STATE_WRITE_RES;
                end

                STATE_WRITE_RES: begin
                    busy          <= 1'b0;
                    current_state <= STATE_IDLE;
                end
                
                default: current_state <= STATE_IDLE;
            endcase
        end
    end

endmodule
