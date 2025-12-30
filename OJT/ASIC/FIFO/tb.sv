`timescale 1ns / 1ps

module tb_main #(
    parameter int NUM        = 10000,
    parameter int WIDTH      = 8,
    parameter int DEPTH      = 5,
    parameter int PFULL_TH   = 8,
    parameter int PEMPTY_TH  = 8,
    parameter int M_WRITERS  = 1,
    parameter int N_READERS  = 1
);
`include "ansi_display.svh"

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

localparam WR_WIDTH = WIDTH * N_READERS;

logic                       i_wr_clk;
logic                       i_wr_rstn;
logic [M_WRITERS-1:0]       i_wr_en;

logic                       o_wr_full;
logic                       o_wr_afull;
logic                       o_wr_pfull;
logic [DEPTH:0]             o_wr_remain;

logic [M_WRITERS*WIDTH-1:0] i_wr_data;//M:1
//logic [WR_WIDTH-1:0]        i_wr_data;//1:N

logic                       i_rd_clk;
logic                       i_rd_rstn;
logic [N_READERS-1:0]       i_rd_en;

logic                       o_rd_empty;
logic                       o_rd_aempty;
logic                       o_rd_pempty;
logic [DEPTH:0]             o_rd_depth;

logic [N_READERS*WIDTH-1:0] o_rd_data;

//logic [N_READERS-1:0]       o_rd_valid; // 1:N에서만 사용

//==============================================================================
// DUT
//==============================================================================

MtoOne_async_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH),
    .PFULL_TH(PFULL_TH),
    .PEMPTY_TH(PEMPTY_TH),
    .M_WRITERS(M_WRITERS),
    .N_READERS(N_READERS)
) dut(.*);

/*
OnetoN_async_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH),
    .PFULL_TH(PFULL_TH),
    .PEMPTY_TH(PEMPTY_TH),
    .M_WRITERS(M_WRITERS),
    .N_READERS(N_READERS),
    .WR_WIDTH(WR_WIDTH)
) dut(.*);
*/
//==============================================================================
// Clocks (Async)
//==============================================================================
initial begin
    i_wr_clk = 0;
    forever #1.25 i_wr_clk = ~i_wr_clk; // 400 MHz
end

initial begin
    i_rd_clk = 0;
    forever #4.0 i_rd_clk = ~i_rd_clk; // 125 MHz
end

assign i_wr_rstn = RSTN;
assign i_rd_rstn = RSTN_rd;

//==============================================================================
// Tasks (M:1)
//==============================================================================

logic [WIDTH*M_WRITERS-1:0] randvalue;
integer randi;

always @(posedge i_wr_clk or negedge i_wr_rstn) begin
    if(!i_wr_rstn) begin 
        randvalue <= '0;
    end else begin
        for (randi=0;randi<M_WRITERS;randi++) begin
            randvalue[randi*WIDTH +: WIDTH] <= $urandom_range(2**WIDTH-1,0); 
        end
    end
end

