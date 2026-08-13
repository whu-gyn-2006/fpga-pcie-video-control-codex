# Run after synthesis has produced the ADF for this exact project.
# Only first-frame generation checkpoints are probed.
set root "D:/a_fpga/codex/5_12_HDMI_IN_DDR3_HDMI_OUT/else/1/fpga_pcie_video_control_codex"
set adf "$root/synthesize/hdmi_loop_syn.adf"
set fic "$root/synthesize/hdmi_loop_syn_20260813_dma_debug.fic"
ins_new $fic
ins_set_file -input $adf
ins_add_core 1
ins_set_core -core 0 -enable_sq 0 -seq_level 1 -data_same 1 -data_depth 10 -clock_edge 1 -trig_num 1 -power 0 -multi_windows 0
ins_set_trig -core 0 -trig 0 -counter 0 -unit_num 1 -type 1 -as_data 1
ins_set_net -core 0 -clock -connect {pclk_div2}
ins_set_net -core 0 -trig 0 -connect {de_in vs_in r_hdmi_de_d1 r_hdmi_vs_d1 w_video_crtl_de w_video_crtl_vs w_start_flag r_vs_rst frame_done r_wr_index_d0[1:0] axis_master_tvalid_mem axis_master_tready_mem axis_master_tlast_mem}
ins_core_info -core 0 -trig 0 -unit 0
ins_save $fic
