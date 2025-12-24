//*****************************************************************************
//  File Name           : async_fifo.v
//-----------------------------------------------------------------------------
//  Description         : Asynchronous FIFO module
//-----------------------------------------------------------------------------
//  Date                : 2025.12.15
//  Designed by         : ycseo
//-----------------------------------------------------------------------------
//  Revision History:
//      1. 2025.12.15   : Created by ycseo
//*****************************************************************************

module async_fifo #(
    parameter WIDTH = 8,
    parameter DEPTH = 8,
    parameter PFULL_TH = 10,
    parameter PEMPTY_TH = 10,
    parameter DEBUG_MODE = 0// 디버깅 모드(1), 합성 모드(0)
)(
    // write side
    input             i_wr_clk,
    input             i_wr_rstn,
    input             i_wr_en,// push 역할
    output            o_wr_full,
    output            o_wr_afull,
    output            o_wr_pfull,
    input [WIDTH-1:0] i_wr_data,
    output [DEPTH:0]  o_wr_remain,

    // read side
    input              i_rd_clk,
    input              i_rd_rstn,
    input              i_rd_en,// pop 역할
    output             o_rd_empty,
    output             o_rd_aempty,
    output             o_rd_pempty,
    output [WIDTH-1:0] o_rd_data,
    output [DEPTH:0]   o_rd_depth,

    // file 값들 -> 디버깅 모드 only
    output [31:0] o_wr_count,
    output [31:0] o_wr_trial,
    output [31:0] o_wr_fail,
    output [31:0] o_rd_count,
    output [31:0] o_rd_trial,
    output [31:0] o_rd_fail
);

    wire [DEPTH-1:0] waddr, raddr;
    wire [DEPTH:0] wptr, wrptr2, rptr, rwptr2;

    // 디버깅 모듈
    generate if (DEBUG_MODE) begin
        DEBUG #(
            .WIDTH(WIDTH),
            .DEPTH(DEPTH),
            .PFULL_TH(PFULL_TH),
            .PEMPTY_TH(PEMPTY_TH)
        ) U_DEBUG (
            // write side
            .wr_clk(i_wr_clk),
            .wr_rstn(i_wr_rstn),
            .wr_en(i_wr_en),
            .wr_full(o_wr_full),
            .wr_afull(o_wr_afull),
            .wr_pfull(o_wr_pfull),
            .wr_data(i_wr_data),

            // read side
            .rd_clk(i_rd_clk),
            .rd_rstn(i_rd_rstn),
            .rd_en(i_rd_en),
            .rd_empty(o_rd_empty),
            .rd_aempty(o_rd_aempty),
            .rd_pempty(o_rd_pempty),
            .rd_data(o_rd_data),

            // output
            .o_wr_count(o_wr_count),
            .o_wr_trial(o_wr_trial),
            .o_wr_fail(o_wr_fail),
            .o_rd_count(o_rd_count),
            .o_rd_trial(o_rd_trial),
            .o_rd_fail(o_rd_fail)
        );
    end
    endgenerate

    // write side
    wptr_full #(
        .DEPTH(DEPTH),
        .PFULL_TH(PFULL_TH)
    ) FIFO_wptr_full (
        .wclk(i_wr_clk),
        .wrst_n(i_wr_rstn),
        .winc(i_wr_en),
        .wfull(o_wr_full),
        .afull(o_wr_afull),
        .pfull(o_wr_pfull),
        .waddr(waddr),
        .wptr(wptr),
        .rwptr2(rwptr2),
        .o_wr_remain(o_wr_remain)
    );

    sync #(
        .DEPTH(DEPTH)
    ) sync_r2w (
        .clk(i_wr_clk),
        .rst_n(i_wr_rstn),
        .ptr(rptr),
        .ptr2(rwptr2)
    );

    FIFO_Memory #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    ) Dual_Port_RAM (
        // write side
        .wclk(i_wr_clk),
        .wdata(i_wr_data),
        .wclken(i_wr_en & ~o_wr_full), // winc & ~wfull
        .waddr(waddr),
        // read side
        .rdata(o_rd_data),
        .raddr(raddr)
    );

    // read side
    sync #(
        .DEPTH(DEPTH)
    ) sync_w2r (
        .clk(i_rd_clk),
        .rst_n(i_rd_rstn),
        .ptr(wptr),
        .ptr2(wrptr2)
    );

    rptr_empty #(
        .DEPTH(DEPTH),
        .PEMPTY_TH(PEMPTY_TH)
    ) FIFO_rptr_empty (
        .rclk(i_rd_clk),
        .rrst_n(i_rd_rstn),
        .rinc(i_rd_en),
        .rempty(o_rd_empty),
        .aempty(o_rd_aempty),
        .pempty(o_rd_pempty),
        .raddr(raddr),
        .rptr(rptr),
        .wrptr2(wrptr2),
        .o_rd_depth(o_rd_depth)
    );
