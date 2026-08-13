# Version Register

## `codex-baseline-20260813-134325`

- Timestamp: `2026-08-13 13:43:25 +08:00`
- Origin: team `pcie_test_img_100h` project, copied into this independent
  Codex project
- Board result used for the A/B diagnosis: the original pure PCIe image
  produced complete and smooth 1280x720 frames on the RK3568
- Diagnostic source state: original video path and original `pcie_tx_fun.v`
  behavior, with the aligned BAR0 control interface retained in `pio_crtl.v`
- Preprocessing: not active in the diagnostic path
- Debugger: no stale FIC is included in the PDS project baseline
- RTL syntax check: ModelSim Errors 0, Warnings 0
- Repository: independent local Git repository created; GitHub remote pending
  because no remote URL or GitHub CLI authentication is configured yet

This entry describes the source baseline. It does not claim that this copied
baseline has been flashed after the latest source edits.

## `codex-control-nongating-20260813-140459`

- Timestamp: `2026-08-13 14:04:59 +08:00`
- `REG_VERSION` changed to `0x20260813` as a board-side bitstream fingerprint.
- `REG_CAPTURE_CTRL` is retained as a readable/writable shadow register, but
  no longer gates the legacy PCIe DMA start path.
- The legacy BAR0 commands `0xffffffe5` and `0xffffff00` remain the only
  hardware start/stop commands, matching the known-good pure PCIe flow.
- Removed Debugger-preservation attributes from unused preprocessor outputs so
  the control plane does not perturb the video implementation by default.
- Added a paired 14-bit Debugger FIC and post-synthesis Inserter recipe:
  `synthesize/hdmi_loop_syn_20260813_dma_debug.fic` and
  `scripts/debugger_make_20260813_dma_fic.tcl`.
- The FIC covers only the first-frame path: raw HDMI DE/VS, delayed DE/VS,
  video_crtl DE/VS, legacy start, VS reset, frame done/index, and PCIe AXIS
  valid/ready/last. It must only be used with the matching ADF.
## Stable Stage 06 - 2026-08-14

This branch contains the board-verified FPGA release with:

- mode 0 direct bypass
- mode 1 gain/brightness enhancement
- mode 2 contrast enhancement
- BAR0 control registers at 16-byte-aligned addresses
- unchanged legacy PCIe DMA/FIFO/start behavior

Source was synchronized from the verified
`baseline_reproduction/stage06_contrast` project. ROI/zoom is not part of this
stable release.
