`timescale 1ns / 1ps

module tb_main;
//`include "ansi_display.svh"

//==============================================================================
// Reset
//==============================================================================
reg RSTN;
reg RSTN_rd;

initial begin
    RSTN = 0;
    RSTN_rd = 0;
    #200;
    RSTN = 1;
    #400;
    RSTN_rd = 1;
end
/*
//==============================================================================
// Parameters
//==============================================================================
localparam int WIDTH      = 32;
localparam int DEPTH      = 5;   // FIFO entries = 32
localparam int PFULL_TH   = 8;
localparam int PEMPTY_TH  = 8;
localparam int DEBUG_MODE = 1;
parameter NUM = 10000; // fork join_any (동시에 write read) 수행할 횟수

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

wire [31:0]         o_wr_count;
wire [31:0]         o_wr_trial;
wire [31:0]         o_wr_fail;
wire [31:0]         o_rd_count;
wire [31:0]         o_rd_trial;
wire [31:0]         o_rd_fail;

//==============================================================================
// DUT
//==============================================================================
async_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH),
    .PFULL_TH(PFULL_TH),
	.PEMPTY_TH(PEMPTY_TH),
    .DEBUG_MODE(DEBUG_MODE)
) dut (.*);
*/
//==============================================================================
// Parameters
//==============================================================================
localparam NUM        = 10000; // fork join_any (동시에 write read) 수행할 횟수

localparam WIDTH      = 8;
localparam DEPTH      = 5;
localparam PFULL_TH   = 2;
localparam PEMPTY_TH  = 8;
localparam M_WRITERS  = 1;
localparam N_READERS  = 8;
localparam WR_WIDTH = 64;
//==============================================================================
// Signals
//==============================================================================
/*
logic                        i_wr_clk;
logic                        i_wr_rstn;
logic [M_WRITERS-1:0]        i_wr_en;

logic                       o_wr_full;
logic                       o_wr_afull;
logic                       o_wr_pfull;
logic [DEPTH:0]             o_wr_remain;

logic [M_WRITERS*WIDTH-1:0]  i_wr_data;

logic                        i_rd_clk;
logic                        i_rd_rstn;
logic [N_READERS-1:0]        i_rd_en;

logic                       o_rd_empty;
logic                       o_rd_aempty;
logic                       o_rd_pempty;
logic [DEPTH:0]             o_rd_depth;

logic [N_READERS*WIDTH-1:0] o_rd_data;
logic [N_READERS-1:0]       o_rd_valid;*/
logic                        i_wr_clk;
logic                        i_wr_rstn;
logic [M_WRITERS-1:0]        i_wr_en;
logic                       o_wr_full;
logic                       o_wr_afull;
logic                       o_wr_pfull;
logic [WR_WIDTH-1:0]         i_wr_data;
logic [DEPTH:0]             o_wr_remain;
logic                        i_rd_clk;
logic                        i_rd_rstn;
logic [N_READERS-1:0]        i_rd_en;
logic                       o_rd_empty;
logic                       o_rd_aempty;
logic                       o_rd_pempty;
logic [N_READERS*WIDTH-1:0] o_rd_data;
logic [DEPTH:0]             o_rd_depth;
//==============================================================================
// DUT
//==============================================================================
/*MtoN_async_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH),
    .PFULL_TH(PFULL_TH),
    .PEMPTY_TH(PEMPTY_TH),
    .M_WRITERS(M_WRITERS),
    .N_READERS(N_READERS)
) dut(.*);*/

OnetoN_async_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH),
    .PFULL_TH(PFULL_TH),
    .PEMPTY_TH(PEMPTY_TH),
    .M_WRITERS(M_WRITERS),
    .N_READERS(N_READERS),
    .WR_WIDTH(WR_WIDTH)
) dut(.*);
//==============================================================================
// Clocks (Async)
//==============================================================================
initial begin
    i_wr_clk = 0;
    //forever #4.0 i_wr_clk = ~i_wr_clk; // 100 MHz
    //forever #2.5 i_wr_clk = ~i_wr_clk; // 200 MHz
    forever #1.25 i_wr_clk = ~i_wr_clk; // 400 MHz
end

