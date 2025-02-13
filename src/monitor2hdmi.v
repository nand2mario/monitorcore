`timescale 1ns / 1ps

// This simply takes output from the overlay textdisp and upscale to 720p hdmi
module monitor2hdmi (
	input clk,      // snes clock
	input resetn,

    input overlay,
    output [7:0] overlay_x,
    output [7:0] overlay_y,
    input [14:0] overlay_color,

	// video clocks
	input clk_pixel,
	input clk_5x_pixel,
	input locked,

	// output signals
	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p
);

    localparam FRAMEWIDTH = 1280;       // 720P
    localparam FRAMEHEIGHT = 720;
    localparam TOTALWIDTH = 1650;
    localparam TOTALHEIGHT = 750;
    localparam SCALE = 5;
    localparam VIDEOID = 4;
    localparam VIDEO_REFRESH = 60.0;

    localparam IDIV_SEL_X5 = 3;
    localparam FBDIV_SEL_X5 = 54;
    localparam ODIV_SEL_X5 = 2;
    localparam DUTYDA_SEL_X5 = "1000";
    localparam DYN_SDIV_SEL_X5 = 2;
    
    localparam CLKFRQ = 74250;

    localparam AUDIO_BIT_WIDTH = 16;

    //
    // Video
    //
    wire [9:0] cy;              // hdmi x
    wire [10:0] cx;             // hdmi y
    reg [23:0] rgb;             // hdmi RGB output
    reg active;
    reg [7:0] xx;               // scaled-down pixel position
    reg [7:0] yy;
    reg [10:0] xcnt;
    reg [10:0] ycnt;            // fractional scaling counters
    reg [9:0] cy_r;
    assign overlay_x = xx;
    assign overlay_y = yy;
    localparam XSTART = (1280 - 960) / 2;   // 960:720 = 4:3
    localparam XSTOP = (1280 + 960) / 2;

    // address calculation
    // Assume the video occupies fully on the Y direction, we are upscaling the video by `720/height`.
    // xcnt and ycnt are fractional scaling counters.
    always @(posedge clk_pixel) begin
        reg active_t;
        reg [10:0] xcnt_next;
        reg [10:0] ycnt_next;
        xcnt_next = xcnt + 256;
        ycnt_next = ycnt + 224;

        active_t = 0;
        if (cx == XSTART - 1) begin
            active_t = 1;
            active <= 1;
        end else if (cx == XSTOP - 1) begin
            active_t = 0;
            active <= 0;
        end

        if (active_t | active) begin        // increment xx
            xcnt <= xcnt_next;
            if (xcnt_next >= 960) begin
                xcnt <= xcnt_next - 960;
                xx <= xx + 1;
            end
        end

        cy_r <= cy;
        if (cy[0] != cy_r[0]) begin         // increment yy at new lines
            ycnt <= ycnt_next;
            if (ycnt_next >= 720) begin
                ycnt <= ycnt_next - 720;
                yy <= yy + 1;
            end
        end

        if (cx == 0) begin
            xx <= 0;
            xcnt <= 0;
        end
        
        if (cy == 0) begin
            yy <= 0;
            ycnt <= 0;
        end 

    end

    // calc rgb value to hdmi
    always @(posedge clk_pixel) begin
        if (active) begin
            rgb <= {overlay_color[4:0],3'b0,overlay_color[9:5],3'b0,overlay_color[14:10],3'b0};       // BGR5 to RGB8
        end else
            rgb <= 24'h303030;
    end

    // HDMI output.
    logic[2:0] tmds;

    hdmi #( .VIDEO_ID_CODE(VIDEOID), 
            .DVI_OUTPUT(0), 
            .VIDEO_REFRESH_RATE(VIDEO_REFRESH),
            .IT_CONTENT(1),
            .AUDIO_RATE(AUDIO_OUT_RATE), 
            .AUDIO_BIT_WIDTH(AUDIO_BIT_WIDTH),
            .START_X(0),
            .START_Y(0) )

    hdmi( .clk_pixel_x5(clk_5x_pixel), 
          .clk_pixel(clk_pixel), 
          .clk_audio(clk_audio),
          .rgb(rgb), 
          .reset( ~resetn ),
          .audio_sample_word(audio_sample_word),
          .tmds(tmds), 
          .tmds_clock(tmdsClk), 
          .cx(cx), 
          .cy(cy),
          .frame_width(),
          .frame_height() );

    // Gowin LVDS output buffer
    ELVDS_OBUF tmds_bufds [3:0] (
        .I({clk_pixel, tmds}),
        .O({tmds_clk_p, tmds_d_p}),
        .OB({tmds_clk_n, tmds_d_n})
    );

endmodule