endmodule

module FIFO_Memory #(
    parameter WIDTH = 8,
    parameter DEPTH = 8
) (
    // write side
    input wclk,
    input [WIDTH-1:0] wdata,
    input wclken, // winc
    input [DEPTH-1:0] waddr,
    // read side
    output [WIDTH-1:0] rdata,
    input [DEPTH-1:0] raddr
);
    localparam MEM_SIZE = (1 << DEPTH);

    reg [WIDTH-1:0] register_memory [0:MEM_SIZE-1];

    always @(posedge wclk) begin
        if (wclken) begin
            register_memory[waddr] <= wdata;  
        end
    end

    assign rdata = register_memory[raddr];
endmodule

module rptr_empty #(
    parameter DEPTH = 8,
    parameter PEMPTY_TH = 2
) (
    input rclk,
    input rrst_n,
    input rinc,
    output reg rempty,
    output reg aempty,
    output reg pempty,
    output [DEPTH-1:0] raddr,
    output reg [DEPTH:0] rptr,
    input [DEPTH:0] wrptr2,
    output [DEPTH:0] o_rd_depth
);
    
    assign o_rd_depth = occ_r;

    // gray code -> binary
    function automatic [DEPTH:0] gray2bin(input [DEPTH:0] g);
        integer i;
        begin
            gray2bin[DEPTH] = g[DEPTH];
            for (i = DEPTH-1; i >= 0; i=i-1) begin
                gray2bin[i] = gray2bin[i+1] ^ g[i];
            end
        end
    endfunction

    reg [DEPTH:0] rbin;
    wire [DEPTH:0] rgraynext, rbinnext;

    assign raddr = rbin[DEPTH-1:0];
    assign rbinnext = rbin + (rinc & ~rempty);// bin = bin + 1
    assign rgraynext = (rbinnext>>1) ^ rbinnext;// gray 변환

    wire [DEPTH:0] wbin_sync, occ_r;
    
    assign wbin_sync = gray2bin(wrptr2);// gray -> binary
    assign occ_r     = wbin_sync - rbinnext;

    wire rempty_val = (rgraynext == wrptr2);
    wire aempty_val = (occ_r == 1);// almost
    wire pempty_val = (occ_r <= PEMPTY_TH);// 이게 program empty

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            {rbin, rptr} <= 0;
        end else begin
            {rbin, rptr} <= {rbinnext, rgraynext};        
        end
    end

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rempty <= 1;
            aempty <= 0;
            pempty <= 1;
        end else begin
            rempty <= rempty_val; 
            aempty <= aempty_val;
            pempty <= pempty_val;
        end
    end
endmodule

module wptr_full #(
    parameter DEPTH = 8,
    parameter PFULL_TH = 2
) (
    input wclk, 
    input wrst_n,
    input winc,
    output reg wfull,
    output reg afull,
    output reg pfull,
    output [DEPTH-1:0] waddr,
    output reg [DEPTH:0] wptr,
    input [DEPTH:0] rwptr2,
    output [DEPTH:0] o_wr_remain
);

    assign o_wr_remain = (1<<DEPTH) - occ_w;

    function automatic [DEPTH:0] gray2bin(input [DEPTH:0] g);
        integer i;
        begin
            gray2bin[DEPTH] = g[DEPTH];
            for (i = DEPTH-1; i >= 0; i=i-1) begin
                gray2bin[i] = gray2bin[i+1] ^ g[i]; 
            end
        end
    endfunction

    reg  [DEPTH:0] wbin;
    wire [DEPTH:0] wgraynext, wbinnext;

    assign waddr = wbin[DEPTH-1:0];
    assign wbinnext = wbin + (winc & ~wfull);// bin = bin + 1
    assign wgraynext = (wbinnext>>1) ^ wbinnext;// gray 변환

    wire [DEPTH:0] rbin_sync;
    wire [DEPTH:0] occ_w;

    assign rbin_sync = gray2bin(rwptr2);
    assign occ_w     = wbinnext - rbin_sync;

    localparam DEPTH_S = (1<<DEPTH); //2^DEPTH
    wire wfull_val = (wgraynext=={~rwptr2[DEPTH:DEPTH-1], rwptr2[DEPTH-2:0]});
    wire afull_val = (occ_w == DEPTH_S - 1);
    wire pfull_val = (occ_w >= (DEPTH_S - PFULL_TH));// 이게 program full

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin 
            {wbin, wptr} <= 0;
        end else begin
            {wbin, wptr} <= {wbinnext, wgraynext};
        end
    end

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wfull <= 0;
            afull <= 0;
            pfull <= 0;
        end else begin
            wfull <= wfull_val;
            afull <= afull_val;
            pfull <= pfull_val;
        end
    end
