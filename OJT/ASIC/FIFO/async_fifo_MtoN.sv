`timescale 1ns / 1ps

module MtoOne_async_fifo #(
    parameter WIDTH     = 8,
    parameter DEPTH     = 8,
    parameter PFULL_TH  = 10,
    parameter PEMPTY_TH = 10,
    parameter M_WRITERS = 2,
    parameter N_READERS = 2
)(
    // ----------------------------------------------------------------
    // write side (wr_clk domain)
    // ----------------------------------------------------------------
    input                        i_wr_clk,
    input                        i_wr_rstn,
    input [M_WRITERS-1:0]        i_wr_en,

    output                       o_wr_full,
    output                       o_wr_afull,
    output                       o_wr_pfull,
    output [DEPTH:0]             o_wr_remain,

    input [M_WRITERS*WIDTH-1:0]  i_wr_data,

    // ----------------------------------------------------------------
    // read side (rd_clk domain)
    // ----------------------------------------------------------------
    input                        i_rd_clk,
    input                        i_rd_rstn,
    input [N_READERS-1:0]        i_rd_en,

    output                       o_rd_empty,
    output                       o_rd_aempty,
    output                       o_rd_pempty,
    output [DEPTH:0]             o_rd_depth,

    output reg [WIDTH-1:0]       o_rd_data
);
    localparam WRITE_IDX_WIDTH = (M_WRITERS <= 1) ? 1 : $clog2(M_WRITERS);
    localparam FIFO_MEM_WIDTH = M_WRITERS*WIDTH + M_WRITERS;
    
    // =========================================================================
    // WRITE control (wr_clk)
    // =========================================================================
    reg [FIFO_MEM_WIDTH-1:0] wr_data;

    wire [M_WRITERS-1:0] wr_req = i_wr_en & {M_WRITERS{~o_wr_full}};
    wire winc = |wr_req;

    integer wk;
    always @(*) begin
        wr_data = 0;
        // MUX
        for (wk=0; wk<M_WRITERS; wk=wk+1) begin
            if (wr_req[wk]) begin// wr_req = i_wr_en & {M_WRITERS{~o_wr_full}}
                wr_data[wk*WIDTH +: WIDTH] = i_wr_data[wk*WIDTH +: WIDTH];
            end
        end
        wr_data[FIFO_MEM_WIDTH-1:FIFO_MEM_WIDTH-M_WRITERS] = wr_req;
    end

    // =========================================================================
    // READ control (rd_clk) : M:1
    // =========================================================================
    parameter RD_WAIT = 1'b0, RD_HAVE = 1'b1;
    localparam META_MSB = FIFO_MEM_WIDTH - 1;
    localparam META_LSB = FIFO_MEM_WIDTH - M_WRITERS;
    
    reg state_reg, state_next;

    reg rinc, rinc_d;

    reg [FIFO_MEM_WIDTH-1:0] packet_q, packet_d;
    reg [M_WRITERS-1:0]     consumed_q, consumed_d;

    wire [FIFO_MEM_WIDTH-1:0] rd_data;

    wire [M_WRITERS-1:0] mask_q  = packet_q[META_MSB: META_LSB];
    wire [M_WRITERS-1:0] avail_q = mask_q & ~consumed_q;

    always @(posedge i_rd_clk or negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            state_reg  <= RD_WAIT;
            packet_q   <= 0;
            consumed_q <= 0;
            rinc       <= 1'b0;
        end else begin
            state_reg  <= state_next;
            packet_q   <= packet_d;
            consumed_q <= consumed_d;
            rinc       <= rinc_d;
        end
    end

    integer k;
    reg found;

    always @(*) begin
        state_next = state_reg;
        packet_d   = packet_q;
        consumed_d = consumed_q;
        rinc_d     = 1'b0;
        o_rd_data  = '0;

        case (state_reg)
            // FIFO에 데이터가 생기면 register(assign으로 나오는 rd_data)에 저장
            RD_WAIT: begin
                consumed_d = 0;
                if (!o_rd_empty) begin
                    if (rd_data[META_MSB: META_LSB] != 0) begin
                        packet_d   = rd_data;
                        rinc_d     = 1'b1;   // fifo memory에서 새롭게 pop
                        state_next = RD_HAVE;
                    end                    
                end
            end
            // packet_q를 lane 단위로 하나씩 소비
            RD_HAVE: begin
                if (|i_rd_en) begin
                    found = 1'b0;
                    for (k=0; k<M_WRITERS; k=k+1) begin
                        if (!found && avail_q[k]) begin
                            o_rd_data     = packet_q[k*WIDTH +: WIDTH];
                            consumed_d[k] = 1'b1;
                            found         = 1'b1;
                        end
                    end
                    // packet 내 valid data를 다 pop한 경우
                    if ((consumed_d & mask_q) == mask_q) begin
                        consumed_d = 0;
                        state_next = RD_WAIT;
                    end
                end
            end
        endcase
    end

    wire [DEPTH-1:0] waddr;
    wire [DEPTH-1:0] raddr;
    wire [DEPTH:0]   wptr;
    wire [DEPTH:0]   rptr;
    wire [DEPTH:0]   wrptr2;
    wire [DEPTH:0]   rwptr2;

    wptr_full #(
        .DEPTH   (DEPTH),
        .PFULL_TH(PFULL_TH)
    ) u_wptr_full (
        .wclk       (i_wr_clk),
        .wrst_n     (i_wr_rstn),
        .winc       (winc),
        .wfull      (o_wr_full),
        .afull      (o_wr_afull),
        .pfull      (o_wr_pfull),
        .waddr      (waddr),
        .wptr       (wptr),
        .rwptr2     (rwptr2),
        .o_wr_remain(o_wr_remain)
    );

    sync #(
        .DEPTH(DEPTH)
    ) u_sync_r2w (
        .clk   (i_wr_clk),
        .rst_n (i_wr_rstn),
        .ptr   (rptr),
        .ptr2  (rwptr2)
    );

    FIFO_Memory #(
        .WIDTH(FIFO_MEM_WIDTH),
        .DEPTH(DEPTH)
    ) u_mem (
        .wclk   (i_wr_clk),
        .wdata  (wr_data),
        .wclken (winc & ~o_wr_full),
        .waddr  (waddr),
        .rdata  (rd_data),
        .raddr  (raddr)
    );

    sync #(
        .DEPTH(DEPTH)
    ) u_sync_w2r (
        .clk   (i_rd_clk),
        .rst_n (i_rd_rstn),
        .ptr   (wptr),
        .ptr2  (wrptr2)
    );

    rptr_empty #(
        .DEPTH     (DEPTH),
        .PEMPTY_TH (PEMPTY_TH)
    ) u_rptr_empty (
        .rclk      (i_rd_clk),
        .rrst_n    (i_rd_rstn),
        .rinc      (rinc),
        .rempty    (o_rd_empty),
        .aempty    (o_rd_aempty),
        .pempty    (o_rd_pempty),
        .raddr     (raddr),
        .rptr      (rptr),
        .wrptr2    (wrptr2),
        .o_rd_depth(o_rd_depth)
    );
endmodule

// ----------------------------------------------------------------//
// -------------------------------1:N------------------------------//
// ----------------------------------------------------------------//
module OnetoN_async_fifo #(
    parameter WIDTH      = 8,
    parameter DEPTH      = 8,
    parameter PFULL_TH   = 10,
    parameter PEMPTY_TH  = 10,
    parameter M_WRITERS  = 1,
    parameter N_READERS  = 2,
    parameter WR_WIDTH   = 64
)(
    // ----------------------------------------------------------------
    // write side
    // ----------------------------------------------------------------
    input                            i_wr_clk,
    input                            i_wr_rstn,
    input [M_WRITERS-1:0]            i_wr_en,
    output                           o_wr_full,
    output                           o_wr_afull,
    output                           o_wr_pfull,
    input [WR_WIDTH-1:0]             i_wr_data,
    output [DEPTH:0]                 o_wr_remain,

    // ----------------------------------------------------------------
    // read side
    // ----------------------------------------------------------------
    input                            i_rd_clk,
    input                            i_rd_rstn,
    input [N_READERS-1:0]            i_rd_en,
    output                           o_rd_empty,
    output                           o_rd_aempty,
    output                           o_rd_pempty,
    output reg [N_READERS*WIDTH-1:0] o_rd_data,
    output [DEPTH:0]                 o_rd_depth,
    output reg [N_READERS-1:0]       o_rd_valid
);

    localparam LANES = WR_WIDTH / WIDTH;
    localparam FIFO_MEM_WIDTH = WR_WIDTH;

    // =========================================================================
    // READ control
    // =========================================================================
    function automatic [$clog2(N_READERS):0] rd_bit_cnt(input [N_READERS-1:0] g);
        integer i;
        begin
            rd_bit_cnt = 0;
            for (i=0;i<N_READERS;i=i+1) begin
                rd_bit_cnt = rd_bit_cnt + g[i];
            end
        end
    endfunction

    function automatic [$clog2(LANES):0] lane_bit_cnt(input [LANES-1:0] g);
        integer i;
        begin
            lane_bit_cnt = 0;
            for (i=0;i<LANES;i=i+1) begin
                lane_bit_cnt = lane_bit_cnt + g[i];
            end
        end
    endfunction

    parameter RD_WAIT = 1'b0, RD_HAVE = 1'b1;
    reg state_reg, state_next;

    wire [FIFO_MEM_WIDTH-1:0] rd_data;
    reg [FIFO_MEM_WIDTH-1:0] packet_q, packet_d;    // 현재 packet data
    reg [FIFO_MEM_WIDTH-1:0] packet1_q, packet1_d;  // 다음 packet data

    reg [LANES-1:0] consumed_q, consumed_d;
    reg [LANES-1:0] consumed1_q, consumed1_d;

    reg rinc_d, rinc;
    reg prefetch_v_q, prefetch_v_d; // packet1 valid

    wire [LANES-1:0] mask_q = {LANES{1'b1}};

    always @(posedge i_rd_clk or negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            state_reg    <= RD_WAIT;
            packet_q     <= 0;
            consumed_q   <= 0;
            packet1_q    <= 0;
            consumed1_q  <= 0;
            prefetch_v_q <= 1'b0;
            rinc         <= 1'b0;
        end else begin
            state_reg    <= state_next;
            packet_q     <= packet_d;
            consumed_q   <= consumed_d;
            packet1_q    <= packet1_d;
            consumed1_q  <= consumed1_d;
            prefetch_v_q <= prefetch_v_d;
            rinc         <= rinc_d;
        end
    end

    reg [$clog2(N_READERS):0] req_cnt;
    reg [$clog2(LANES):0] rem0;
    reg lane_found;

    integer r, l;
    always @(*) begin
        state_next   = state_reg;
        packet_d     = packet_q;
        consumed_d   = consumed_q;
        packet1_d    = packet1_q;
        consumed1_d  = consumed1_q;
        prefetch_v_d = prefetch_v_q;
        rinc_d       = 1'b0;
        o_rd_data    = 0;
        req_cnt      = rd_bit_cnt(i_rd_en);
        rem0         = (state_reg==RD_HAVE) ? (LANES - lane_bit_cnt(consumed_q)) : 0;
        o_rd_valid   = '0;

        // -------------------------
        // 0) packet_q가 모두 소비되면 shift (packet1 -> packet)
        // -------------------------
        if ((state_reg==RD_HAVE) && ((consumed_q & mask_q) == mask_q)) begin
            if (prefetch_v_q) begin
                packet_d     = packet1_q;
                consumed_d   = consumed1_q;
                state_next   = RD_HAVE;

                // prefetch 비우기
                packet1_d    = 0;
                consumed1_d  = 0;
                prefetch_v_d = 1'b0;
            end else begin
                // 다음 packet 없음
                state_next   = RD_WAIT;
                consumed_d   = 0;
            end
        end

        case (state_reg)
            //====================================================
            // RD_WAIT: packet_q가 비어있음 -> 1개 pop해서 packet_q 채움
            //====================================================
            RD_WAIT: begin
                if (!o_rd_empty) begin
                    packet_d   = rd_data;
                    consumed_d = 0;
                    rinc_d     = 1'b1; // POP
                    state_next = RD_HAVE;                    
                end
            end

            //====================================================
            // RD_HAVE: packet_q 서비스 + 필요 시 prefetch
            //====================================================
            RD_HAVE: begin
                if ((req_cnt > rem0) && !prefetch_v_q && !o_rd_empty) begin
                    packet1_d    = rd_data;
                    consumed1_d  = 0;
                    prefetch_v_d = 1'b1;
                    rinc_d       = 1'b1;  // POP
                end

                if (|i_rd_en) begin
                    for (r=0; r<N_READERS; r=r+1) begin
                        if (i_rd_en[r]) begin
                            lane_found = 1'b0;

                            // 1) packet_q에서 찾기
                            for (l=0; l<LANES; l=l+1) begin
                                if (!lane_found && (mask_q[l] && !consumed_d[l])) begin
                                    o_rd_data [r*WIDTH +: WIDTH] = packet_q[l*WIDTH +: WIDTH];
                                    consumed_d[l]                = 1'b1;
                                    lane_found                   = 1'b1;
                                end
                            end

                            // 2) packet1_q에서 찾기 (prefetch 유효할 때)
                            if (!lane_found && prefetch_v_d) begin
                                for (l=0; l<LANES; l=l+1) begin
                                    if (!lane_found && (mask_q[l] && !consumed1_d[l])) begin
                                        o_rd_data [r*WIDTH +: WIDTH] = packet1_d[l*WIDTH +: WIDTH];
                                        consumed1_d[l]               = 1'b1;
                                        lane_found                   = 1'b1;
                                    end
                                end
                            end
                            if (lane_found) begin 
                                o_rd_valid[r] = 1'b1; 
                            end
                        end
                    end
                end
            end
        endcase
    end
    
    wire [DEPTH-1:0] waddr;
    wire [DEPTH-1:0] raddr;
    wire [DEPTH:0]   wptr;
    wire [DEPTH:0]   rptr;
    wire [DEPTH:0]   wrptr2;
    wire [DEPTH:0]   rwptr2;

    wptr_full #(
        .DEPTH    (DEPTH),
        .PFULL_TH (PFULL_TH)
    ) u_wptr_full (
        .wclk       (i_wr_clk),
        .wrst_n     (i_wr_rstn),
        .winc       (i_wr_en & ~o_wr_full),
        .wfull      (o_wr_full),
        .afull      (o_wr_afull),
        .pfull      (o_wr_pfull),
        .waddr      (waddr),
        .wptr       (wptr),
        .rwptr2     (rwptr2),
        .o_wr_remain(o_wr_remain)
    );

    sync #(
        .DEPTH(DEPTH)
    ) u_sync_r2w (
        .clk  (i_wr_clk),
        .rst_n(i_wr_rstn),
        .ptr  (rptr),
        .ptr2 (rwptr2)
    );

    wire [WR_WIDTH-1:0] wr_data = i_wr_data;
    FIFO_Memory #(
        .WIDTH(FIFO_MEM_WIDTH),
        .DEPTH(DEPTH)
    ) u_mem (
        .wclk  (i_wr_clk),
        .wdata (wr_data),
        .wclken(i_wr_en & ~o_wr_full),
        .waddr (waddr),
        .rdata (rd_data),
        .raddr (raddr)
    );

    sync #(
        .DEPTH(DEPTH)
    ) u_sync_w2r (
        .clk  (i_rd_clk),
        .rst_n(i_rd_rstn),
        .ptr  (wptr),
        .ptr2 (wrptr2)
    );

    rptr_empty #(
        .DEPTH     (DEPTH),
        .PEMPTY_TH (PEMPTY_TH)
    ) u_rptr_empty (
        .rclk      (i_rd_clk),
        .rrst_n    (i_rd_rstn),
        .rinc      (rinc),
        .rempty    (o_rd_empty),
        .aempty    (o_rd_aempty),
        .pempty    (o_rd_pempty),
        .raddr     (raddr),
        .rptr      (rptr),
        .wrptr2    (wrptr2),
        .o_rd_depth(o_rd_depth)
    );

endmodule
