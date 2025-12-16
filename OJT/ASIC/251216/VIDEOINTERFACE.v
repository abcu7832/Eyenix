module top #(
    parameter SYS_CLK_FREQ = 100,// MHz 단위
    parameter HACT = 16,// Active pixels per line
    parameter VACT = 1, // Active video lines
    parameter HSA = 1, // hsync 펄스폭
    parameter HBP = 1, // back porch
    parameter HFP = 1, // front porch
    parameter VSA = 1, // vsync 펄스폭
    parameter VBP = 1, //
    parameter VFP = 1,
    parameter PCLK_MHZ = 16,//클럭 주파수
    parameter MIPI_SPEED = 80,//사용x
    parameter MIPI_DNUM = 1//사용x
) (
    input         i_clk,
    input         i_rstn,
    input         i_init_done,
    output        o_hsync,
    output        o_vsync,
    output [63:0] o_pixel_data,
    output        o_pixel_valid,
    output [ 5:0] o_data_type
);
    localparam HACT_4 = HACT / 4;
    localparam HSA_4 = HSA / 4;
    localparam HBP_4 = HBP / 4;
    localparam HFP_4 = HFP / 4;
    // pixel data 1clk당 4개씩 나가는 구조 이므로 4 나눠줌.
    localparam H_MAX = HFP_4 + HACT_4 + HBP_4;
    localparam V_MAX = VFP + VACT + VBP;
//----------------------------------------------------//
    wire pixel_valid;
    wire [$clog2(H_MAX)-1:0] h_counter;
    wire [$clog2(V_MAX)-1:0] v_counter;
    wire [63:0] pixel_data;

    assign o_pixel_data = pixel_data;
    assign o_pixel_valid = pixel_valid;
    assign o_data_type = 6'h1E;

    COLORBAR #(
        .H_MAX(H_MAX),
        .V_MAX(V_MAX),
        .HACT(HACT_4),
        .VACT(VACT)
    ) U_COLORBAR (
        .pixel_valid(pixel_valid),
        .h_counter(h_counter),
        .v_counter(v_counter),
        .pixel_data(pixel_data)
    );

    video_sync_gen #(
        .SYS_CLK_FREQ(SYS_CLK_FREQ),
        .HACT(HACT),
        .VACT(VACT), 
        .HSA(HSA), 
        .HBP(HBP), 
        .HFP(HFP), 
        .VSA(VSA), 
        .VBP(VBP), 
        .VFP(VFP),
        .PCLK_MHZ(PCLK_MHZ)
    ) U_video_sync_gen (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_init_done(i_init_done),
        .o_hsync(o_hsync),
        .o_vsync(o_vsync),
        .o_pixel_valid(pixel_valid),
        .o_h_counter(h_counter),
        .o_v_counter(v_counter)        
    );
endmodule

module COLORBAR #(
    parameter H_MAX = 800,
    parameter V_MAX = 525,
    parameter HACT = 16,
    parameter VACT = 1
) (
    input                     pixel_valid,
    input [$clog2(H_MAX)-1:0] h_counter,
    input [$clog2(V_MAX)-1:0] v_counter,
    output [            63:0] pixel_data
);
    localparam DIV = (HACT >> 3);
    // reg Y4, V3, Y3, U3, Y2, V1, Y1, U1;
    reg [63:0] r_pixel_data;

    assign pixel_data = (pixel_valid) ? r_pixel_data : 64'h0;

    always @(*) begin
        if (h_counter < DIV) begin
            r_pixel_data = 64'hEB80EB80EB80EB80;
        end else if (h_counter < DIV * 2) begin
            r_pixel_data = 64'hD292D210D292D210;
        end else if (h_counter < DIV * 3) begin
            r_pixel_data = 64'hAA10AAA6AA10AAA6;
        end else if (h_counter < DIV * 4) begin
            r_pixel_data = 64'h9122913691229136;
        end else if (h_counter < DIV * 5) begin
            r_pixel_data = 64'h6ADE6ACA6ADE6ACA;
        end else if (h_counter < DIV * 6) begin
            r_pixel_data = 64'h51F0515A51F0515A;
        end else if (h_counter < DIV * 7) begin
            r_pixel_data = 64'h296E29F0296E29F0;
        end else begin
            r_pixel_data = 64'h1080108010801080;
        end
    end
endmodule

