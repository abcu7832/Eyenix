//*****************************************************************************
//  File Name           : async_fifo.v
//-----------------------------------------------------------------------------
//  Description         : Asynchronous FIFO module
//-----------------------------------------------------------------------------
//  Date                : 2025.12.19
//  Designed by         : ycseo
//-----------------------------------------------------------------------------
//  Revision History:
//      1. 2025.12.19   : Created by ycseo
//*****************************************************************************
/*
module M_N_FIFO #( // 1:N FIFO
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
    output [ DEPTH:0] o_wr_remain,

    // read side
    input              i_rd_clk,
    input              i_rd_rstn,
    input              i_rd_en,// pop 역할
    output             o_rd_empty,
    output             o_rd_aempty,
    output             o_rd_pempty,
    output [WIDTH-1:0] o_rd_data,
    output [  DEPTH:0] o_rd_depth,

    // file 값들 -> 디버깅 모드 only
    output [     31:0] o_wr_count,
    output [     31:0] o_wr_trial,
    output [     31:0] o_wr_fail,
    output [     31:0] o_rd_count,
    output [     31:0] o_rd_trial,
    output [     31:0] o_rd_fail
);

    reg [WIDTH-1:0] rd_data, hold_register;
    reg hold_valid;

    assign o_rd_data = hold_register;

    always @(posedge i_rd_clk, negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            hold_register <= 0;
        end else begin
            hold_register <= rd_data;
        end
    end

    async_fifo #(
        .WIDTH(WIDTH),
        .DEPTH(DEPTH),
        .PFULL_TH(PFULL_TH),
        .PEMPTY_TH(PEMPTY_TH),
        .DEBUG_MODE(DEBUG_MODE) // 디버깅 모드(1), 합성 모드(0)
    ) U_async_fifo (
        // write side
        .i_wr_clk(i_wr_clk),
        .i_wr_rstn(i_wr_rstn),
        .i_wr_en(i_wr_en),// push 역할
        .o_wr_full(o_wr_full),
        .o_wr_afull(o_wr_afull),
        .o_wr_pfull(o_wr_pfull),
        .i_wr_data(i_wr_data),
        .o_wr_remain(o_wr_remain),

        // read side
        .i_rd_clk(i_rd_clk),
        .i_rd_rstn(i_rd_rstn),
        .i_rd_en(i_rd_en),// pop 역할
        .o_rd_empty(o_rd_empty),
        .o_rd_aempty(o_rd_aempty),
        .o_rd_pempty(o_rd_pempty),
        .o_rd_data(rd_data),
        .o_rd_depth(o_rd_depth),

        // file 값들 -> 디버깅 모드 only
        .o_wr_count(o_wr_count),
        .o_wr_trial(o_wr_trial),
        .o_wr_fail(o_wr_fail),
        .o_rd_count(o_rd_count),
        .o_rd_trial(o_rd_trial),
        .o_rd_fail(o_rd_fail)
    );
endmodule
*/

