# First-frame Debugger Scope

Timestamp: 2026-08-13 14:12 +08:00

The board currently reports PCIe Gen2 x2 and a healthy BAR0, but the FPGA
reports no completed frame. The board fingerprint remains `0x20260801`, so the
new non-gating source version has not been flashed yet.

The matching Debugger probe is intentionally limited to 14 signals:

`de_in`, `vs_in`, `r_hdmi_de_d1`, `r_hdmi_vs_d1`, `w_video_crtl_de`,
`w_video_crtl_vs`, `w_start_flag`, `r_vs_rst`, `frame_done`,
`r_wr_index_d0[1:0]`, `axis_master_tvalid_mem`, `axis_master_tready_mem`,
`axis_master_tlast_mem`.

Interpretation:

- Raw DE/VS inactive: HDMI input side is not producing an active video frame.
- Raw active but delayed inactive: input sampling or reset timing is wrong.
- Delayed active but video_crtl inactive: video control path is wrong.
- Video_crtl active but frame_done/index inactive: frame counter/reset logic is wrong.
- Frame_done active but AXIS valid/ready/last inactive: PCIe DMA output path is wrong.

No PIO bus, pixel data bus, or unrelated PCIe internal signal is included.

The active PDS project now references
`synthesize/hdmi_loop_syn_20260813_dma_debug.fic` under `wgt_my_fic_src`.
Close and reopen PDS so the GUI reloads the project entry before synthesis and
Device Map.

## Hardware result, 2026-08-13 14:51 +08:00

- Board fingerprint: `version=0x20260813`.
- PCIe endpoint: Gen2 x2; BAR0 reads/writes pass.
- Legacy start command was issued and `w_start_flag=1` for all 1024 samples.
- `de_in`, `vs_in`, delayed HDMI DE/VS, and `video_crtl` DE/VS stayed low for
  all 1024 samples with zero transitions.
- `frame_done`, write index, and AXIS valid stayed inactive as a consequence.
- AXIS ready stayed high, so the downstream PCIe path was available and was
  waiting for frame data.

Conclusion: the first frame is blocked at the HDMI input boundary, before
`video_crtl` and PCIe DMA. The next probe must remain input-only and separate
`pixclk_in` activity from MS7200 initialization/lock and DE/VS generation.
