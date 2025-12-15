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
    parameter PEMPTY_TH = 10
)(
    // write side
    input i_wr_clk,
    input i_wr_rstn,
    input i_wr_en,// push 역할
    output o_wr_full,
    output o_wr_afull,
    output o_wr_pfull,
    input [WIDTH-1:0] i_wr_data,
    output [DEPTH:0] o_wr_remain,
    // read side
    input i_rd_clk,
    input i_rd_rstn,
    input i_rd_en,// pop 역할
    output o_rd_empty,
    output o_rd_aempty,
    output o_rd_pempty,
    output [WIDTH-1:0] o_rd_data,
    output [DEPTH:0] o_rd_depth
);

    wire [DEPTH-1:0] waddr, raddr;
    wire [DEPTH:0] wptr, wrptr2, rptr, rwptr2;

    // write side
    wptr_full #(
        .DEPTH(DEPTH),
        .AFULL_TH(PFULL_TH)
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
        .wclken(i_wr_en), // winc
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
        .AEMPTY_TH(PEMPTY_TH)
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
    parameter AEMPTY_TH = 2
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

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            {rbin, rptr} <= 0;
        end else begin
            {rbin, rptr} <= {rbinnext, rgraynext};        
        end
    end

    wire [DEPTH:0] wbin_sync, occ_r;
    
    assign wbin_sync  = gray2bin(wrptr2);// gray -> binary
    assign occ_r      = wbin_sync - rbinnext;

    wire rempty_val = (rgraynext == wrptr2);
    wire aempty_val = (occ_r == 1);// almost
    wire pempty_val = (occ_r <= AEMPTY_TH);// 이게 program empty

    always @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rempty <= 1;
            aempty <= 1;
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
    parameter AFULL_TH = 2
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

    always @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin 
            {wbin, wptr} <= 0;
        end else begin
            {wbin, wptr} <= {wbinnext, wgraynext};
        end
    end

    assign waddr = wbin[DEPTH-1:0];
    assign wbinnext = wbin + (winc & ~wfull);// bin = bin + 1
    assign wgraynext = (wbinnext>>1) ^ wbinnext;// gray 변환

    wire [DEPTH:0] rbin_sync;
    wire [DEPTH:0] occ_w;

    assign rbin_sync = gray2bin(rwptr2);
    assign occ_w     = wbinnext - rbin_sync;

    localparam integer DEPTH_S = (1<<DEPTH);
    wire wfull_val = (wgraynext=={~rwptr2[DEPTH:DEPTH-1], rwptr2[DEPTH-2:0]});
    wire afull_val = (occ_w == DEPTH_S - 1);
    wire pfull_val = (occ_w >= (DEPTH_S - AFULL_TH));// 이게 program full

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
