module video_preproc
#(
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720
)
(
    input i_video_clk,
    input i_rst_n,
    input [23:0] i_video_data,
    input i_video_vs,
    input i_video_de,
    input [31:0] i_preproc_mode,
    input [31:0] i_threshold,
    input [31:0] i_roi_xy,
    input [31:0] i_roi_wh,
    output [23:0] o_video_data,
    output o_video_vs,
    output o_video_de
);
reg [23:0] r_video_data;
reg r_video_vs;
reg r_video_de;
wire signed [8:0]  brightness_delta = $signed({1'b0,i_threshold[7:0]}) - 9'sd128;
wire signed [19:0] bright_r_calc = (($signed({1'b0,i_video_data[23:16]}) - 9'sd128) * $signed({1'b0,i_threshold[7:0]})) >>> 7;
wire signed [19:0] bright_g_calc = (($signed({1'b0,i_video_data[15:8]}) - 9'sd128) * $signed({1'b0,i_threshold[7:0]})) >>> 7;
wire signed [19:0] bright_b_calc = (($signed({1'b0,i_video_data[7:0]}) - 9'sd128) * $signed({1'b0,i_threshold[7:0]})) >>> 7;
wire signed [19:0] bright_r = bright_r_calc + 20'sd128 + (brightness_delta >>> 1);
wire signed [19:0] bright_g = bright_g_calc + 20'sd128 + (brightness_delta >>> 1);
wire signed [19:0] bright_b = bright_b_calc + 20'sd128 + (brightness_delta >>> 1);
wire signed [19:0] contrast_r = (($signed({1'b0,i_video_data[23:16]}) - 9'sd128) *
                                  $signed({1'b0,i_threshold[7:0]})) >>> 7;
wire signed [19:0] contrast_g = (($signed({1'b0,i_video_data[15:8]}) - 9'sd128) *
                                  $signed({1'b0,i_threshold[7:0]})) >>> 7;
wire signed [19:0] contrast_b = (($signed({1'b0,i_video_data[7:0]}) - 9'sd128) *
                                  $signed({1'b0,i_threshold[7:0]})) >>> 7;

function [7:0] clamp8;
    input signed [10:0] value;
    begin
        if(value < 0)
            clamp8 = 8'd0;
        else if(value > 255)
            clamp8 = 8'd255;
        else
            clamp8 = value[7:0];
    end
endfunction

always @(posedge i_video_clk) begin
    if (!i_rst_n) begin
        r_video_data <= 24'd0;
        r_video_vs <= 1'b0;
        r_video_de <= 1'b0;
    end else begin
        r_video_data <= (i_preproc_mode[2:0] == 3'd1) ?
                        {clamp8(bright_r), clamp8(bright_g), clamp8(bright_b)} :
                        (i_preproc_mode[2:0] == 3'd2) ?
                        {clamp8(contrast_r + 20'sd128),
                         clamp8(contrast_g + 20'sd128),
                         clamp8(contrast_b + 20'sd128)} : i_video_data;
        r_video_vs <= i_video_vs;
        r_video_de <= i_video_de;
    end
end

// Mode 0 is direct bypass. Modes 1 and 2 are one-cycle aligned.
assign o_video_data = (i_preproc_mode[2:0] == 3'd0) ? i_video_data : r_video_data;
assign o_video_vs = (i_preproc_mode[2:0] == 3'd0) ? i_video_vs : r_video_vs;
assign o_video_de = (i_preproc_mode[2:0] == 3'd0) ? i_video_de : r_video_de;

endmodule