task automatic fifo_write(logic [WIDTH-1:0] data, logic [M_WRITERS-1:0] M);
int wa;
begin
    @(posedge i_wr_clk);
    i_wr_en = M;
    for (wa=0; wa<M_WRITERS; wa++) begin
        i_wr_data[wa*WIDTH +: WIDTH] = (data ^ wa[WIDTH-1:0]) | {{(WIDTH-1){1'b0}},1'b1};
    end
    @(posedge i_wr_clk);
    i_wr_en = 0;
    i_wr_data = '0;
end
endtask

task automatic fifo_read();
begin
    @(posedge i_rd_clk);
    i_rd_en = 1'b1;
    @(posedge i_rd_clk);
    i_rd_en = 1'b0;
end
endtask

//==============================================================================
// Tasks (1:N)
//==============================================================================
/*
logic [WR_WIDTH-1:0] randvalue;
integer randi;

always @(posedge i_wr_clk or negedge i_wr_rstn) begin
    if(!i_wr_rstn) begin 
        randvalue <= '0;
    end else begin
        for (randi=0;randi<8;randi++) begin
            randvalue[randi*WIDTH +: WIDTH] <= $urandom_range(2**WIDTH-1,0); 
        end
    end
end

task automatic fifo_write(logic [WR_WIDTH-1:0] data);
begin
    @(posedge i_wr_clk);
    i_wr_en = 1'b1;
    i_wr_data = data;
    @(posedge i_wr_clk);
    i_wr_en = 1'b0;
    i_wr_data = '0;
end
endtask

task automatic fifo_read(logic [N_READERS-1:0] N);
begin
    @(posedge i_rd_clk);
    i_rd_en = N;
    @(posedge i_rd_clk);
    i_rd_en = '0;
end
endtask
*/
//==============================================================================
// Stimulus
//==============================================================================
integer i;

initial begin
    i_wr_en   = '0;
    i_rd_en   = '0;
    i_wr_data = '0;

    wait(RSTN_rd);
    repeat (3) @(posedge i_wr_clk);
    repeat (3) @(posedge i_rd_clk);

    while (!o_wr_full) begin
        //fifo_write(randvalue); // 1:N
        fifo_write(randvalue, $urandom_range(2**M_WRITERS-1, 0)); // M:1
    end

    //repeat (10) fifo_read($urandom_range(2**N_READERS-1, 0)); // 1:N
    repeat (10) fifo_read(); // M:1

    fork
        begin : WR_THREAD
            for (int k = 0; k < NUM; k++) begin
                //fifo_write(randvalue); // 1:N
                fifo_write(randvalue, $urandom_range(2**M_WRITERS-1, 0)); // M:1
            end
        end

        begin : RD_THREAD
            for (int k = 0; k < NUM; k++) begin
                //fifo_read($urandom_range(2**N_READERS-1, 0)); // 1:N
                fifo_read();
            end
        end
    join_any

    while(!o_rd_aempty) begin 
        //fifo_read($urandom_range(2**N_READERS-1, 0)); // 1:N
        fifo_read(); // M:1
    end

    repeat (5) @(posedge i_rd_clk);

    $finish;
end
    //--------------------------------------------------------------------------
    // 파일 생성
    //--------------------------------------------------------------------------
    integer fd_wr, fd_rd;
    string wr_fname;
    string rd_fname;

    initial begin
    ////////////////////////// M:1 /////////////////////////////////
        wr_fname     = $sformatf("WRITE_DATA_M%0d.txt", M_WRITERS);
        rd_fname     = $sformatf("READ_DATA_M%0d.txt",  M_WRITERS);
        
    ////////////////////////// 1:N /////////////////////////////////
        //wr_fname     = $sformatf("WRITE_DATA_M%0d.txt", N_READERS);
        //rd_fname     = $sformatf("READ_DATA_M%0d.txt",  N_READERS);

        fd_wr = $fopen(wr_fname, "w");
        fd_rd = $fopen(rd_fname, "w");

        if (fd_wr == 0) begin
            $display("❌ DEBUG: failed to open %s", "WRITE_DATA");
            $finish;
        end
        if (fd_rd == 0) begin
            $display("❌ DEBUG: failed to open %s", "READ_DATA");
            $finish;
        end
    end

    ////////////////////////// M:1 /////////////////////////////////
    
    wire [M_WRITERS-1:0] wr_req = i_wr_en & {M_WRITERS{~o_wr_full}};
    integer wk;
    integer write_trial, read_trial;
    integer write_success, read_success;

    initial begin
        write_trial = 0;
        read_trial = 0;
        write_success = 0;
        read_success = 0;
    end

    always @(negedge i_wr_clk) begin
        // MUX
        for (wk=0; wk<M_WRITERS; wk=wk+1) begin
            if (wr_req[wk]) begin
                $fdisplay(fd_wr, "%d", i_wr_data[wk*WIDTH +: WIDTH]);
                write_success = write_success + 1;
            end
        end
        if (i_wr_en) begin
            write_trial = write_trial + 1;
        end
    end    
    
    wire rd_req = i_rd_en & (~o_rd_empty);
    always @(negedge i_rd_clk) begin
        if (rd_req) begin
            $fdisplay(fd_rd, "%d", o_rd_data);
            read_success = read_success + 1;
        end
        if (i_rd_en) begin
            read_trial = read_trial + 1;
        end
    end

    integer fd;
    initial begin 
        fd = $fopen($sformatf("final_M%0d.txt", M_WRITERS), "w"); 
    end

    final begin
        $fdisplay(fd, "FINAL REPORT(M:1) %d", M_WRITERS);
        $fdisplay(fd, "write trial = %d", write_trial);
        $fdisplay(fd, "write success = %d", write_success);
        $fdisplay(fd, "read trial = %d", read_trial);
        $fdisplay(fd, "read success = %d", read_success);
        $fclose(fd);
    end
////////////////////////// 1:N /////////////////////////////////
/*
    wire wr_req = i_wr_en & (~o_wr_full);
    integer wk;
    integer write_trial, read_trial;
    integer write_success, read_success;
    
    initial begin
        write_trial = 0;
        read_trial = 0;
        write_success = 0;
        read_success = 0;
    end

    always @(negedge i_wr_clk) begin
        if (wr_req) begin
            for (wk=0; wk<WR_WIDTH/WIDTH; wk=wk+1) begin
                $fdisplay(fd_wr, "%d", i_wr_data[wk*WIDTH +: WIDTH]);
            end
            write_success = write_success + 1;
        end
        if (i_wr_en) begin
            write_trial = write_trial + 1;
        end
    end
    
    integer rk;
    always @(negedge i_rd_clk) begin
        for (rk=0;rk<N_READERS;rk++) begin
            if (o_rd_valid[rk]) begin
                $fdisplay(fd_rd, "%d", o_rd_data[rk*WIDTH +: WIDTH]);
                read_success = read_success + 1;
            end        
            if (i_rd_en[rk]) begin
                read_trial = read_trial + 1;
            end    
        end
    end

    integer fd;
    initial begin 
        fd = $fopen($sformatf("final_N%0d.txt", N_READERS), "w"); 
    end

    final begin
        $fdisplay(fd, "FINAL REPORT(1:N) %d", N_READERS);
        $fdisplay(fd, "write trial = %d", write_trial);
        $fdisplay(fd, "write success = %d", write_success);
        $fdisplay(fd, "read trial = %d", read_trial);
        $fdisplay(fd, "read success = %d", read_success);
        $fclose(fd);
    end
    */

endmodule