module video_sync_gen #(
    parameter SYS_CLK_FREQ = 100,
    parameter HACT = 16,
    parameter VACT = 1, 
    parameter HSA = 1, 
    parameter HBP = 1, 
    parameter HFP = 1, 
    parameter VSA = 1, 
    parameter VBP = 1, 
    parameter VFP = 1,
    parameter PCLK_MHZ = 16
)(
    input  i_clk,
    input  i_rstn,
    input  i_init_done,
    output o_hsync,
    output o_vsync,
    output o_pixel_valid,
    output [$clog2(H_MAX)-1:0] o_h_counter,
    output [$clog2(V_MAX)-1:0] o_v_counter
);
    localparam HACT_4 = HACT / 4;
    localparam HSA_4 = HSA / 4;
    localparam HBP_4 = HBP / 4;
    localparam HFP_4 = HFP / 4;
    // pixel data: 1 clk당 4개씩 나가는 구조 이므로 parameter 4 나눠줌.
    localparam H_MAX = HFP_4 + HACT_4 + HBP_4 + HSA_4;// horizon에만 해당
    localparam V_MAX = VFP + VACT + VBP + VSA;

    //wire clk_pixel;
    wire [$clog2(H_MAX)-1:0] h_counter;
    wire [$clog2(V_MAX)-1:0] v_counter;
    wire pixel_valid;

    assign o_pixel_valid = pixel_valid;
    assign o_h_counter = h_counter;
    assign o_v_counter = v_counter;

    vga_decoder #(
        .H_MAX(H_MAX),
        .V_MAX(V_MAX),
        .HACT(HACT_4),
        .VACT(VACT),
        .HFP(HFP_4),
        .VFP(VFP),
        .HSA(HSA_4),
        .VSA(VSA),
        .HBP(HBP_4),
        .VBP(VBP)
    ) U_VGA_DECODER (
        .clk_pixel(i_clk),
        .rstn(i_rstn),
        .init_done(i_init_done),
        .h_sync(o_hsync),
        .v_sync(o_vsync),
        .pixel_valid(pixel_valid),
        .h_counter(h_counter),
        .v_counter(v_counter)
    );
/*
    pixel_clk_gen #(
        .SYS_CLK_FREQ(SYS_CLK_FREQ),
        .PCLK_MHZ(PCLK_MHZ)
    ) U_PIXEL_CLK_GEN (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .init_done(i_init_done),
        .clk_pixel(clk_pixel)
    );
*/
endmodule

module vga_decoder #(
    parameter H_MAX = 800,
    parameter V_MAX = 525,
    parameter HACT = 16,
    parameter VACT = 1,
    parameter HFP = 1,
    parameter VFP = 1,
    parameter HSA = 1,
    parameter VSA = 1,
    parameter HBP = 1, 
    parameter VBP = 1
) (
    input  clk_pixel,
    input  rstn,
    input  init_done,
    output h_sync,
    output v_sync,
    output pixel_valid,
    output reg [$clog2(H_MAX)-1:0] h_counter,
    output reg [$clog2(V_MAX)-1:0] v_counter
);
    
    always @(negedge clk_pixel, negedge rstn) begin
        if (!rstn) begin
            h_counter <= 0;
            v_counter <= 0;
        end else if (!init_done) begin
            h_counter <= 0;
            v_counter <= 0;        
        end else begin
            if (h_counter == H_MAX - 1) begin
                h_counter <= 0;
                if (v_counter == V_MAX - 1) begin
                    v_counter <= 0;
                end else begin
                    v_counter <= v_counter + 1; 
                end
            end else begin
                h_counter <= h_counter + 1; // 1clk에 4개 픽셀데이터
            end
        end
    end

    assign h_sync = !(h_counter < HSA);
    assign v_sync = !((v_counter >= (VACT + VFP + VBP)) && (v_counter < (VACT + VFP + VSA + VBP)));
    assign pixel_valid = (((h_counter >= (HSA + HBP)) && (h_counter < (HSA + HBP + HACT))) && (v_counter >= VBP) && (v_counter < (VACT + VBP)));

endmodule

module pixel_clk_gen #(
    parameter SYS_CLK_FREQ = 100,
    parameter PCLK_MHZ = 16
) (
    input      i_clk,
    input      i_rstn,
    input      init_done,
    output reg clk_pixel
);
    localparam PIXEL_CNT = SYS_CLK_FREQ / PCLK_MHZ;
    reg [$clog2(PIXEL_CNT)-1:0] pcnt;

    always @(posedge i_clk, negedge i_rstn) begin
        if (!i_rstn) begin
            pcnt <= 0;
            clk_pixel <= 0;
        end else if (!init_done) begin
            pcnt <= 0;
            clk_pixel <= 0;
        end else begin
            if (pcnt == PIXEL_CNT - 1) begin
                pcnt <= 0;
                clk_pixel <= 1;
            end else begin
                pcnt <= pcnt + 1;
                clk_pixel <= 0; 
            end
        end
    end
endmodule