endmodule

module sync #(
    parameter DEPTH = 8
) (
    input clk,
    input rst_n,
    input [DEPTH:0] ptr,
    output reg [DEPTH:0] ptr2
);
    reg [DEPTH:0] ptr1;

    always @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            {ptr2, ptr1} <= 0;
        end else begin
            {ptr2, ptr1} <= {ptr1, ptr};
        end
    end
endmodule

module DEBUG #(
    parameter WIDTH = 8,
    parameter DEPTH = 8,
    parameter PFULL_TH = 10,
    parameter PEMPTY_TH = 10
) (
    // write side
    input wr_clk,
    input wr_rstn,
    input wr_en,
    input wr_full,
    input wr_afull,
    input wr_pfull,
    input [WIDTH-1:0] wr_data,

    // read side
    input rd_clk,
    input rd_rstn,
    input rd_en,
    input rd_empty,
    input rd_aempty,
    input rd_pempty,
    input [WIDTH-1:0] rd_data,

    // output
    output [31:0] o_wr_count,
    output [31:0] o_wr_trial,
    output [31:0] o_wr_fail,
    output [31:0] o_rd_count,
    output [31:0] o_rd_trial,
    output [31:0] o_rd_fail
);
    integer wr_count, wr_trial, wr_fail;
    integer rd_count, rd_trial, rd_fail;

    wire [3:0] wr_condi = {wr_en, wr_full, wr_afull, wr_pfull};
    wire [3:0] rd_condi = {rd_en, rd_empty, rd_aempty, rd_pempty};
    
    assign o_wr_trial = wr_trial;
    assign o_wr_count = wr_count;
    assign o_wr_fail = wr_fail;
    assign o_rd_count = rd_count;
    assign o_rd_trial = rd_trial;
    assign o_rd_fail = rd_fail;

    always @(posedge wr_clk, negedge wr_rstn) begin
        if (!wr_rstn) begin
            wr_count <= 0;
            wr_trial <= 0;
            wr_fail <= 0;
        end else begin
            wr_trial <= wr_trial + (wr_condi[3]);
            wr_count <= wr_count + (wr_condi[3:2] == 2'b10);
            wr_fail <= wr_fail + (wr_condi[3:2] == 2'b11);
            case (wr_condi)
                4'b1101: $display("W @%0t FIFO FULL", $time);
                4'b1101: $display("FIFO FULL");
                4'b1011: $display("W @%0t FIFO ALMOST FULL", $time);
                4'b1001: $display("W @%0t FIFO PROGRAM FULL", $time);
                default: ; 
            endcase
        end
    end
    
    always @(posedge rd_clk, negedge rd_rstn) begin
        if (!rd_rstn) begin
            rd_count <= 0;
            rd_trial <= 0;
            rd_fail <= 0;
        end else begin
            rd_trial <= rd_trial + (rd_condi[3]);
            rd_count <= rd_count + (rd_condi[3:2] == 2'b10);
            rd_fail <= rd_fail + (rd_condi[3:2] == 2'b11);
            case (rd_condi)
                4'b1101: $display("R @%0t FIFO EMPTY", $time);
                4'b1011: $display("R @%0t FIFO ALMOST EMPTY", $time);
                4'b1001: $display("R @%0t FIFO PROGRAM EMPTY", $time);
                default: ;
            endcase
        end
    end
endmodule
