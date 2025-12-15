`timescale 1ns / 1ps

module tb_main;
`include "ansi_display.svh"

//==============================================================================
// Reset
//==============================================================================
reg RSTN;
initial begin
    RSTN = 0;
    #50;
    RSTN = 1;
end

//==============================================================================
// Parameters
//==============================================================================
localparam int WIDTH     = 32;
localparam int DEPTH     = 5;   // FIFO entries = 32
localparam int PFULL_TH  = 8;
localparam int PEMPTY_TH = 8;

//==============================================================================
// Signals
//==============================================================================
reg                 i_wr_clk;
reg                 i_wr_rstn;
reg                 i_wr_en;
wire                o_wr_full;
wire                o_wr_afull;
wire                o_wr_pfull;
reg  [WIDTH-1:0]    i_wr_data;
wire [DEPTH:0]      o_wr_remain;

reg                 i_rd_clk;
reg                 i_rd_rstn;
reg                 i_rd_en;
wire                o_rd_empty;
wire                o_rd_aempty;
wire                o_rd_pempty;
wire [WIDTH-1:0]    o_rd_data;
wire [DEPTH:0]      o_rd_depth;

//==============================================================================
// DUT
//==============================================================================
async_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH),
    .PFULL_TH(PFULL_TH),
   .PEMPTY_TH(PEMPTY_TH)
) dut (.*);

//==============================================================================
// Clocks (Async)
//==============================================================================
initial begin
    i_wr_clk = 0;
    forever #2.5 i_wr_clk = ~i_wr_clk; // 200 MHz
end

initial begin
    i_rd_clk = 0;
    forever #4.0 i_rd_clk = ~i_rd_clk; // 125 MHz
end

always @(*) begin
    i_wr_rstn = RSTN;
    i_rd_rstn = RSTN;
end

//==============================================================================
// Tasks
//==============================================================================
task automatic fifo_write(input [WIDTH-1:0] data);
begin
    @(posedge i_wr_clk);
    if (!o_wr_full) begin
        i_wr_en   <= 1'b1;
        i_wr_data <= data;
        @(posedge i_wr_clk);
        i_wr_en   <= 1'b0;
        $display("W @%0t data=%h remain=%0d full=%0b",
                 $time, data, o_wr_remain, o_wr_full);
    end
    else begin
        $display("⚠️ WRITE BLOCKED (FULL) @%0t data=%h", $time, data);
    end
end
endtask

task automatic fifo_read();
begin
    @(posedge i_rd_clk);
    if (!o_rd_empty) begin
        i_rd_en <= 1'b1;
        @(posedge i_rd_clk);
        i_rd_en <= 1'b0;
        $display("R @%0t data=%h depth=%0d empty=%0b",
                 $time, o_rd_data, o_rd_depth, o_rd_empty);
    end
end
endtask

//==============================================================================
// Stimulus
//==============================================================================
integer i;

initial begin
    // init
    i_wr_en   = 0;
    i_rd_en   = 0;
    i_wr_data = 0;

    wait(RSTN);
    repeat (3) @(posedge i_wr_clk);
    repeat (3) @(posedge i_rd_clk);

    `DISP_SECTION("SCENARIO: FILL FIFO UNTIL FULL");

    //--------------------------------------------------------------------------
    // 1) WRITE ONLY → FIFO 가득 채우기
    //--------------------------------------------------------------------------
    for (i = 0; i < 40; i++) begin
        fifo_write(32'hA000_0000 + i);
    end

    `DISP_SECTION("FIFO SHOULD BE FULL NOW");

    //--------------------------------------------------------------------------
    // 2) FULL 상태에서 write 시도 (차단되는 모습)
    //--------------------------------------------------------------------------
    repeat (5) fifo_write(32'hDEAD_BEEF);

    //--------------------------------------------------------------------------
    // 3) READ 시작 → FULL 해제 확인
    //--------------------------------------------------------------------------
    `DISP_SECTION("START READ → FULL RELEASE");

    repeat (10) fifo_read();

    //--------------------------------------------------------------------------
    // 4) WRITE / READ 번갈아 정상 동작
    //--------------------------------------------------------------------------
    `DISP_SECTION("NORMAL INTERLEAVED OPERATION");

    for (i = 0; i < 10; i++) begin
        fifo_write(32'hB000_0000 + i);
        fifo_read();
    end

    //--------------------------------------------------------------------------
    // 5) 마무리: 모두 읽어서 empty 확인
    //--------------------------------------------------------------------------
    `DISP_SECTION("FINAL DRAIN");

    repeat (40) fifo_read();

    repeat (5) @(posedge i_rd_clk);
    if (!o_rd_empty) begin
        $display("❌ ERROR: FIFO not empty at end");
        $fatal;
    end

    `DISP_TEST_TAG("✅ FIFO FULL/EMPTY DEMO PASSED");
    $finish;
end

endmodule
