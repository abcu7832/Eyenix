module OnetoN_async_fifo #(
    parameter WIDTH      = 8,
    parameter DEPTH      = 8,
    parameter PFULL_TH   = 10,
    parameter PEMPTY_TH  = 10,
    parameter M_WRITERS  = 1,
    parameter N_READERS  = 2,
    parameter WR_WIDTH = 64
)(
    // ----------------------------------------------------------------
    // write side (wr_clk domain)
    // ----------------------------------------------------------------
    input logic                        i_wr_clk,
    input logic                        i_wr_rstn,
    input logic [M_WRITERS-1:0]        i_wr_en,
    output logic                       o_wr_full,
    output logic                       o_wr_afull,
    output logic                       o_wr_pfull,
    input logic [WR_WIDTH-1:0]         i_wr_data,
    output logic [DEPTH:0]             o_wr_remain,

    // ----------------------------------------------------------------
    // read side (rd_clk domain)
    // ----------------------------------------------------------------
    input logic                        i_rd_clk,
    input logic                        i_rd_rstn,
    input logic [N_READERS-1:0]        i_rd_en,
    output logic                       o_rd_empty,
    output logic                       o_rd_aempty,
    output logic                       o_rd_pempty,
    output logic [N_READERS*WIDTH-1:0] o_rd_data,
    output logic [DEPTH:0]             o_rd_depth
);

    localparam int LANES = WR_WIDTH / WIDTH;
    localparam int FIFO_MEM_SIZE = WR_WIDTH;

    function automatic [$clog2(N_READERS)-1:0] bit_cnt(input [N_READERS-1:0] g);
        integer i;
        begin
            bit_cnt = 0;
            for (i=0;i<N_READERS;i=i+1) begin
                bit_cnt = bit_cnt + g[i];
            end
        end
    endfunction

    typedef enum logic { 
        RD_WAIT=1'b0,
        RD_HAVE=1'b1
    } rd_state_e;

    rd_state_e st_q, st_d;

    logic prefetch_v_q, prefetch_v_d; // packet1 valid

    integer r, l;
    logic lane_found;

    logic [FIFO_MEM_SIZE-1:0] packet_q,   packet_d;    // 현재 word (packet0)
    logic [LANES-1:0]         consumed_q, consumed_d;

    logic [WR_WIDTH-1:0]        rd_data;
    logic [FIFO_MEM_SIZE-1:0] packet1_q,   packet1_d;  // 다음 word (prefetch)
    logic [LANES-1:0]         consumed1_q, consumed1_d;
    logic rinc_d, rinc;
    wire [LANES-1:0] mask_q  = '1;

    always_ff @(posedge i_rd_clk or negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            st_q         <= RD_WAIT;
            packet_q     <= '0;
            consumed_q   <= '0;
            packet1_q    <= '0;
            consumed1_q  <= '0;
            prefetch_v_q <= 1'b0;
            rinc         <= 1'b0;
        end else begin
            st_q         <= st_d;
            packet_q     <= packet_d;
            consumed_q   <= consumed_d;
            packet1_q    <= packet1_d;
            consumed1_q  <= consumed1_d;
            prefetch_v_q <= prefetch_v_d;
            rinc         <= rinc_d;
        end
    end

    // -------------------------
    // helper: 남은 lane 계산
    // -------------------------
    integer req_cnt;
    integer rem0;

    always_comb begin
        st_d         = st_q;

        packet_d     = packet_q;
        consumed_d   = consumed_q;

        packet1_d    = packet1_q;
        consumed1_d  = consumed1_q;
        prefetch_v_d = prefetch_v_q;

        rinc_d       = 1'b0;

        o_rd_data    = '0;

        req_cnt  = bit_cnt(i_rd_en);
        rem0     = (st_q==RD_HAVE) ? (LANES - bit_cnt(consumed_q)) : 0;

        // -------------------------
        // 0) packet_q가 모두 소비되면 shift (packet1 -> packet)
        // -------------------------
        if ((st_q==RD_HAVE) && ((consumed_q & mask_q) == mask_q)) begin
            if (prefetch_v_q) begin
                packet_d     = packet1_q;
                consumed_d   = consumed1_q;
                st_d         = RD_HAVE;

                // prefetch 비우기
                packet1_d    = '0;
                consumed1_d  = '0;
                prefetch_v_d = 1'b0;
            end else begin
                // 다음 packet 없음
                st_d         = RD_WAIT;
                consumed_d   = '0;
            end
        end

        case (st_q)
            //====================================================
            // RD_WAIT: packet_q가 비어있음 -> 1개 pop해서 packet_q 채움
            //====================================================
            RD_WAIT: begin
                if (!o_rd_empty) begin
                    packet_d   = rd_data;
                    consumed_d = '0;
                    st_d       = RD_HAVE;

                    rinc_d     = 1'b1; // POP
                end
            end

            //====================================================
            // RD_HAVE: packet_q 서비스 + 필요 시 prefetch
            //====================================================
            RD_HAVE: begin
                // -------- (A) prefetch 판단: "다음 사이클 초과"를 줄이기 위해 --------
                // 조건: 이번 사이클 요청 수 > 현재 packet 남은 lane 수(rem0) 인데,
                //       prefetch가 비어있고, fifo에도 데이터가 있으면 미리 채움
                if ((req_cnt > rem0) && !prefetch_v_q && !o_rd_empty) begin
                    packet1_d    = rd_data;
                    consumed1_d  = '0;
                    prefetch_v_d = 1'b1;

                    rinc_d       = 1'b1;  // POP
                end

                // -------- (B) multi-issue 배분: packet_q 우선, 부족하면 packet1 --------
                if (|i_rd_en) begin
                    // reader r마다 1lane 할당 (가능한 만큼)
                    for (r=0; r<N_READERS; r++) begin
                        if (i_rd_en[r]) begin
                            lane_found = 1'b0;

                            // 1) packet_q에서 찾기
                            for (l=0; l<LANES; l++) begin
                                if (!lane_found && (mask_q[l] && !consumed_d[l])) begin
                                    o_rd_data [r*WIDTH +: WIDTH] = packet_q[l*WIDTH +: WIDTH];
                                    consumed_d[l]                = 1'b1;
                                    lane_found                   = 1'b1;
                                end
                            end

                            // 2) packet1_q에서 찾기 (prefetch 유효할 때)
                            if (!lane_found && prefetch_v_d) begin
                                for (l=0; l<LANES; l++) begin
                                    if (!lane_found && (mask_q[l] && !consumed1_d[l])) begin
                                        o_rd_data [r*WIDTH +: WIDTH] = packet1_d[l*WIDTH +: WIDTH];
                                        consumed1_d[l]               = 1'b1;
                                        lane_found                   = 1'b1;
                                    end
                                end
                            end
                        end
                    end
                end

                // -------- (C) packet_q가 소진되면 다음 사이클에 shift 하도록 위에서 처리 --------
                // 여기서는 st_d 변경 안 함 (위 shift 로직이 st_d를 RD_WAIT/RD_HAVE로 바꿈)
            end
        endcase
    end

    logic [DEPTH-1:0] waddr;
    logic [DEPTH-1:0] raddr;
    logic [DEPTH:0]   wptr;
    logic [DEPTH:0]   rptr;
    logic [DEPTH:0]   wrptr2;
    logic [DEPTH:0]   rwptr2;

    wptr_full #(
        .DEPTH    (DEPTH),
        .PFULL_TH (PFULL_TH)
    ) u_wptr_full (
        .wclk        (i_wr_clk),
        .wrst_n      (i_wr_rstn),
        .winc        (i_wr_en),
        .wfull       (o_wr_full),
        .afull       (o_wr_afull),
        .pfull       (o_wr_pfull),
        .waddr       (waddr),
        .wptr        (wptr),
        .rwptr2      (rwptr2),
        .o_wr_remain (o_wr_remain)
    );

    sync #(
        .DEPTH(DEPTH)
    ) u_sync_r2w (
        .clk  (i_wr_clk),
        .rst_n(i_wr_rstn),
        .ptr  (rptr),
        .ptr2 (rwptr2)
    );

    FIFO_Memory #(
        .WIDTH(FIFO_MEM_SIZE),
        .DEPTH(DEPTH)
    ) u_mem (
        .wclk  (i_wr_clk),
        .wdata (i_wr_data),
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
