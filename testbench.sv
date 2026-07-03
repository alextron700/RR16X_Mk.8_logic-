// Code your testbench here
// or browse Examples
// =========================================================================
// GATEWAY DRUG CPU - UNIFIED PHYSICAL SOC HARDWARE TESTBENCH
// =========================================================================
module gateway_drug_tb;
reg clk;
reg rst;
wire [26:0] mem_addr;
reg [15:0] peripheral_read_data;
wire [15:0] mem_read_data;
wire [15:0] mem_write_data;
wire mem_write_en;
reg [15:0] vic_enabled_channels;
reg [15:0] vic_vector_base_ptr;
wire [15:0] ram_read_word = ram_array[mem_addr[15:0]];
wire [3:0] vic_hardware_inputs;
// assign vic_hardware_inputs = (hardware_timer == 16'h03FF) ? 4'b0001 : 4'b0000;
assign vic_hardware_inputs = {3'b000, tb_interrupt};
wire [3:0] vic_active_requests = vic_hardware_inputs & vic_enabled_channels;

wire [1:0] vic_highest_priority;
assign vic_highest_priority = (vic_active_requests & 4'b0001) ? 2'd0 :
(vic_active_requests & 4'b0010) ? 2'd1 :
(vic_active_requests & 4'b0100) ? 2'd2 : 2'd3;

wire vic_global_trigger = (vic_active_requests != 4'b0000);
reg [15:0] int32_a_lo;
reg [15:0] int32_a_hi;
reg [15:0] int32_b_lo;
reg [15:0] int32_b_hi;
reg [2:0] int32_cmd;

// Symmetrical 32-bit internal routing hooks
wire [31:0] full_operand_a = {int32_a_hi, int32_a_lo};
wire [31:0] full_operand_b = {int32_b_hi, int32_b_lo};

// Clean, zero-overhead combinational arithmetic plane
reg [31:0] int32_result;
always @(*) begin
case (int32_cmd)
3'd0: int32_result = full_operand_a + full_operand_b; // ADD32
3'd1: int32_result = full_operand_a - full_operand_b; // SUB32
3'd2: int32_result = full_operand_a << full_operand_b[4:0]; // SHL32 (cap shift at 31)
3'd3: int32_result = full_operand_a >> full_operand_b[4:0]; // SHR32
3'd4: int32_result = full_operand_a & full_operand_b; // AND32
3'd5: int32_result = full_operand_a | full_operand_b; // OR32
3'd6: int32_result = full_operand_a ^ full_operand_b; // XOR32
default: int32_result = 32'h00000000;
endcase
end

// Real RAM array storage (2048 words deep)
reg [15:0] ram_array [0:65535];
reg [26:0] dma_source_ptr;
reg [26:0] dma_dest_ptr;
reg [15:0] dma_word_counter;

// Status flag to freeze CPU bus operations
wire dma_active = (dma_word_counter != 16'h0000);
// Hardware Peripheral Registers
reg [15:0] hardware_timer;
reg tb_interrupt;

// Instantiate the CPU core
gateway_drug_cpu uut (
.clk(clk),
.rst(rst),
.ext_interrupt(tb_interrupt),
.mem_addr(mem_addr),
.mem_read_data(mem_read_data),
.mem_write_data(mem_write_data),
.mem_write_en(mem_write_en),
.dma_active(dma_active)
);

// Generate a continuous 100MHz clock signal (10ns period)
always #5 clk = ~clk;

// =========================================================================
// MEMORY MAP BUS ADDRESSES
// =========================================================================
// UART & hardware timer extensions
localparam VIRTUAL_UART_ADDR = 27'h7FFFFFF;
localparam HARDWARE_TIMER_ADDR = 27'h7FFFFFE;
// Multiply/Divide Coprocessor
localparam MDU_REG_A_ADDR = 27'h7FFFFFD;
localparam MDU_REG_B_ADDR = 27'h7FFFFFC;
localparam MDU_REG_RES_LO_ADDR = 27'h7FFFFFB;
localparam MDU_REG_RES_HI_ADDR = 27'h7FFFFFA;

// --- INTEGRATED FP32 COPROCESSOR EXTENSION SPACE ---
// Memory mapping the FPU window using a base boundary
localparam FPU_BASE_ADDR = 27'h7FFFFD6; // Maps 4'h0 to 4'h6 down to 27'h7FFFFD0
wire fpu_sel = (mem_addr >= 27'h7FFFFD6 && mem_addr <= 27'h7FFFFD0); // Adjusting range allocations
wire [15:0] fpu_dout;
wire fpu_busy;

// Interrupt controller Extension Hardware
localparam VIC_ENABLE_ADDR = 27'h7FFFFF5;
localparam VIC_PENDING_ADDR = 27'h7FFFFF4;
localparam VIC_VECTOR_BASE_ADDR= 27'h7FFFFF3;
// DMA extension hardware
localparam DMA_SRC_ADDR = 27'h7FFFFF2;
localparam DMA_DST_ADDR = 27'h7FFFFF1;
localparam DMA_CNT_ADDR = 27'h7FFFFF0;
localparam DMA_SRC_BANK = 27'h7FFFFEF;
localparam DMA_DST_BANK = 27'h7FFFFEE;
// Int32 Extension Hardware
localparam INT32_REG_A_LO_ADDR = 27'h7FFFFED;
localparam INT32_REG_A_HI_ADDR = 27'h7FFFFEC;
localparam INT32_REG_B_LO_ADDR = 27'h7FFFFEB;
localparam INT32_REG_B_HI_ADDR = 27'h7FFFFEA;
localparam INT32_CMD_ADDR = 27'h7FFFFE9;
localparam INT32_RES_LO_ADDR = 27'h7FFFFE8;
localparam INT32_RES_HI_ADDR = 27'h7FFFFE7;

// --- FP32 Coprocessor Instance Implementation ---
// Subtracting the address from the target base to safely generate local offsets (0 to 6)
fp32_coprocessor fpu_uut (
.clk(clk),
.rst_n(!rst),
.addr(FPU_BASE_ADDR[3:0] - mem_addr[3:0]),
.din(mem_write_data),
.write_en(mem_write_en && (mem_addr >= 27'h7FFFFD6 && mem_addr <= 27'h7FFFFD0)),
.dout(fpu_dout),
.busy(fpu_busy)
);

// Hardware Multiplier-Divider Unit (MDU) Core Registers
reg [15:0] mdu_param_a;
reg [15:0] mdu_param_b;
wire [31:0] mdu_product = mdu_param_a * mdu_param_b; // Combinational multiplier

// Synchronous Write Logic for Peripherals & RAM Array
always @(posedge clk or posedge rst) begin
if (rst) begin
hardware_timer <= 16'h0000;
mdu_param_a <= 16'h0000;
mdu_param_b <= 16'h0000;
vic_enabled_channels <= 16'h0000;
vic_vector_base_ptr <= 16'h0000;
dma_source_ptr <= 16'h0000;
dma_dest_ptr <= 16'h0000;
dma_word_counter <= 16'h0000;
int32_a_lo <= 16'h0000;
int32_a_hi <= 16'h0000;
int32_b_lo <= 16'h0000;
int32_b_hi <= 16'h0000;
int32_cmd <= 3'd7;
end else begin
hardware_timer <= hardware_timer + 1'b1;
if (dma_active) begin
dma_source_ptr <= dma_source_ptr + 27'h1;
dma_dest_ptr <= dma_dest_ptr + 27'h1;
dma_word_counter <= dma_word_counter - 16'h1;
end else if (mem_write_en) begin
if (mem_addr == MDU_REG_A_ADDR) mdu_param_a <= mem_write_data;
if (mem_addr == MDU_REG_B_ADDR) mdu_param_b <= mem_write_data;
if (mem_addr == VIC_ENABLE_ADDR) vic_enabled_channels <= mem_write_data;
if (mem_addr == VIC_VECTOR_BASE_ADDR) vic_vector_base_ptr <= mem_write_data;
if (mem_addr == DMA_SRC_ADDR) dma_source_ptr[15:0] <= mem_write_data;
if (mem_addr == DMA_DST_ADDR) dma_dest_ptr[15:0] <= mem_write_data;
if (mem_addr == DMA_CNT_ADDR) dma_word_counter <= mem_write_data;
if(mem_addr == DMA_SRC_BANK) dma_source_ptr[26:16] <= mem_write_data;
if(mem_addr == DMA_DST_BANK) dma_dest_ptr[26:16] <= mem_write_data;
if (mem_addr == INT32_REG_A_LO_ADDR) int32_a_lo <= mem_write_data;
if (mem_addr == INT32_REG_A_HI_ADDR) int32_a_hi <= mem_write_data;
if (mem_addr == INT32_REG_B_LO_ADDR) int32_b_lo <= mem_write_data;
if (mem_addr == INT32_REG_B_HI_ADDR) int32_b_hi <= mem_write_data;
if (mem_addr == INT32_CMD_ADDR) int32_cmd <= mem_write_data[2:0];
end
end
end

always @(posedge clk) begin
if (dma_active) begin
ram_array[dma_dest_ptr[26:0]] <= ram_array[dma_source_ptr[15:0]];
end
else if (mem_write_en && (mem_addr < 27'h7FFFFE9)) begin
ram_array[mem_addr[15:0]] <= mem_write_data;
end
end

assign mem_read_data = 
(mem_addr == HARDWARE_TIMER_ADDR)               ? hardware_timer :
(mem_addr == MDU_REG_RES_LO_ADDR)               ? mdu_product[15:0] :
(mem_addr == MDU_REG_RES_HI_ADDR)               ? mdu_product[31:16] :
(mem_addr >= 27'h7FFFFD6 && mem_addr <= 27'h7FFFFD0) ? fpu_dout :
(mem_addr == VIC_PENDING_ADDR)                  ? vic_active_requests :
(mem_addr == VIC_VECTOR_BASE_ADDR)              ? (vic_vector_base_ptr + vic_highest_priority) :
(mem_addr == DMA_SRC_ADDR)                      ? dma_source_ptr[15:0] :
(mem_addr == DMA_DST_ADDR)                      ? dma_dest_ptr[15:0] :
(mem_addr == DMA_CNT_ADDR)                      ? dma_word_counter :
 (mem_addr == DMA_SRC_BANK)                  ?dma_source_ptr[26:16]:
 (mem_addr == DMA_DST_BANK)                  ?dma_dest_ptr[26:16]:
(mem_addr == INT32_REG_A_LO_ADDR)               ? int32_a_lo :
(mem_addr == INT32_REG_A_HI_ADDR)               ? int32_a_hi :
(mem_addr == INT32_REG_B_LO_ADDR)               ? int32_b_lo :
(mem_addr == INT32_REG_B_HI_ADDR)               ? int32_b_hi :
(mem_addr == INT32_RES_LO_ADDR)                 ? int32_result[15:0] :
(mem_addr == INT32_RES_HI_ADDR)                 ? int32_result[31:16] :
                                                  ram_read_word;
// =========================================================================
// EXECUTION TRACING, SYSTEM TELEMETRY & CONSOLE MONITORS
// =========================================================================
int cycle_count = 0;

always @(posedge clk) begin
// Virtual UART Console Intercept
if (mem_write_en && (mem_addr == VIRTUAL_UART_ADDR)) begin
$display("[UART Out] Raw Hex: 0x%h | Lower 8-bit Char: '%c'", mem_write_data, mem_write_data[7:0]);
$fflush();
end

// Logging CPU Pipeline Telemetry
if (!rst) begin
    $display("CYCLE %0d | PC: 0x%h | State: %0d | BusAddr: 0x%h | WriteEn: %b | WriteData: 0x%h", 
             cycle_count, uut.PC, uut.current_state, mem_addr, mem_write_en, mem_write_data);
    cycle_count = cycle_count + 1;
end

// Clean Execution Exit
if (uut.current_state == 3'd4 && uut.opcode == 4'hF && !uut.flag_M) begin
    $display("\n[Hardware] Standard HLT instruction executed. Stopping simulation successfully.");
    $finish;
end

// Safety Watchdog Timeout Filter
if ($time > 10000) begin
    $display("\n[Warning] Simulation timed out safely via watchdog filter.");
    $finish;
end
end

// =========================================================================
// TEST VECTOR INITIALIZATION
// =========================================================================
initial begin
tb_interrupt = 1'b0;

// Attempt to load up your assembled file
$readmemh("torture.hex", ram_array);
$display("SUCCESS: Loaded output1f.hex into simulation memory.");

clk = 0;
rst = 1;         
#20;             
rst = 0; // Release system reset line

// Optional test vector: uncomment to test your interrupt hardware behavior
 #550 tb_interrupt = 1'b1;
 #50  tb_interrupt = 1'b0;
end
endmodule
