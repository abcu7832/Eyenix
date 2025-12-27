module MtoN_async_fifo #(
    parameter WIDTH      = 8,
    parameter DEPTH      = 8,
    parameter PFULL_TH   = 10,
    parameter PEMPTY_TH  = 10,
    parameter M_WRITERS  = 2,
    parameter N_READERS  = 2
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
    output logic [DEPTH:0]             o_wr_remain,

    input logic [M_WRITERS*WIDTH-1:0]  i_wr_data,
    output logic [M_WRITERS-1:0]       o_wr_ed,

    // ----------------------------------------------------------------
    // read side (rd_clk domain)
    // ----------------------------------------------------------------
    input logic                        i_rd_clk,
    input logic                        i_rd_rstn,
    input logic [N_READERS-1:0]        i_rd_en,

    output logic                       o_rd_empty,
    output logic                       o_rd_aempty,
    output logic                       o_rd_pempty,
    output logic [DEPTH:0]             o_rd_depth,

    output logic [WIDTH-1:0]           o_rd_data
);
    localparam WRITE_IDX_WIDTH = (M_WRITERS <= 1) ? 1 : $clog2(M_WRITERS);
    localparam FIFO_MEM_SIZE = M_WRITERS*WIDTH + M_WRITERS;
    
    //localparam FIFO_MEM_SIZE = M_WRITERS*WIDTH;
    // =========================================================================
    // WRITE control (wr_clk)
    // =========================================================================
    logic [FIFO_MEM_SIZE-1:0] wr_data; // 1:1 async fifo로 전달됨.

    // fifo memory가 안 차있고, writer가 push 신호를 보내면 wr_req는 high
    wire [M_WRITERS-1:0] wr_req = i_wr_en & {M_WRITERS{~o_wr_full}};
    wire winc = |wr_req;  // 1:1 async fifo로 전달됨.

    assign o_wr_ed = wr_req;

    integer wk;
    always_comb begin
        wr_data = '0;
        // MUX
        for (wk=0; wk<M_WRITERS; wk=wk+1) begin
            if (wr_req[wk]) begin// wr_req = i_wr_en & {M_WRITERS{~o_wr_full}}
                wr_data[wk*WIDTH +: WIDTH] = i_wr_data[wk*WIDTH +: WIDTH];
            end
        end
        wr_data[FIFO_MEM_SIZE-1:FIFO_MEM_SIZE-M_WRITERS] = wr_req;
    end

    // =========================================================================
    // READ control (rd_clk) : N:1, CAPTURE first (FWFT), POP after consumed
    // =========================================================================
    typedef enum logic { 
        RD_WAIT=1'b0,
        RD_HAVE=1'b1
    } rd_state_e;

    rd_state_e st_q, st_d;

    logic rinc, rinc_d;

    logic [FIFO_MEM_SIZE-1:0] packet_q, packet_d;
    logic [M_WRITERS-1:0]     consumed_q, consumed_d;

    logic [FIFO_MEM_SIZE-1:0] rd_data;

    wire [M_WRITERS-1:0] mask_q  = packet_q[META_MSB: META_LSB];
    wire [M_WRITERS-1:0] avail_q = mask_q & ~consumed_q;

    localparam int META_MSB = FIFO_MEM_SIZE-1;
    localparam int META_LSB = FIFO_MEM_SIZE-M_WRITERS;

    always_ff @(posedge i_rd_clk or negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            st_q       <= RD_WAIT;
            packet_q   <= '0;
            consumed_q <= '0;
            rinc       <= 1'b0;
        end else begin
            st_q       <= st_d;
            packet_q   <= packet_d;
            consumed_q <= consumed_d;
            rinc       <= rinc_d;
        end
    end

    integer k;
    logic found;

    always_comb begin
        st_d       = st_q;
        packet_d   = packet_q;
        consumed_d = consumed_q;
        rinc_d     = 1'b0;
        o_rd_data  = '0;

        case (st_q)
            // FIFO에 데이터가 생기면 register(assign으로 나오는 rd_data)에 저장
            RD_WAIT: begin
                consumed_d = '0;
                if (!o_rd_empty) begin
                    if (rd_data[META_MSB: META_LSB] != '0) begin
                        packet_d = rd_data;
                        st_d     = RD_HAVE;
                    end                    
                end
            end
            // packet_q를 lane 단위로 하나씩 소비
            RD_HAVE: begin
                if (|i_rd_en) begin
                    found = 1'b0;
                    for (k=0; k<M_WRITERS; k++) begin
                        if (!found && avail_q[k]) begin
                            o_rd_data     = packet_q[k*WIDTH +: WIDTH];
                            consumed_d[k] = 1'b1;
                            found         = 1'b1;
                        end
                    end
                    // packet 내 valid data를 다 pop한 경우
                    if ((consumed_d & mask_q) == mask_q) begin
                        rinc_d     = 1'b1;   // fifo memory에서 새롭게 pop
                        consumed_d = '0;
                        st_d       = RD_WAIT;
                    end
                end
            end
        endcase
    end

    // =========================================================================
    // 1:1 async FIFO 
    // =========================================================================

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
        .winc        (winc),
        .wfull       (o_wr_full),
        .afull       (o_wr_afull),
        .pfull       (o_wr_pfull),
        .waddr       (waddr),
        .wptr        (wptr),
        .rwptr2      (rwptr2),
        .o_wr_remain (o_wr_remain)
    );

    sync #(.DEPTH(DEPTH)) u_sync_r2w (
        .clk   (i_wr_clk),
        .rst_n (i_wr_rstn),
        .ptr   (rptr),
        .ptr2  (rwptr2)
    );

    FIFO_Memory #(
        .WIDTH(FIFO_MEM_SIZE),
        .DEPTH(DEPTH)
    ) u_mem (
        .wclk   (i_wr_clk),
        .wdata  (wr_data),
        .wclken (winc && ~o_wr_full),
        .waddr  (waddr),
        .rdata  (rd_data),
        .raddr  (raddr)
    );

    sync #(.DEPTH(DEPTH)) u_sync_w2r (
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
