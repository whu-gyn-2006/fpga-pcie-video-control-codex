/*
    Simple RK-controlled video preprocessing stage.

    mode 0: bypass
    mode 1: brightness adjustment, threshold[7:0], 128 is neutral
    mode 2: contrast enhancement, threshold[7:0], 128 is neutral
    mode 3: ROI highlight, roi_xy={y,x}, roi_wh={h,w}; outside ROI is dimmed

    ROI zoom is performed by the RK preview after the FPGA marks the selected
    region. A full-frame zoom would require a frame/line buffer in this stage.
*/
module video_preproc
#(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720
)
(
    input               i_video_clk,
    input               i_rst_n,

    input       [23:0]  i_video_data,
    input               i_video_vs,
    input               i_video_de,

    input       [31:0]  i_preproc_mode,
    input       [31:0]  i_threshold,
    input       [31:0]  i_roi_xy,
    input       [31:0]  i_roi_wh,

    output      [23:0]  o_video_data,
    output              o_video_vs,
    output              o_video_de
);

reg             r_vs_d0;
reg     [15:0]  r_x_cnt;
reg     [15:0]  r_y_cnt;
reg     [23:0]  r_video_data;
reg             r_video_vs;
reg             r_video_de;

wire    [7:0]   w_r;
wire    [7:0]   w_g;
wire    [7:0]   w_b;
wire    [7:0]   w_threshold;
wire    [15:0]  w_roi_x;
wire    [15:0]  w_roi_y;
wire    [15:0]  w_roi_w;
wire    [15:0]  w_roi_h;
wire            w_roi_nonzero;
wire            w_roi_inside;
reg     [23:0]  r_preproc_data_next;
reg signed [10:0] light_r_calc;
reg signed [10:0] light_g_calc;
reg signed [10:0] light_b_calc;
reg signed [19:0] contrast_r_calc;
reg signed [19:0] contrast_g_calc;
reg signed [19:0] contrast_b_calc;

assign w_r = i_video_data[23:16];
assign w_g = i_video_data[15:8];
assign w_b = i_video_data[7:0];

assign w_threshold = i_threshold[7:0];

assign w_roi_x = i_roi_xy[15:0];
assign w_roi_y = i_roi_xy[31:16];
assign w_roi_w = i_roi_wh[15:0];
assign w_roi_h = i_roi_wh[31:16];
assign w_roi_nonzero = (w_roi_w != 16'd0) && (w_roi_h != 16'd0);
assign w_roi_inside =
    (!w_roi_nonzero) ||
    ((r_x_cnt >= w_roi_x) && (r_x_cnt < (w_roi_x + w_roi_w)) &&
     (r_y_cnt >= w_roi_y) && (r_y_cnt < (w_roi_y + w_roi_h)));

always @(*) begin
    // The adjustment midpoint is 128 so the default setting preserves the
    // source image. Saturation keeps the result in the RGB channel range.
    light_r_calc = $signed({1'b0,w_r}) + $signed({1'b0,w_threshold}) - 11'sd128;
    light_g_calc = $signed({1'b0,w_g}) + $signed({1'b0,w_threshold}) - 11'sd128;
    light_b_calc = $signed({1'b0,w_b}) + $signed({1'b0,w_threshold}) - 11'sd128;

    contrast_r_calc = ((($signed({1'b0,w_r}) - 9'sd128) *
                        $signed({1'b0,w_threshold})) >>> 7) + 20'sd128;
    contrast_g_calc = ((($signed({1'b0,w_g}) - 9'sd128) *
                        $signed({1'b0,w_threshold})) >>> 7) + 20'sd128;
    contrast_b_calc = ((($signed({1'b0,w_b}) - 9'sd128) *
                        $signed({1'b0,w_threshold})) >>> 7) + 20'sd128;

    case(i_preproc_mode[2:0])
        3'd1: r_preproc_data_next = {clamp8(light_r_calc),
                                      clamp8(light_g_calc),
                                      clamp8(light_b_calc)};
        3'd2: r_preproc_data_next = {clamp8(contrast_r_calc),
                                      clamp8(contrast_g_calc),
                                      clamp8(contrast_b_calc)};
        // Keep a dimmed context outside the ROI. The RK preview crops this
        // stream to the selected rectangle and scales it for a useful zoom.
        3'd3: r_preproc_data_next = w_roi_inside ? i_video_data :
                                    {2'b00, i_video_data[23:18],
                                     2'b00, i_video_data[15:10],
                                     2'b00, i_video_data[7:2]};
        default: r_preproc_data_next = i_video_data;
    endcase
end

function [7:0] clamp8;
    input signed [19:0] value;
    begin
        if(value < 20'sd0)
            clamp8 = 8'd0;
        else if(value > 20'sd255)
            clamp8 = 8'd255;
        else
            clamp8 = value[7:0];
    end
endfunction

always @(posedge i_video_clk) begin
    if(!i_rst_n)
        r_vs_d0 <= 1'b0;
    else
        r_vs_d0 <= i_video_vs;
end

always @(posedge i_video_clk) begin
    if(!i_rst_n) begin
        r_x_cnt <= 16'd0;
        r_y_cnt <= 16'd0;
    end
    else if(i_video_vs && !r_vs_d0) begin
        r_x_cnt <= 16'd0;
        r_y_cnt <= 16'd0;
    end
    else if(i_video_de) begin
        if(r_x_cnt == IMG_WIDTH - 1) begin
            r_x_cnt <= 16'd0;
            if(r_y_cnt == IMG_HEIGHT - 1)
                r_y_cnt <= 16'd0;
            else
                r_y_cnt <= r_y_cnt + 16'd1;
        end
        else begin
            r_x_cnt <= r_x_cnt + 16'd1;
        end
    end
end

always @(posedge i_video_clk) begin
    if(!i_rst_n) begin
        r_video_data <= 24'd0;
        r_video_vs   <= 1'b0;
        r_video_de   <= 1'b0;
    end
    else begin
        r_video_data <= r_preproc_data_next;
        r_video_vs   <= i_video_vs;
        r_video_de   <= i_video_de;
    end
end

// Keep mode 0 cycle-equivalent to the original video_crtl -> PCIe path.
// Processed modes use the registered outputs above so data and timing stay
// aligned through the arithmetic stage.
assign o_video_data = (i_preproc_mode[2:0] == 3'd0) ? i_video_data : r_video_data;
assign o_video_vs   = (i_preproc_mode[2:0] == 3'd0) ? i_video_vs   : r_video_vs;
assign o_video_de   = (i_preproc_mode[2:0] == 3'd0) ? i_video_de   : r_video_de;

endmodule