initial begin
    i_rd_clk = 0;
    forever #4.0 i_rd_clk = ~i_rd_clk; // 125 MHz
    //forever #2.5 i_rd_clk = ~i_rd_clk; // 200 MHz
    //forever #1.25 i_rd_clk = ~i_rd_clk; // 400 MHz
end

assign i_wr_rstn = RSTN;
assign i_rd_rstn = RSTN_rd;

//==============================================================================
// Tasks
//==============================================================================
logic [63:0] rand64;

always @(posedge i_wr_clk or negedge i_wr_rstn) begin
    if(!i_wr_rstn) begin 
        rand64 <= 64'h0;
    end else begin
        rand64 <= { $urandom, $urandom };
    end
end

task automatic fifo_write(reg [WR_WIDTH-1:0] data);
begin
    @(posedge i_wr_clk);
    i_wr_en   = 1'b1;
    i_wr_data = data;
    @(posedge i_wr_clk);
    i_wr_en   = 1'b0;
    
    //if (!o_wr_full) begin
    //    $display("W @%0t data=%h remain=%0d full=%0b", $time, data, o_wr_remain, o_wr_full); 
    //end else begin
    //    $display("W @%0t FIFO IS FULL, data=%h remain=%0d full=%0b", $time, data, o_wr_remain, o_wr_full); 
    //end
end
endtask

/*task automatic fifo_read();
begin
    @(posedge i_rd_clk);
    i_rd_en = 1'b1;
    @(posedge i_rd_clk);
    i_rd_en = 1'b0;
    
    if (!o_rd_empty) begin
        $display("R @%0t data=%h depth=%0d empty=%0b", $time, o_rd_data, o_rd_depth, o_rd_empty);    
    end else begin
        $display("R @%0t FIFO IS EMPTY, data=%h remain=%0d empty=%0b", $time, o_rd_data, o_rd_depth, o_rd_empty); 
    end
end
endtask*/

/*task automatic fifo_write(logic [WIDTH-1:0] data, logic [M_WRITERS-1:0] M);
begin
    @(posedge i_wr_clk);
    i_wr_en = M;
    i_wr_data[M*WIDTH +:WIDTH] = data;
    @(posedge i_wr_clk);
    i_wr_en = 0;
    repeat(2) @(posedge i_wr_clk);
end
endtask*/

