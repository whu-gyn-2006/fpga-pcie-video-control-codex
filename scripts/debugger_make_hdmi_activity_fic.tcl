# DRAFT ONLY: do not run this script.
#
# cdt_ins 2022.2 reorders numeric net indices on each ADF parse. A previous
# version of this recipe therefore connected HDMI names to unrelated PCIe
# nets. The reliable next step is to create this probe in the PDS Fabric
# Inserter GUI against the current ADF, then save the GUI-generated FIC.
ins_new D:/a_fpga/codex/5_12_HDMI_IN_DDR3_HDMI_OUT/else/1/pcie_test_img_100h/synthesize/hdmi_loop_syn_hdmi_activity.fic
ins_set_file -input D:/a_fpga/codex/5_12_HDMI_IN_DDR3_HDMI_OUT/else/1/pcie_test_img_100h/synthesize/hdmi_loop_syn.adf
ins_add_core 1
ins_set_core -core 0 -enable_sq 0 -seq_level 1 -data_same 1 -data_depth 10 -clock_edge 1 -trig_num 1 -power 0 -multi_windows 0
ins_set_trig -core 0 -trig 0 -counter 0 -unit_num 1 -type 1 -as_data 1
ins_set_net -core 0 -clock -connect 9141
# Current ADF net indices:
# w_start_flag=11035, frame_done=11772, hs_in=8105,
# w_video_crtl_de=1214, w_video_crtl_vs=4526,
# w_preproc_de=2648, w_preproc_vs=650.
ins_set_net -core 0 -trig 0 -connect "11035 11772 8105 1214 4526 2648 650"
ins_core_info -core 0 -trig 0 -unit 0
ins_save D:/a_fpga/codex/5_12_HDMI_IN_DDR3_HDMI_OUT/else/1/pcie_test_img_100h/synthesize/hdmi_loop_syn_hdmi_activity.fic
