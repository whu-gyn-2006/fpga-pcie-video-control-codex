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
