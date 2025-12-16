`include "ansi_display.svh"
module img_save # (
    parameter IMG_WIDTH         = 1920,
    parameter IMG_HEIGHT        = 1080,
    parameter CAPTURE_FRAMES    = 5,
    parameter PIXEL_PER_CLOCK   = 4,
    parameter DEBUG             = 1
    )(
    input               i_clk,
    input               i_rstn,
    
    input               i_hsync,
    input               i_vsync,
    input       [63:0]  i_pixel_data,
    input               i_pixel_valid,
    input       [5:0]   i_data_type,

    output reg          o_save_done     // file save done signal
);

    // YUV422 Data Capture
    // [63:56] Y4, [55:48] V3, [47:40] Y3, [39:32] U3
    // [31:24] Y2, [23:16] V1, [15:8] Y1, [7:0] U1
    wire [7:0] U1, Y1, V1, Y2, U3, Y3, V3, Y4;
    assign U1 = i_pixel_data[7:0];
    assign Y1 = i_pixel_data[15:8];
    assign V1 = i_pixel_data[23:16];
    assign Y2 = i_pixel_data[31:24];
    assign U3 = i_pixel_data[39:32];
    assign Y3 = i_pixel_data[47:40];
    assign V3 = i_pixel_data[55:48];
    assign Y4 = i_pixel_data[63:56];


    // Internal Signals
    reg [31:0] frame_count;
    reg [31:0] pixel_count;
    reg [31:0] line_count;

    // File Handling
    integer yuv_file;
    reg [8*50-1:0] filename; // Filename string

    // Signal Declarations
    reg vsync_d1;
    reg hsync_d1;
    wire vsync_posedge;
    wire vsync_negedge;
    wire hsync_posedge;
    wire hsync_negedge;
    
    assign vsync_posedge = i_vsync & ~vsync_d1;
    assign vsync_negedge = ~i_vsync & vsync_d1;
    assign hsync_posedge = i_hsync & ~hsync_d1;
    assign hsync_negedge = ~i_hsync & hsync_d1;

    // vsync/hsync edge detection
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            vsync_d1 <= 1'b0;
            hsync_d1 <= 1'b0;
        end else begin
            vsync_d1 <= i_vsync;
            hsync_d1 <= i_hsync;
        end
    end

    // Counter 및 Control Logic
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            if (yuv_file != 0) begin
                $fclose(yuv_file);
                yuv_file = 0;
            end
            frame_count <= 32'd1;
            pixel_count <= 32'd0;
            line_count  <= 32'd1;
            o_save_done <= 1'b0;
        end else begin
            if (frame_count <= CAPTURE_FRAMES) begin
                if (vsync_posedge) begin // Frame start (vsync rising edge)

                    // Close previous file
                    if (yuv_file != 0) begin
                        $fclose(yuv_file);
                        yuv_file = 0;
                    end

                    // Open new file
                    $swrite(filename, "./_Out/img_%0dx%0d_frame_%0d.yuv", IMG_WIDTH, IMG_HEIGHT, frame_count);
                    yuv_file = $fopen(filename, "wb");
                    if (yuv_file == 0) begin
                        `DISP_FAIL_TAG($sformatf("Cannot open file for frame %0d", frame_count));
                    end else begin
                        `DISP_TEST_TAG($sformatf("Started capturing frame %0d", frame_count));
                    end

                    line_count <= 32'd1;
                end else if (hsync_negedge) begin
                    $display(" # Frame %0d: Line %0d ...", frame_count, line_count);
                    if (vsync_negedge) begin // Frame end (vsync falling edge)
                        frame_count <= frame_count + 1'd1;

                        // Save done for all frames
                        if (frame_count >= CAPTURE_FRAMES) begin
                            o_save_done <= 1'b1;
                        end

                        if (yuv_file != 0) begin
                            $fclose(yuv_file);
                            `DISP_NOTE_TAG($sformatf("Frame %0d saved: %0s (%0d pixels, %0d lines)", 
                                                    frame_count, filename, pixel_count, line_count));
                            yuv_file = 0;
                        end
                        
                        // All frames done message
                        if (frame_count>= CAPTURE_FRAMES) begin
                            `DISP_PASS_TAG($sformatf("All %0d frames captured successfully", CAPTURE_FRAMES));
                        end

                    end else begin
                        line_count <= line_count + 1'd1;
                    end
                end

                 if (vsync_posedge) begin
                    pixel_count <= 32'd0;
                 end else if (i_pixel_valid) begin
                    pixel_count <= pixel_count + PIXEL_PER_CLOCK;
                end
            end
        end
    end

//=========================================================================
// File save logic (Simulation Only)
//=========================================================================

    // File write
    always @(posedge i_clk) begin
        if (i_pixel_valid && yuv_file != 0) begin
            // YUV422 format: YUYV YUYV order
            // Pixel 1,2: Y1 U1 Y2 V1
            $fwrite(yuv_file, "%c", Y1);
            $fwrite(yuv_file, "%c", U1);
            $fwrite(yuv_file, "%c", Y2);
            $fwrite(yuv_file, "%c", V1);
            
            // Pixel 3,4: Y3 U3 Y4 V3
            $fwrite(yuv_file, "%c", Y3);
            $fwrite(yuv_file, "%c", U3);
            $fwrite(yuv_file, "%c", Y4);
            $fwrite(yuv_file, "%c", V3);
        end
    end

    generate if (DEBUG) begin: debug_block
        // Expected pixel count verification
        always @(posedge i_clk) begin
            if (vsync_negedge && pixel_count != IMG_WIDTH * IMG_HEIGHT) begin
                `DISP_WARN_TAG($sformatf("Pixel count mismatch! Expected: %0d, Got: %0d", 
                                        IMG_WIDTH * IMG_HEIGHT, pixel_count));
            end
        end
    end

    // Initial debug info
    initial begin
        `DISP_SECTION("=== Image Save Debug Mode Enabled ===");
        `DISP_NOTE($sformatf("Resolution: %0dx%0d", IMG_WIDTH, IMG_HEIGHT));
        `DISP_NOTE($sformatf("Pixels per clock: %0d", PIXEL_PER_CLOCK));
        `DISP_NOTE($sformatf("Capture frames: %0d", CAPTURE_FRAMES));
        `DISP_NOTE($sformatf("Expected pixels per frame: %0d", IMG_WIDTH * IMG_HEIGHT));
        `DISP_NOTE($sformatf("Expected clocks per line: %0d", IMG_WIDTH / PIXEL_PER_CLOCK));
    end

    endgenerate
endmodule