task automatic fifo_read(logic [N_READERS-1:0] N);
//task automatic fifo_read();
begin
    @(posedge i_rd_clk);
    //i_rd_en[N] = 1'b1;
    //i_rd_en = 1'b1;
    i_rd_en = N;
    @(posedge i_rd_clk);
    //i_rd_en[N] = 1'b0;
    //i_rd_en = 1'b0;
    i_rd_en = '0;
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
    //i_wr_data = 16'h3101;
    i_wr_data = '0;

    wait(RSTN_rd);
    repeat (3) @(posedge i_wr_clk);
    repeat (3) @(posedge i_rd_clk);

    //`DISP_SECTION("SCENARIO: FILL FIFO UNTIL FULL");

    //--------------------------------------------------------------------------
    // 1) WRITE ONLY → FIFO 가득 채우기
    //--------------------------------------------------------------------------
    
    while (!o_wr_full) begin
        //fifo_write({rand64,1'b1}, $urandom_range(2**M_WRITERS-1, 0)); 
        fifo_write({rand64,1'b1}); 
    end

    //`DISP_SECTION("FIFO SHOULD BE FULL NOW");

    //--------------------------------------------------------------------------
    // 2) READ 시작 → FULL 해제 확인
    //--------------------------------------------------------------------------
    //`DISP_SECTION("START READ → FULL RELEASE");

    repeat (10) fifo_read($urandom_range(2**N_READERS-1, 0));
    //repeat (10) fifo_read();

    //--------------------------------------------------------------------------
    // 3) fork/join으로 동시 수행
    //--------------------------------------------------------------------------
    fork
        begin : WR_THREAD
            for (int k = 0; k < NUM; k++) begin
                //fifo_write({rand64, 1'b1}, $urandom_range(2**M_WRITERS-1, 0));
                fifo_write({rand64, 1'b1});
                // (옵션) 너무 한쪽으로 몰아치지 않게 가끔 쉬고 싶으면:
                // if ((k % 32) == 31) repeat(1) @(posedge i_wr_clk);
                //if (k == (NUM >> 2)) begin
                //    RSTN = 0;// 리셋
                //    $display("WRITE RESET im");
                //end else if (k == (NUM >> 2) + (NUM >> 5)) begin
                //    RSTN = 1;
                //    $display("WRITE RESET GGUIT");
                //end
            end
        end

        begin : RD_THREAD
            for (int k = 0; k < NUM; k++) begin
                //fifo_read();
                fifo_read($urandom_range(2**N_READERS-1, 0));
                // (옵션) read를 더 느리게 만들어 full을 더 잘 보고 싶으면:
                // repeat(1) @(posedge i_rd_clk);
                //if (k == (NUM >> 4) + (NUM >> 6) + (NUM >> 8)) begin
                //    RSTN_rd = 0;// 리셋
                //    $display("READ RESET im");
                //end else if (k == (NUM >> 4) + (NUM >> 6) + (NUM >> 8) + 20) begin
                //    RSTN_rd = 1;
                //    $display("READ RESET GGUIT");
                //end
            end
        end
    join_any

    //--------------------------------------------------------------------------
    // 4) 마무리: 모두 읽어서 empty 확인
    //--------------------------------------------------------------------------
    //`DISP_SECTION("FINAL DRAIN");

    while(!o_rd_aempty) begin 
        fifo_read($urandom_range(2**N_READERS-1, 0));
        //fifo_read();
    end

    repeat (5) @(posedge i_rd_clk);

    //`DISP_TEST_TAG("✅ FIFO FULL/EMPTY DEMO PASSED");
    $finish;
end

//--------------------------------------------------------------------------
// 파일 생성
//--------------------------------------------------------------------------
/*integer fd_wr, fd_rd, result;

initial begin
    fd_wr = $fopen("WRITE_DATA.txt", "w");
    fd_rd = $fopen("READ_DATA.txt", "w");
    result = $fopen("RESULT.txt", "w");

    if (fd_wr == 0) begin
        $display("❌ DEBUG: failed to open %s", "WRITE_DATA");
        $finish;
    end
    if (fd_rd == 0) begin
        $display("❌ DEBUG: failed to open %s", "READ_DATA");
        $finish;
    end
    if (result == 0) begin
        $display("❌ DEBUG: failed to open %s", "READ_DATA");
        $finish;
    end            
end

wire [1:0] wr_condi = {i_wr_en, o_wr_full};
wire [1:0] rd_condi = {i_rd_en, o_rd_empty};

always @(posedge i_wr_clk) begin
    //if ((wr_condi == 2'b10) && i_wr_rstn && i_rd_rstn) begin
    if ((wr_condi == 2'b10)) begin
        $fdisplay(fd_wr, "%d", i_wr_data);
    end
end

always @(posedge i_rd_clk) begin
    //if ((rd_condi == 2'b10) && i_wr_rstn && i_rd_rstn) begin
    if ((rd_condi == 2'b10)) begin
        $fdisplay(fd_rd, "%d", o_rd_data);
    end
end

final begin
    $fdisplay(result, "");
    $fdisplay(result, "------------------------");
    $fdisplay(result, "----------- write -------");
    $fdisplay(result, "------------------------");
    $fdisplay(result, "write trial count : %0d", o_wr_trial);
    $fdisplay(result, "write success cnt : %0d", o_wr_count);
    $fdisplay(result, "write fail    cnt : %0d", o_wr_fail);

    $fdisplay(result, "");
    $fdisplay(result, "------------------------");
    $fdisplay(result, "----------- read --------");
    $fdisplay(result, "------------------------");
    $fdisplay(result, "read  trial count : %0d", o_rd_trial);
    $fdisplay(result, "read  success cnt : %0d", o_rd_count);
    $fdisplay(result, "read  fail    cnt : %0d", o_rd_fail);

    $fdisplay(result, "========== DEBUG RESULT END ==========");

    $fclose(fd_wr);
    $fclose(fd_rd);
    $fclose(result);
end*/

endmodule
