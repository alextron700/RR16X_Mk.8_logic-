// Code your design here
module gateway_drug_cpu (
    input wire clk,
    input wire rst,
    input wire ext_interrupt,
    output wire [26:0] mem_addr,
    input wire [15:0] mem_read_data,
    output wire [15:0] mem_write_data,
    output wire        mem_write_en,
    input wire dma_active
);
  
    // --- Internal CPU Registers ---
    reg [26:0] IVR;
    reg        interrupt_mask;
    reg [15:0] R[0:7];
    reg [15:0] PC;
    reg [15:0] IR;
    reg [26:0] JR;
    reg [26:0] shadow_stack[0:255];
    reg [7:0]  shadow_sp;

    // --- Banking Modules ---
    reg [10:0] PROGRAM_EAM;
    reg [10:0] DATA_EAM;

    // --- State Vectors ---
    localparam STATE_FETCH            = 3'd0,
               STATE_DECODE           = 3'd1,
               STATE_FETCH_IMMX       = 3'd2,
               STATE_FETCH_IMMY       = 3'd3,
               STATE_EXECUTE          = 3'd4,
               STATE_LDM_WRITEBACK    = 3'd5,
               STATE_INT_CHECK        = 3'd6;
               
    reg [2:0] current_state;
    reg [15:0] immediate_x;
    reg [15:0] immediate_y;

    // --- Explicit Bus Bit Slicing Wires ---
    wire [3:0] opcode  = IR[15:12];
    wire        flag_M  = IR[11];
    wire [2:0] reg_D   = IR[10:8];
    wire        flag_LX = IR[7];
    wire [2:0] reg_X   = IR[6:4];
    wire        flag_LY = IR[3];
    wire [2:0] reg_Y   = IR[2:0];
    
    wire [7:0] shadow_sp_dec = shadow_sp - 8'd1;

    // --- Edge Detection Hardware Trigger ---
    reg ext_interrupt_r;
    wire interrupt_trigger = (ext_interrupt && !ext_interrupt_r); 

    always @(posedge clk or posedge rst) begin
        if (rst) ext_interrupt_r <= 1'b0;
        else     ext_interrupt_r <= ext_interrupt;
    end

    // --- Safe Scope Isolation for Multiplexed Operands ---
    wire [15:0] opX = (flag_LX ? immediate_x : R[reg_X]);
    wire [15:0] opY = (flag_LY ? immediate_y : R[reg_Y]);
    wire [3:0]  jump_cond = {flag_M, reg_D};

    // --- 16-Condition Branch Array Evaluation Block ---
    reg condition_met; 
     always_comb begin
        if (opcode == 4'hC) begin
            case (jump_cond)
                4'h0: condition_met = 1'b0;
                4'h1: condition_met = ($signed(opX) <  $signed(opY));
                4'h2: condition_met = (opX == opY);
                4'h3: condition_met = ($signed(opX) <= $signed(opY));
                4'h4: condition_met = ($signed(opX) >  $signed(opY));
                4'h5: condition_met = (opX != opY);
                4'h6: condition_met = ($signed(opX) >= $signed(opY));
                4'h7: condition_met = 1'b1;
                4'h8: condition_met = (opX < opY);
                4'h9: condition_met = (opX == opY);
                4'hA: condition_met = (opX <= opY);
                4'hB: condition_met = (opX > opY);
                4'hC: condition_met = (opX != opY);
                4'hD: condition_met = (opX >= opY);
                4'hE: condition_met = (opX > opY);
                4'hF: condition_met = (opX > opY);
                default: condition_met = 1'b0;
            endcase
        end else begin
            condition_met = 1'b0;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            PC             <= 16'h0000;
            IR             <= 16'h0000;
            JR             <= 27'h0000000;
            IVR            <= 27'h0000000;
            shadow_sp      <= 8'h00;
            PROGRAM_EAM    <= 11'h000;
            DATA_EAM       <= 11'h000;
            current_state  <= STATE_FETCH;
            immediate_x    <= 16'h0000;
            immediate_y    <= 16'h0000;
            interrupt_mask <= 1'b0;
        end else begin
            if (!dma_active) begin
                case (current_state)
                    STATE_FETCH: begin
                        if (interrupt_trigger && !interrupt_mask) begin
                            // Edge verified! Capture a clean return address snapshot before PC increments!
                            shadow_stack[shadow_sp] <= {PROGRAM_EAM, PC};
                            shadow_sp               <= shadow_sp + 8'd1;
                            
                            PC          <= IVR[15:0];
                            PROGRAM_EAM <= IVR[26:16];
                            
                            interrupt_mask <= 1'b1;        // Lock out nested interrupts
                            current_state  <= STATE_FETCH; // Re-enter fetch to grab the first ISR instruction
                        end else begin
                            // Standard sequential fetch operation
                            IR            <= mem_read_data;
                            PC            <= PC + 16'h1; 
                            current_state <= STATE_DECODE;
                        end
                    end
                    STATE_DECODE: begin
                        if (flag_LX)      current_state <= STATE_FETCH_IMMX;
                        else if (flag_LY) current_state <= STATE_FETCH_IMMY;
                        else              current_state <= STATE_EXECUTE;
                    end
                    STATE_FETCH_IMMX: begin
                        immediate_x   <= mem_read_data;
                        PC            <= PC + 16'h1;
                        if (flag_LY) current_state <= STATE_FETCH_IMMY;
                        else         current_state <= STATE_EXECUTE;
                    end
                    STATE_FETCH_IMMY: begin
                        immediate_y   <= mem_read_data;
                        PC            <= PC + 16'h1;
                        current_state <= STATE_EXECUTE;
                    end
                    STATE_EXECUTE: begin
                        if (opcode == 4'h0) begin
                            if (flag_M) IVR <= {DATA_EAM, opX};
                            else        DATA_EAM <= opX[10:0];
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h1) begin
                            R[reg_D] <= opX + opY + (flag_M ? 16'h1 : 16'h0);
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h2) begin
                            R[reg_D] <= opX - opY - (flag_M ? 16'h1 : 16'h0);
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h3) begin
                            R[reg_D] <= opX & (flag_M ? ~opY : opY);
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h4) begin
                            R[reg_D] <= opX | (flag_M ? ~opY : opY);
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h5) begin
                            R[reg_D] <= flag_M ? (~opX + 16'h1) : ~opX;
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h6) begin
                            R[reg_D] <= opX ^ (flag_M ? ~opY : opY);
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h7) begin
                            R[reg_D] <= flag_M ? ((opX << opY) | (opX >> (16'd16 - opY))) : (opX << opY);
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h8) begin
                            R[reg_D] <= flag_M ? ($signed(opX) >>> opY) : (opX >> opY);
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'h9) begin
                            current_state <= STATE_LDM_WRITEBACK;
                            if (flag_M && !flag_LX) R[reg_X] <= R[reg_X] + 16'h1;
                        end
                        else if (opcode == 4'hA) begin
                            current_state <= STATE_INT_CHECK;
                            if (flag_M && !flag_LX) R[reg_X] <= R[reg_X] + 16'h1;
                        end
                        else if (opcode == 4'hB) begin
                            JR[15:0]  <= opX;
                            JR[26:16] <= flag_M ? PROGRAM_EAM : DATA_EAM;
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'hC) begin
                            if (condition_met) begin
                                PC          <= JR[15:0];
                                PROGRAM_EAM <= JR[26:16];
                            end
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'hD) begin
                            shadow_stack[shadow_sp] <= {PROGRAM_EAM, PC};
                            shadow_sp <= shadow_sp + 8'd1;
                            PC <= opX;
                            if (!flag_M) PROGRAM_EAM <= DATA_EAM;
                            current_state <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'hE) begin
                            shadow_sp      <= shadow_sp_dec;
                            PC             <= shadow_stack[shadow_sp_dec][15:0];
                            PROGRAM_EAM    <= shadow_stack[shadow_sp_dec][26:16];
                            interrupt_mask <= flag_M ? 1'b1 : 1'b0;
                            current_state  <= STATE_INT_CHECK;
                        end
                        else if (opcode == 4'hF) begin
                            if (flag_M && interrupt_trigger && !interrupt_mask)
                                current_state <= STATE_INT_CHECK;
                            else
                                current_state <= STATE_EXECUTE;
                        end
                        else begin
                            current_state <= STATE_INT_CHECK;
                        end
                    end
                    STATE_LDM_WRITEBACK: begin
                        R[reg_D]      <= mem_read_data;
                        current_state <= STATE_INT_CHECK;
                    end
                    STATE_INT_CHECK: begin
                        current_state <= STATE_FETCH;
                    end
                    default: current_state <= STATE_FETCH;
                endcase
            end
        end
    end

    reg [15:0] mem_offset_calc;
    always @* begin
        if (current_state == STATE_EXECUTE && (opcode == 4'h9 || opcode == 4'hA))
            mem_offset_calc = opX;
        else
            mem_offset_calc = PC;
    end

    assign mem_addr = (current_state == STATE_EXECUTE && (opcode == 4'h9 || opcode == 4'hA)) ? 
                      {DATA_EAM, mem_offset_calc} : {PROGRAM_EAM, mem_offset_calc};
    assign mem_write_en   = (current_state == STATE_EXECUTE && opcode == 4'hA);
    assign mem_write_data = (current_state == STATE_EXECUTE && opcode == 4'hA) ? R[reg_D] : 
                        (flag_LY) ? immediate_y : R[reg_Y];
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
