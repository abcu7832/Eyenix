`timescale  1ns / 1ps

`include "ansi_display.svh"
module tb_main;
//=================================================================================================
// System
//=================================================================================================  
// Reset
    reg             RSTN;
    initial begin
        RSTN = 1'd0;
        #(50.0);
        RSTN = 1'd1;
    end

// Clock
`define         CLK_PERIOD_BASE         1000.0
`define         MCK_PERIOD              100.0
`define         PIXEL_CLK_PERIOD        74.25

    reg             MCK = 1'd0;
    reg             PIXEL_CLK = 1'd0;

    initial begin
        #7;
        forever #(`PIXEL_CLK_PERIOD/2.0) PIXEL_CLK = ~PIXEL_CLK;
    end

    initial begin
        #5;
        forever #(`MCK_PERIOD/2.0) MCK = ~MCK;
    end


    parameter INPUT_WIDTH  = 1920;
    parameter INPUT_HEIGHT = 1080;

    reg             init_done = 1'd0;

//=================================================================================================
// Video Sync Generator
//================================================================================================= 


//=================================================================================================
// DUT
//=================================================================================================

    parameter SYS_CLK_FREQ = 100;//모듈 내부에서 pixel clk 생성 안하니 필요 x
    parameter HACT = 16;
    parameter VACT = 1;
    parameter HSA = 4;
    parameter HBP = 4;
    parameter HFP = 4;
    parameter VSA = 1;
    parameter VBP = 1;
    parameter VFP = 1;
    parameter PCLK_MHZ = 16;//모듈 내부에서 pixel clk 생성 안하니 필요x
    parameter MIPI_SPEED = 80;//사용x
    parameter MIPI_DNUM = 1;//사용x

    wire    save_done;

    wire        hsync;
    wire        vsync;
    reg  [63:0] pixel_data;
    wire        pixel_valid;
    wire [ 5:0] data_type;

    top #(
        .SYS_CLK_FREQ(SYS_CLK_FREQ),
        .HACT(INPUT_WIDTH),
        .VACT(INPUT_HEIGHT),
        .HSA(HSA), 
        .HBP(HBP), 
        .HFP(HFP), 
        .VSA(VSA), 
        .VBP(VBP), 
        .VFP(VFP),
        .PCLK_MHZ(PCLK_MHZ),
        .MIPI_SPEED(MIPI_SPEED),
        .MIPI_DNUM(MIPI_DNUM)
    ) dut (
        .i_clk(PIXEL_CLK),
        .i_rstn(RSTN),
        .i_init_done(init_done),
        .o_hsync(hsync),
        .o_vsync(vsync),
        //.o_pixel_data(pixel_data),
        .o_pixel_valid(pixel_valid),
        .o_data_type(data_type)
    );

    localparam int PPC = 4;
    localparam int WORDS_PER_LINE = INPUT_WIDTH / PPC;
    localparam int TOTAL_WORDS    = (INPUT_WIDTH * INPUT_HEIGHT) / PPC;

    reg  [63:0] pixel_mem [0:TOTAL_WORDS-1];
    integer     word_idx;

    // HEX 파일 로드
    initial begin
        $display("[TB] Loading pixel_4ppc_1920x1080.hex ...");
        $readmemh("pixel_4ppc_1920x1080.hex", pixel_mem);
        $display("[TB] Load done. TOTAL_WORDS = %0d", TOTAL_WORDS);
    end

    img_save #(
        .IMG_WIDTH          (INPUT_WIDTH        ),
        .IMG_HEIGHT         (INPUT_HEIGHT       ),
        .CAPTURE_FRAMES     (1                  )
    )   IMG_SAVE (
        .i_clk              (PIXEL_CLK          ),
        .i_rstn             (RSTN               ),
        .i_hsync            (hsync              ),
        .i_vsync            (vsync              ),
        .i_pixel_data       (pixel_data         ),
        .i_pixel_valid      (pixel_valid        ),
        .i_data_type        (data_type          ),
        .o_save_done        (save_done          )
    );

    // TB에서 DUT o_pixel_data를 강제로 구동
    always @(posedge PIXEL_CLK or negedge RSTN) begin
        if (!RSTN) begin
            word_idx <= 0;
            pixel_data = 64'd0;
        end else if (init_done) begin
            if (pixel_valid) begin
                pixel_data = pixel_mem[word_idx];
                word_idx <= word_idx + 1;

                // 프레임 끝 → 다시 처음으로 (1프레임 반복)
                if (word_idx == TOTAL_WORDS-1)
                    word_idx <= 0;
            end
        end
    end
//=================================================================================================
// Stimulus
//=================================================================================================  

    initial begin
        wait(RSTN);
        #(500);
        init_done = 1'd1;

        // Wait for save done
        wait(save_done);

        #(10000);
        $finish;
    end

endmodule
