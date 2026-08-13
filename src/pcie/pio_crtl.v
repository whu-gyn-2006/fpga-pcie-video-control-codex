/*
	v1_0:pio控制
*/
module	pio_crtl
(
	input					pcie_clk			/* synthesis PAP_MARK_DEBUG="true" */,
	input					rst_n				,

	//crtl
	output					start_flag			/* synthesis PAP_MARK_DEBUG="true" */,
    output                  set_dma_config_en   /* synthesis PAP_MARK_DEBUG="true" */,
	output	[63:0]			o_ch0_base_addr		/* synthesis PAP_MARK_DEBUG="true" */,
	output	[63:0]			o_ch0_base_addr2    /* synthesis PAP_MARK_DEBUG="true" */,
	output	[63:0]			o_ch0_base_addr3	/* synthesis PAP_MARK_DEBUG="true" */,
	output	[63:0]			o_ch0_base_addr4	/* synthesis PAP_MARK_DEBUG="true" */,
	output  [31:0]          o_preproc_mode,
	output  [31:0]          o_threshold,
	output  [31:0]          o_roi_xy,
	output  [31:0]          o_roi_wh,
	output  [31:0]          o_debug_trig,
	output  [31:0]          o_frame_cfg,
    input                   i_wr_frame_done     /* synthesis PAP_MARK_DEBUG="true" */,
    input   [1:0]           i_wr_index          /* synthesis PAP_MARK_DEBUG="true" */,
	//
	input					pio_wr_en			/* synthesis PAP_MARK_DEBUG="true" */,
	input	[9:0]			pio_wr_addr			/* synthesis PAP_MARK_DEBUG="true" */,
	input	[31:0]			pio_wr_data			/* synthesis PAP_MARK_DEBUG="true" */,
	
	//
	input					pio_rd_en			/* synthesis PAP_MARK_DEBUG="true" */,
	input	[9:0]			pio_rd_addr			/* synthesis PAP_MARK_DEBUG="true" */,
	output	[31:0]			pio_rd_data		    /* synthesis PAP_MARK_DEBUG="true" */

);
//------------------寄存器----------------------------
parameter       WR_FRAME_DONE    =    10'h140    ;
parameter       DMA_ADDR_L  	 =    10'h050    ;
parameter       DMA_ADDR_H	   	 =    10'h054    ;    //
parameter       DMA_ADDR1_L  	 =    10'h020    ;
parameter       DMA_ADDR1_H	   	 =    10'h024    ;    //
parameter       DMA_ADDR2_L  	 =    10'h040    ;
parameter       DMA_ADDR2_H	   	 =    10'h044    ;    //
parameter       DMA_ADDR3_L  	 =    10'h030    ;
parameter       DMA_ADDR3_H	   	 =    10'h034    ;    //
parameter		DMA_SET_EN		 =	  10'h060	;
// BAR0 write/read data reaches the existing PIO path through the low 32-bit
// lane of a 128-bit/16-byte BAR adapter. Keep RK-visible control registers
// 16-byte aligned so both write data and readback data use that valid lane.
parameter       REG_MAGIC        =    10'h100    ;
parameter       REG_VERSION      =    10'h110    ;
parameter       REG_SCRATCH      =    10'h120    ;
parameter       REG_CAPTURE_CTRL =    10'h130    ;
parameter       REG_PREPROC_MODE =    10'h150    ;
parameter       REG_THRESHOLD    =    10'h160    ;
parameter       REG_ROI_XY       =    10'h170    ;
parameter       REG_ROI_WH       =    10'h180    ;
parameter       REG_DEBUG_TRIG   =    10'h190    ;
parameter       REG_FRAME_CFG    =    10'h1a0    ;
parameter       REG_CTRL_STATUS  =    10'h1b0    ;
//------------------reg------------------------------
reg				r_start_flag			;
reg				r_set_dma_config_en     ;
reg		[31:0]  r_pio_rd_data           ;
reg             r_wr_frame_done         ;
reg     [31:0]  r_scratch               ;
reg     [31:0]  r_capture_ctrl          ;
reg     [31:0]  r_preproc_mode          ;
reg     [31:0]  r_threshold             ;
reg     [31:0]  r_roi_xy                ;
reg     [31:0]  r_roi_wh                ;
reg     [31:0]  r_debug_trig            ;
reg     [31:0]  r_frame_cfg             ;
reg     [15:0]  r_cfg_write_count       ;
reg		[63:0]	r_ch0_base_addr			/* synthesis PAP_MARK_DEBUG="true" */;
reg		[63:0]	r_ch0_base_addr2		/* synthesis PAP_MARK_DEBUG="true" */;
reg		[63:0]	r_ch0_base_addr3		/* synthesis PAP_MARK_DEBUG="true" */;
reg		[63:0]	r_ch0_base_addr4		/* synthesis PAP_MARK_DEBUG="true" */;

