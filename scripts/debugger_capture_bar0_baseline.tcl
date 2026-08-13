dbg_connect -ip 127.0.0.1 -port 65420
dbg_scan_chain
dbg_import_fic -file D:/a_fpga/codex/5_12_HDMI_IN_DDR3_HDMI_OUT/else/1/pcie_test_img_100h/synthesize/hdmi_loop_syn_20260813_bar0_baseline.fic
dbg_set_cur_core -device 0 -core 0
dbg_set_capture -type 1 -samples 1024
dbg_add_all_to_waveform
dbg_add_all_to_listing
dbg_trig_immd
dbg_close