// 1:N FIFO (async_fifo + FWFT hold(prefetch) buffer + unpack fanout)
// - async_fifo는 그대로 인스턴스
// - hold_valid=0이고 FIFO not-empty면 rd_data를 hold에 "미리" 캡처(prefetch)
// - downstream이 i_rd_en으로 "이번 세트 소비"를 하면, 그때 FIFO pop(rinc)하여 다음 워드로 이동
module fifo_1toN #(
    parameter N         = 8,   // lane 개수
    parameter LANE_W    = 8,   // lane width (각 output 폭)
    // async_fifo 파라미터 (그대로 전달)
    parameter DEPTH     = 8,
    parameter PFULL_TH  = 10,
    parameter PEMPTY_TH = 10,
    parameter DEBUG_MODE = 0
)(
    // write side (wide write)
    input                         i_wr_clk,
    input                         i_wr_rstn,
    input                         i_wr_en,
    output                        o_wr_full,
    output                        o_wr_afull,
    output                        o_wr_pfull,
    input  [N*LANE_W-1:0]         i_wr_data,
    output [DEPTH:0]              o_wr_remain,

    // read side (set-level handshake)
    input                         i_rd_clk,
    input                         i_rd_rstn,
    input                         i_rd_en,      // "이번 1세트(=N lane) 소비" 의미
    output                        o_rd_empty,   // hold 기준 empty
    output                        o_rd_aempty,  // (선택) 아래에서 패스스루
    output                        o_rd_pempty,  // (선택) 아래에서 패스스루
    output [N*LANE_W-1:0]         o_rd_data,
    output [DEPTH:0]              o_rd_depth,   // (선택) 아래에서 패스스루

    // debug passthrough
    output [31:0]                 o_wr_count,
    output [31:0]                 o_wr_trial,
    output [31:0]                 o_wr_fail,
    output [31:0]                 o_rd_count,
    output [31:0]                 o_rd_trial,
    output [31:0]                 o_rd_fail
);

    localparam WIDTH = N*LANE_W;

    // async_fifo signals
    wire [WIDTH-1:0] fifo_rd_data;
    wire             fifo_empty;
    wire             fifo_aempty, fifo_pempty;
    wire             fifo_rd_en;

    // 1-deep hold buffer (read clock domain)
    reg [WIDTH-1:0] hold_data;
    reg             hold_valid;

    // -------------------------------
    // 핵심: FWFT prefetch + consume-pop
    //  - prefetch: hold 비었고 FIFO not-empty이면 hold에 rd_data를 캡처
    //  - consume:  hold_valid && i_rd_en이면 hold 비우고, 동시에 FIFO pop
    // -------------------------------
    wire prefetch = (~hold_valid) && (~fifo_empty);
    wire consume  = ( hold_valid) && ( i_rd_en);

    assign o_rd_aempty = fifo_aempty;
    assign o_rd_pempty = fifo_pempty;
    // FIFO pop은 "소비" 순간에만
    assign fifo_rd_en = consume;

    always @(posedge i_rd_clk or negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            hold_valid <= 1'b0;
            hold_data  <= 0;
        end else begin            
            // prefetch가 우선: hold를 채워두기
            if (prefetch) begin
                hold_data  <= fifo_rd_data;
                hold_valid <= 1'b1;
            end

            // consume: 이번 세트를 사용했으면 hold 비움 (다음 prefetch 준비)
            if (consume) begin
                hold_valid <= 1'b0;
            end
        end
    end

    // 외부에서 보는 empty는 hold 기준
    assign o_rd_empty = ~hold_valid;

    // hold_data를 N lane
    assign o_rd_data = hold_data;

    // --------------------------------
    // async_fifo instance (그대로)
    // --------------------------------
    async_fifo #(
        .WIDTH     (WIDTH),
        .DEPTH     (DEPTH),
        .PFULL_TH  (PFULL_TH),
        .PEMPTY_TH (PEMPTY_TH),
        .DEBUG_MODE(DEBUG_MODE)
    ) U_async_fifo (
        // write side
        .i_wr_clk    (i_wr_clk),
        .i_wr_rstn   (i_wr_rstn),
        .i_wr_en     (i_wr_en),
        .o_wr_full   (o_wr_full),
        .o_wr_afull  (o_wr_afull),
        .o_wr_pfull  (o_wr_pfull),
        .i_wr_data   (i_wr_data),
        .o_wr_remain (o_wr_remain),

        // read side
        .i_rd_clk    (i_rd_clk),
        .i_rd_rstn   (i_rd_rstn),
        .i_rd_en     (fifo_rd_en),       // <<< wrapper가 만든 rd_en
        .o_rd_empty  (fifo_empty),
        .o_rd_aempty (fifo_aempty),
        .o_rd_pempty (fifo_pempty),
        .o_rd_data   (fifo_rd_data),
        .o_rd_depth  (o_rd_depth),

        // debug
        .o_wr_count  (o_wr_count),
        .o_wr_trial  (o_wr_trial),
        .o_wr_fail   (o_wr_fail),
        .o_rd_count  (o_rd_count),
        .o_rd_trial  (o_rd_trial),
        .o_rd_fail   (o_rd_fail)
    );

endmodule