//用户端
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_start_flag	<=	1'd0	;
	else	if(pio_wr_en && pio_wr_addr == 0 && pio_wr_data == 32'hffffffe5)	//开启
		r_start_flag	<=	1'd1	;
	else	if(pio_wr_en && pio_wr_addr == 0 && pio_wr_data == 32'hffffff00)	//关闭
		r_start_flag	<=	1'd0	;
	else
		r_start_flag	<=	r_start_flag	;
end

// RK3568可见配置寄存器。v1先只做读写闭环，后续再接入预处理和ROI逻辑。
always@(posedge pcie_clk)	begin
	if(!rst_n)	begin
        r_scratch          <=    32'd0    ;
        r_capture_ctrl    <=    32'd0    ;
        r_preproc_mode     <=    32'd0    ;
        r_threshold        <=    32'd0    ;
        r_roi_xy           <=    32'd0    ;
        r_roi_wh           <=    32'd0    ;
        r_debug_trig       <=    32'd0    ;
        r_frame_cfg        <=    32'd0    ;
        r_cfg_write_count  <=    16'd0    ;
    end
	else	if(pio_wr_en)	begin
        case(pio_wr_addr)
            REG_SCRATCH      :    r_scratch      <=    pio_wr_data    ;
            REG_CAPTURE_CTRL :    r_capture_ctrl <=    pio_wr_data    ;
            REG_PREPROC_MODE :    r_preproc_mode <=    pio_wr_data    ;
            REG_THRESHOLD    :    r_threshold    <=    pio_wr_data    ;
            REG_ROI_XY       :    r_roi_xy       <=    pio_wr_data    ;
            REG_ROI_WH       :    r_roi_wh       <=    pio_wr_data    ;
            REG_DEBUG_TRIG   :    r_debug_trig   <=    pio_wr_data    ;
            REG_FRAME_CFG    :    r_frame_cfg    <=    pio_wr_data    ;
            default          :    ;
        endcase

        if((pio_wr_addr == REG_SCRATCH) || (pio_wr_addr == REG_CAPTURE_CTRL) ||
           (pio_wr_addr == REG_PREPROC_MODE) || (pio_wr_addr == REG_THRESHOLD) ||
           (pio_wr_addr == REG_ROI_XY) || (pio_wr_addr == REG_ROI_WH) ||
           (pio_wr_addr == REG_DEBUG_TRIG) || (pio_wr_addr == REG_FRAME_CFG))
            r_cfg_write_count <= r_cfg_write_count + 16'd1;
    end
end

//内核
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_set_dma_config_en	<=	1'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_SET_EN && pio_wr_data == 32'h00000001)	//开启
		r_set_dma_config_en	<=	1'd1	;
	else
		r_set_dma_config_en	<=	1'd0	;
end


//低32
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_ch0_base_addr[31:0]	<=	'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_ADDR_L)
		r_ch0_base_addr[31:0]	<=	pio_wr_data	;
	else
		r_ch0_base_addr[31:0]	<=	r_ch0_base_addr[31:0]	;
end

//高32
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_ch0_base_addr[63:32]	<=	'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_ADDR_H)
		r_ch0_base_addr[63:32]	<=	pio_wr_data	;
	else
		r_ch0_base_addr[63:32]	<=	r_ch0_base_addr[63:32]	;
end

//低32
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_ch0_base_addr2[31:0]	<=	'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_ADDR1_L)
		r_ch0_base_addr2[31:0]	<=	pio_wr_data	;
	else
		r_ch0_base_addr2[31:0]	<=	r_ch0_base_addr2[31:0]	;
end

//高32
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_ch0_base_addr2[63:32]	<=	'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_ADDR1_H)
		r_ch0_base_addr2[63:32]	<=	pio_wr_data	;
	else
		r_ch0_base_addr2[63:32]	<=	r_ch0_base_addr2[63:32]	;
end

//低32
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_ch0_base_addr3[31:0]	<=	'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_ADDR2_L)
		r_ch0_base_addr3[31:0]	<=	pio_wr_data	;
	else
		r_ch0_base_addr3[31:0]	<=	r_ch0_base_addr3[31:0]	;
end

//高32
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_ch0_base_addr3[63:32]	<=	'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_ADDR2_H)
		r_ch0_base_addr3[63:32]	<=	pio_wr_data	;
	else
		r_ch0_base_addr3[63:32]	<=	r_ch0_base_addr3[63:32]	;
end

//低32
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_ch0_base_addr4[31:0]	<=	'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_ADDR3_L)
		r_ch0_base_addr4[31:0]	<=	pio_wr_data	;
	else
		r_ch0_base_addr4[31:0]	<=	r_ch0_base_addr4[31:0]	;
end

//高32
always@(posedge pcie_clk)	begin
	if(!rst_n)	
		r_ch0_base_addr4[63:32]	<=	'd0	;
	else	if(pio_wr_en && pio_wr_addr == DMA_ADDR3_H)
		r_ch0_base_addr4[63:32]	<=	pio_wr_data	;
	else
		r_ch0_base_addr4[63:32]	<=	r_ch0_base_addr4[63:32]	;
end


//写完一帧信号
always@(posedge pcie_clk)	begin
	if(!rst_n)	
        r_wr_frame_done    <=    1'd0    ;    
    else    if(pio_rd_en && pio_rd_addr == WR_FRAME_DONE)
        r_wr_frame_done    <=    1'd0    ;
    else    if(i_wr_frame_done)
        r_wr_frame_done    <=    1'd1    ;
    else
        r_wr_frame_done    <=    r_wr_frame_done    ;
end



//pio_read
always@(posedge pcie_clk)	begin
	if(!rst_n)
        r_pio_rd_data    <=    32'd0    ;
    else    if(pio_rd_en)    begin
        case(pio_rd_addr)
            REG_MAGIC        :    r_pio_rd_data    <=    32'h46504331;
            REG_VERSION      :    r_pio_rd_data    <=    32'h20260813;
            REG_SCRATCH      :    r_pio_rd_data    <=    r_scratch;
            REG_CAPTURE_CTRL :    r_pio_rd_data    <=    {31'd0,r_capture_ctrl[0]};
            REG_PREPROC_MODE :    r_pio_rd_data    <=    r_preproc_mode;
            REG_THRESHOLD    :    r_pio_rd_data    <=    r_threshold;
            REG_ROI_XY       :    r_pio_rd_data    <=    r_roi_xy;
            REG_ROI_WH       :    r_pio_rd_data    <=    r_roi_wh;
            REG_DEBUG_TRIG   :    r_pio_rd_data    <=    r_debug_trig;
            REG_FRAME_CFG    :    r_pio_rd_data    <=    r_frame_cfg;
            REG_CTRL_STATUS  :    r_pio_rd_data    <=    {12'd0,r_cfg_write_count,i_wr_index,r_wr_frame_done,r_start_flag};
            WR_FRAME_DONE    :    r_pio_rd_data    <=    {29'd0,i_wr_index,r_wr_frame_done};
            default          :    r_pio_rd_data    <=    32'd0;
        endcase
    end
end

//--------------------------------------------------------------------------------------
//开始
assign start_flag = r_start_flag	;
assign set_dma_config_en = r_set_dma_config_en    ;

assign pio_rd_data 	= r_pio_rd_data;
assign o_ch0_base_addr  = r_ch0_base_addr	;
assign o_ch0_base_addr2 = r_ch0_base_addr2	;
assign o_ch0_base_addr3 = r_ch0_base_addr3	;
assign o_ch0_base_addr4 = r_ch0_base_addr4	;
assign o_preproc_mode   = r_preproc_mode    ;
assign o_threshold      = r_threshold       ;
assign o_roi_xy         = r_roi_xy          ;
assign o_roi_wh         = r_roi_wh          ;
assign o_debug_trig     = r_debug_trig      ;
assign o_frame_cfg      = r_frame_cfg       ;
//-------------预留---------------



endmodule
