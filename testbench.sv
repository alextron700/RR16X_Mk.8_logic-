`timescale 1ns/1ps

// ============================================================================
// GATEWAY DRUG CPU - COMPLETE SYSTEM TESTBENCH
// Icarus Verilog 12.x / SystemVerilog
// ============================================================================

module gateway_drug_tb;

    // =========================================================================
    // CLOCK / RESET
    // =========================================================================

    reg clk;
    reg rst;

    initial clk = 1'b0;
    always #5 clk = ~clk;


    // =========================================================================
    // CPU BUS
    // =========================================================================

    wire [26:0] mem_addr;
    wire [15:0] mem_read_data;
    wire [15:0] mem_write_data;
    wire        mem_write_en;

    wire dma_active;


    // =========================================================================
    // INTERRUPTS
    // =========================================================================

    reg        tb_interrupt;
    reg [26:0] tb_interrupt_vector;


    // =========================================================================
    // RAM
    // =========================================================================

    localparam integer RAM_WORDS     = 2048;
    localparam integer RAM_ADDR_BITS = 11;

    reg [15:0] ram_array [0:RAM_WORDS-1];

    integer i;

    wire ram_sel;

    assign ram_sel =
        (mem_addr < RAM_WORDS);

    reg [15:0] ram_read_word;

    always @(*) begin
        if (ram_sel === 1'b1)
            ram_read_word = ram_array[mem_addr[RAM_ADDR_BITS-1:0]];
        else
            ram_read_word = 16'h0000;
    end


    // =========================================================================
    // MEMORY MAP
    // =========================================================================

    localparam [26:0] VIRTUAL_UART_ADDR    = 27'h7FFFFFF;
    localparam [26:0] HARDWARE_TIMER_ADDR  = 27'h7FFFFFE;

    // MDU
    localparam [26:0] MDU_REG_A_ADDR       = 27'h7FFFFFD;
    localparam [26:0] MDU_REG_B_ADDR       = 27'h7FFFFFC;
    localparam [26:0] MDU_REG_RES_LO_ADDR  = 27'h7FFFFFB;
    localparam [26:0] MDU_REG_RES_HI_ADDR  = 27'h7FFFFFA;

    // FPU
    localparam [26:0] FPU_BASE_ADDR        = 27'h7FFFFD0;
    localparam [26:0] FPU_LAST_ADDR        = 27'h7FFFFD6;

    // VIC
    localparam [26:0] VIC_ENABLE_ADDR      = 27'h7FFFFF5;
    localparam [26:0] VIC_PENDING_ADDR     = 27'h7FFFFF4;
    localparam [26:0] VIC_VECTOR_BASE_ADDR = 27'h7FFFFF3;

    // DMA
    localparam [26:0] DMA_SRC_ADDR         = 27'h7FFFFF2;
    localparam [26:0] DMA_DST_ADDR         = 27'h7FFFFF1;
    localparam [26:0] DMA_CNT_ADDR         = 27'h7FFFFF0;
    localparam [26:0] DMA_SRC_BANK        = 27'h7FFFFEF;
    localparam [26:0] DMA_DST_BANK        = 27'h7FFFFEE;

    // INT32
    localparam [26:0] INT32_REG_A_LO_ADDR = 27'h7FFFFED;
    localparam [26:0] INT32_REG_A_HI_ADDR = 27'h7FFFFEC;
    localparam [26:0] INT32_REG_B_LO_ADDR = 27'h7FFFFEB;
    localparam [26:0] INT32_REG_B_HI_ADDR = 27'h7FFFFEA;
    localparam [26:0] INT32_CMD_ADDR      = 27'h7FFFFE9;
    localparam [26:0] INT32_RES_LO_ADDR   = 27'h7FFFFE8;
    localparam [26:0] INT32_RES_HI_ADDR   = 27'h7FFFFE7;


    // =========================================================================
    // HARDWARE TIMER
    // =========================================================================

    reg [15:0] hardware_timer;


    // =========================================================================
    // MDU
    // =========================================================================

    reg [15:0] mdu_param_a;
    reg [15:0] mdu_param_b;

    wire [31:0] mdu_product;

    assign mdu_product = mdu_param_a * mdu_param_b;


    // =========================================================================
    // VIC
    // =========================================================================

    reg [15:0] vic_enabled_channels;
    reg [15:0] vic_vector_base_ptr;

    wire [3:0] vic_hardware_inputs;
    wire [3:0] vic_active_requests;
    wire [1:0] vic_highest_priority;
    wire       vic_global_trigger;

    assign vic_hardware_inputs = {3'b000, tb_interrupt};

    assign vic_active_requests =
        vic_hardware_inputs &
        vic_enabled_channels[3:0];

    assign vic_highest_priority =
        (vic_active_requests & 4'b0001) ? 2'd0 :
        (vic_active_requests & 4'b0010) ? 2'd1 :
        (vic_active_requests & 4'b0100) ? 2'd2 :
        2'd3;

    assign vic_global_trigger =
        (vic_active_requests != 4'b0000);


    // =========================================================================
    // DMA
    // =========================================================================

    reg [26:0] dma_source_ptr;
    reg [26:0] dma_dest_ptr;
    reg [15:0] dma_word_counter;

    assign dma_active =
        (dma_word_counter != 16'h0000);


    // =========================================================================
    // INT32 COPROCESSOR
    // =========================================================================

    reg [15:0] int32_a_lo;
    reg [15:0] int32_a_hi;
    reg [15:0] int32_b_lo;
    reg [15:0] int32_b_hi;
    reg [2:0]  int32_cmd;

    wire [31:0] full_operand_a;
    wire [31:0] full_operand_b;

    reg [31:0] int32_result;

    assign full_operand_a = {int32_a_hi, int32_a_lo};
    assign full_operand_b = {int32_b_hi, int32_b_lo};

    always @(*) begin

        case (int32_cmd)

            3'd0:
                int32_result = full_operand_a + full_operand_b;

            3'd1:
                int32_result = full_operand_a - full_operand_b;

            3'd2:
                int32_result = full_operand_a << full_operand_b[4:0];

            3'd3:
                int32_result = full_operand_a >> full_operand_b[4:0];

            3'd4:
                int32_result = full_operand_a & full_operand_b;

            3'd5:
                int32_result = full_operand_a | full_operand_b;

            3'd6:
                int32_result = full_operand_a ^ full_operand_b;

            default:
                int32_result = 32'h00000000;

        endcase

    end


    // =========================================================================
    // FPU
    // =========================================================================

    wire        fpu_sel;
    wire [15:0] fpu_dout;
    wire        fpu_busy;

    assign fpu_sel =
        (mem_addr >= FPU_BASE_ADDR) &&
        (mem_addr <= FPU_LAST_ADDR);

    fp32_coprocessor fpu_uut (
        .clk      (clk),
        .rst_n    (!rst),
        .addr     (mem_addr[3:0]),
        .din      (mem_write_data),
        .write_en (mem_write_en && fpu_sel),
        .dout     (fpu_dout),
        .busy     (fpu_busy)
    );


    // =========================================================================
    // CPU
    // =========================================================================

    gateway_drug_cpu uut (
        .clk                  (clk),
        .rst                  (rst),
        .ext_interrupt        (tb_interrupt),
        .ext_interrupt_vector (tb_interrupt_vector),

        .mem_addr             (mem_addr),
        .mem_read_data        (mem_read_data),
        .mem_write_data       (mem_write_data),
        .mem_write_en         (mem_write_en),

        .dma_active           (dma_active)
    );


    // =========================================================================
    // MEMORY READ MUX
    // =========================================================================

    assign mem_read_data =
        (mem_addr == HARDWARE_TIMER_ADDR) ? hardware_timer :
        (mem_addr == MDU_REG_RES_LO_ADDR) ? mdu_product[15:0] :
        (mem_addr == MDU_REG_RES_HI_ADDR) ? mdu_product[31:16] :
        (mem_addr == VIC_PENDING_ADDR)    ? {12'h000, vic_active_requests} :
        (mem_addr == DMA_SRC_ADDR)        ? dma_source_ptr[15:0] :
        (mem_addr == DMA_DST_ADDR)        ? dma_dest_ptr[15:0] :
        (mem_addr == DMA_CNT_ADDR)        ? dma_word_counter :
        (mem_addr == INT32_REG_A_LO_ADDR) ? int32_a_lo :
        (mem_addr == INT32_REG_A_HI_ADDR) ? int32_a_hi :
        (mem_addr == INT32_REG_B_LO_ADDR) ? int32_b_lo :
        (mem_addr == INT32_REG_B_HI_ADDR) ? int32_b_hi :
        (mem_addr == INT32_RES_LO_ADDR)   ? int32_result[15:0] :
        (mem_addr == INT32_RES_HI_ADDR)   ? int32_result[31:16] :
        fpu_sel                           ? fpu_dout :
        ram_read_word;


    // =========================================================================
    // PERIPHERAL WRITE LOGIC
    // =========================================================================

    always @(posedge clk or posedge rst) begin

        if (rst) begin

            hardware_timer       <= 16'h0000;

            mdu_param_a          <= 16'h0000;
            mdu_param_b          <= 16'h0000;

            vic_enabled_channels <= 16'h0000;
            vic_vector_base_ptr  <= 16'h0000;

            dma_source_ptr       <= 27'h0000000;
            dma_dest_ptr         <= 27'h0000000;
            dma_word_counter     <= 16'h0000;

            int32_a_lo           <= 16'h0000;
            int32_a_hi           <= 16'h0000;
            int32_b_lo           <= 16'h0000;
            int32_b_hi           <= 16'h0000;
            int32_cmd             <= 3'd7;

        end
        else begin

            hardware_timer <= hardware_timer + 16'h0001;

            // -------------------------------------------------------------
            // DMA
            // -------------------------------------------------------------

            if (dma_active) begin

                dma_source_ptr   <= dma_source_ptr + 27'd1;
                dma_dest_ptr     <= dma_dest_ptr + 27'd1;
                dma_word_counter <= dma_word_counter - 16'd1;

            end

            // -------------------------------------------------------------
            // Peripheral writes
            // -------------------------------------------------------------

            else if (mem_write_en) begin

                if (mem_addr == MDU_REG_A_ADDR)
                    mdu_param_a <= mem_write_data;

                if (mem_addr == MDU_REG_B_ADDR)
                    mdu_param_b <= mem_write_data;

                if (mem_addr == VIC_ENABLE_ADDR)
                    vic_enabled_channels <= mem_write_data;

                if (mem_addr == VIC_VECTOR_BASE_ADDR)
                    vic_vector_base_ptr <= mem_write_data;

                if (mem_addr == DMA_SRC_ADDR)
                    dma_source_ptr[15:0] <= mem_write_data;

                if (mem_addr == DMA_DST_ADDR)
                    dma_dest_ptr[15:0] <= mem_write_data;

                if (mem_addr == DMA_CNT_ADDR)
                    dma_word_counter <= mem_write_data;

                if (mem_addr == DMA_SRC_BANK)
                    dma_source_ptr[26:16] <= mem_write_data[10:0];

                if (mem_addr == DMA_DST_BANK)
                    dma_dest_ptr[26:16] <= mem_write_data[10:0];

                if (mem_addr == INT32_REG_A_LO_ADDR)
                    int32_a_lo <= mem_write_data;

                if (mem_addr == INT32_REG_A_HI_ADDR)
                    int32_a_hi <= mem_write_data;

                if (mem_addr == INT32_REG_B_LO_ADDR)
                    int32_b_lo <= mem_write_data;

                if (mem_addr == INT32_REG_B_HI_ADDR)
                    int32_b_hi <= mem_write_data;

                if (mem_addr == INT32_CMD_ADDR)
                    int32_cmd <= mem_write_data[2:0];

            end

        end

    end


    // =========================================================================
    // RAM WRITE LOGIC
    // =========================================================================

    always @(posedge clk) begin

        if (!rst) begin

            // -------------------------------------------------------------
            // DMA RAM transfer
            // -------------------------------------------------------------

            if (dma_active) begin

                if ((^dma_source_ptr === 1'b0 ||
                     ^dma_source_ptr === 1'b1) &&
                    (^dma_dest_ptr === 1'b0 ||
                     ^dma_dest_ptr === 1'b1)) begin

                    if ((dma_source_ptr[26:11] == 0) &&
                        (dma_dest_ptr[26:11] == 0)) begin

                        ram_array[dma_dest_ptr[10:0]] <=
                            ram_array[dma_source_ptr[10:0]];

                    end

                end

            end

            // -------------------------------------------------------------
            // Normal CPU RAM write
            // -------------------------------------------------------------

            else if (mem_write_en &&
                     (mem_addr < RAM_WORDS)) begin

                ram_array[mem_addr[RAM_ADDR_BITS-1:0]] <=
                    mem_write_data;

            end

        end

    end


    // =========================================================================
    // UART MONITOR
    // =========================================================================

    always @(posedge clk) begin

        if (!rst &&
            mem_write_en &&
            (mem_addr == VIRTUAL_UART_ADDR)) begin

            $display(
                "[UART] HEX=%04h CHAR='%c'",
                mem_write_data,
                mem_write_data[7:0]
            );

        end

    end


    // =========================================================================
    // MEMORY WRITE MONITOR
    // =========================================================================

    always @(posedge clk) begin
    if (!rst && uut.current_state == 4'd0) begin

        $display(
            "[FETCH] T=%0t PC=%04h IR=%04h OP=%h X=%04h Y=%04h JR=%07h COND=%h MET=%b",
            $time,
            uut.PC,
            uut.IR,
            uut.opcode,
            uut.operand_x,
            uut.operand_y,
            uut.JR,
            uut.condition_code,
            uut.condition_met
        );

    end
end


    // =========================================================================
    // CPU FETCH TRACE
    // =========================================================================

   // always @(posedge clk) begin
   // if (!rst && uut.current_state == 4'd0) begin
    //    $display(
     //       "[FETCH] T=%0t PC=%04h ADDR=%07h DATA=%04h IR=%04h",
      //      $time,
       //     uut.PC,
   //         mem_addr,
   //         mem_read_data,
   //         uut.IR
    ///    );
  //  end
//end 
    // =========================================================================
    // X/Z DETECTOR
    // =========================================================================

    always @(posedge clk) begin

        if (!rst) begin

            if (^uut.PC === 1'bx) begin

                $display("");
                $display("============================================================");
                $display("ERROR: CPU PC BECAME X/Z");
                $display("============================================================");

                $display("PC             = %h",  uut.PC);
                $display("IR             = %h",  uut.IR);
                $display("STATE          = %0d", uut.current_state);
                $display("MEM ADDR       = %h",  mem_addr);
                $display("MEM DATA       = %h",  mem_read_data);
                $display("PROGRAM EAM    = %h",  uut.PROGRAM_EAM);
                $display("DATA EAM       = %h",  uut.DATA_EAM);
                $display("JR             = %h",  uut.JR);
                $display("SP             = %0d", uut.stack_sp);
                $display("INT VEC        = %h",  tb_interrupt_vector);

                $display("R0             = %h", uut.R[0]);
                $display("R1             = %h", uut.R[1]);
                $display("R2             = %h", uut.R[2]);
                $display("R3             = %h", uut.R[3]);
                $display("R4             = %h", uut.R[4]);
                $display("R5             = %h", uut.R[5]);
                $display("R6             = %h", uut.R[6]);
                $display("R7             = %h", uut.R[7]);

                $display("============================================================");
                $display("");

                $finish;

            end

        end

    end


    // =========================================================================
    // CPU REGISTER / STATE DUMP
    // =========================================================================

    task dump_cpu_state;

        begin

            $display("");
            $display("================================================================");
            $display("                 GATEWAY DRUG CPU STATE DUMP");
            $display("================================================================");

            // -------------------------------------------------------------
            // CONTROL
            // -------------------------------------------------------------

            $display("");
            $display("--- CONTROL ---");

            $display("STATE          = %0d",  uut.state);
            $display("CURRENT_STATE  = %0d",  uut.current_state);
            $display("HALTED         = %b",   uut.halted);
            $display("INT_ENABLE     = %b",   uut.interrupt_enable);
            $display("INT_PENDING    = %b",   uut.interrupt_pending);
            $display("EXT_INTERRUPT  = %b",   tb_interrupt);
            $display("INT_VECTOR     = %07h", uut.IVR);

            // -------------------------------------------------------------
            // PROGRAM
            // -------------------------------------------------------------

            $display("");
            $display("--- PROGRAM ---");

            $display("PC             = %04h", uut.PC);
            $display("IR             = %04h", uut.IR);
            $display("INSTRUCTION_PC = %04h", uut.instruction_pc);
            $display("NEXT_PC        = %04h", uut.next_pc);
            $display("INSTR_LENGTH   = %0d",  uut.instruction_length);

            // -------------------------------------------------------------
            // ADDRESSING
            // -------------------------------------------------------------

            $display("");
            $display("--- ADDRESSING ---");

            $display("JR             = %07h", uut.JR);
            $display("PROGRAM_EAM    = %03h", uut.PROGRAM_EAM);
            $display("DATA_EAM       = %03h", uut.DATA_EAM);
            $display("EFFECTIVE_ADDR = %07h", uut.effective_address);

            // -------------------------------------------------------------
            // REGISTERS
            // -------------------------------------------------------------

            $display("");
            $display("--- GENERAL PURPOSE REGISTERS ---");

            $display("R0 = %04h    R1 = %04h",
                     uut.R[0], uut.R[1]);

            $display("R2 = %04h    R3 = %04h",
                     uut.R[2], uut.R[3]);

            $display("R4 = %04h    R5 = %04h",
                     uut.R[4], uut.R[5]);

            $display("R6 = %04h    R7 = %04h",
                     uut.R[6], uut.R[7]);

            // -------------------------------------------------------------
            // DECODE
            // -------------------------------------------------------------

            $display("");
            $display("--- DECODE ---");

            $display("OPCODE         = %h",  uut.opcode);
            $display("FLAG_M         = %b",  uut.flag_M);
            $display("REG_D          = %0d", uut.reg_D);
            $display("FLAG_LX        = %b",  uut.flag_LX);
            $display("REG_X          = %0d", uut.reg_X);
            $display("FLAG_LY        = %b",  uut.flag_LY);
            $display("REG_Y          = %0d", uut.reg_Y);

            $display("IMMEDIATE_X    = %04h", uut.immediate_x);
            $display("IMMEDIATE_Y    = %04h", uut.immediate_y);
            $display("OPERAND_X      = %04h", uut.operand_x);
            $display("OPERAND_Y      = %04h", uut.operand_y);

            $display("CONDITION_CODE = %h",  uut.condition_code);
            $display("CONDITION_MET  = %b",  uut.condition_met);

            // -------------------------------------------------------------
            // STACK
            // -------------------------------------------------------------

            $display("");
            $display("--- STACK ---");

            $display("STACK_SP       = %0d", uut.stack_sp);
            $display("STACK_EMPTY    = %b",  uut.stack_empty);
            $display("STACK_FULL     = %b",  uut.stack_full);

            if (uut.stack_sp != 0) begin

                $display(
                    "STACK[TOP-1]   = %07h",
                    uut.call_stack[uut.stack_sp[7:0] - 1]
                );

            end

            // -------------------------------------------------------------
            // BUS
            // -------------------------------------------------------------

            $display("");
            $display("--- BUS ---");

            $display("MEM_ADDR       = %07h", mem_addr);
            $display("MEM_READ_DATA  = %04h", mem_read_data);
            $display("MEM_WRITE_DATA = %04h", mem_write_data);
            $display("MEM_WRITE_EN   = %b",   mem_write_en);
            $display("DMA_ACTIVE     = %b",   dma_active);

            // -------------------------------------------------------------
            // COPROCESSORS
            // -------------------------------------------------------------

            $display("");
            $display("--- COPROCESSORS ---");

            $display("MDU A          = %04h", mdu_param_a);
            $display("MDU B          = %04h", mdu_param_b);
            $display("MDU PRODUCT    = %08h", mdu_product);

            $display("INT32 A        = %08h", full_operand_a);
            $display("INT32 B        = %08h", full_operand_b);
            $display("INT32 CMD      = %0d",  int32_cmd);
            $display("INT32 RESULT   = %08h", int32_result);

            $display("FPU BUSY       = %b", fpu_busy);

            $display("");
            $display("================================================================");

        end

    endtask


    // =========================================================================
    // RESET / PROGRAM LOAD / WATCHDOG
    // =========================================================================
	
integer loop_hits;

initial begin
    loop_hits = 0;
end

always @(posedge clk) begin

    if (!rst &&
        uut.current_state == 4'd0 &&
        uut.PC == 16'h00f0) begin

        loop_hits = loop_hits + 1;

        $display(
            "[BREAKPOINT] T=%0t HIT PC=00F0 count=%0d IR=%04h NEXT=%04h",
            $time,
            loop_hits,
            uut.IR,
            uut.next_pc
        );

        if (loop_hits >= 3) begin

            $display("");
            $display("============================================================");
            $display("CPU CONTROL-FLOW LOOP DETECTED");
            $display("============================================================");

            $display("PC             = %04h", uut.PC);
            $display("IR             = %04h", uut.IR);
            $display("NEXT_PC        = %04h", uut.next_pc);
            $display("STATE          = %0d", uut.current_state);

            $display("");
            $display("--- DECODE ---");

            $display("OPCODE         = %h",  uut.opcode);
            $display("CONDITION_CODE = %h",  uut.condition_code);
            $display("CONDITION_MET  = %b",  uut.condition_met);

            $display("REG_D          = %0d", uut.reg_D);
            $display("REG_X          = %0d", uut.reg_X);
            $display("REG_Y          = %0d", uut.reg_Y);

            $display("OPERAND_X      = %04h", uut.operand_x);
            $display("OPERAND_Y      = %04h", uut.operand_y);

            $display("");
            $display("--- ADDRESSING ---");

            $display("JR             = %07h", uut.JR);
            $display("EFFECTIVE_ADDR = %07h", uut.effective_address);

            $display("");
            $display("--- INTERRUPTS ---");

            $display("INT_ENABLE     = %b", uut.interrupt_enable);
            $display("INT_PENDING    = %b", uut.interrupt_pending);
            $display("EXT_INTERRUPT  = %b", tb_interrupt);
            $display("INT_VECTOR     = %07h", uut.IVR);

            $display("");
            $display("--- REGISTERS ---");

            $display("R0 = %04h", uut.R[0]);
            $display("R1 = %04h", uut.R[1]);
            $display("R2 = %04h", uut.R[2]);
            $display("R3 = %04h", uut.R[3]);
            $display("R4 = %04h", uut.R[4]);
            $display("R5 = %04h", uut.R[5]);
            $display("R6 = %04h", uut.R[6]);
            $display("R7 = %04h", uut.R[7]);

            $display("");
            $display("============================================================");

            $finish;

        end

    end

end
    initial begin

        tb_interrupt        = 1'b0;
        tb_interrupt_vector = 27'h0000100;

        rst = 1'b1;

        // -------------------------------------------------------------
        // Initialize RAM
        // -------------------------------------------------------------

        for (i = 0; i < RAM_WORDS; i = i + 1)
            ram_array[i] = 16'h0000;

        // -------------------------------------------------------------
        // Load program
        // -------------------------------------------------------------

        $display("");
        $display("============================================================");
        $display("GATEWAY DRUG CPU TESTBENCH");
        $display("============================================================");

        $readmemh("torture.hex", ram_array);

        $display("Program memory loaded from torture.hex.");
        $display("Reset asserted.");
        $display("============================================================");
        $display("");

        // -------------------------------------------------------------
        // Hold reset for five clocks
        // -------------------------------------------------------------

        repeat (5)
            @(posedge clk);

        rst = 1'b0;

        $display("");
        $display("------------------------------------------------------------");
        $display("RESET RELEASED");
        $display("PC=%04h STATE=%0d MEM_ADDR=%07h",
                 uut.PC,
                 uut.current_state,
                 mem_addr);
        $display("------------------------------------------------------------");
        $display("");

        // -------------------------------------------------------------
        // Optional interrupt test
        // -------------------------------------------------------------

        /*
        repeat (50)
            @(posedge clk);

        $display("[TB] ASSERTING INTERRUPT");

        tb_interrupt = 1'b1;

        repeat (2)
            @(posedge clk);

        tb_interrupt = 1'b0;

        $display("[TB] INTERRUPT RELEASED");
        */

        // -------------------------------------------------------------
        // Watchdog
        // -------------------------------------------------------------

      repeat (2000)
            @(posedge clk);

        $display("");
        $display("============================================================");
        $display("WATCHDOG TIMEOUT");
        $display("============================================================");

        dump_cpu_state();

        $display("");
        $display("============================================================");

        $finish;

    end


    // =========================================================================
    // HLT DETECTOR
    // =========================================================================

    always @(posedge clk) begin

        if (!rst &&
            uut.current_state == 4'd9) begin

            $display("");
            $display("============================================================");
            $display("CPU REACHED HLT");
            $display("============================================================");

            dump_cpu_state();

            $display("");
            $display("CPU HALTED NORMALLY.");
            $display("");

            $finish;

        end

    end

endmodule
