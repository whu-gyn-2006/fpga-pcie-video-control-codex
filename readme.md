# FPGA PCIe Video Control Codex

This is a separate Codex-maintained project derived from the team's original
`pcie_test_img_100h` FPGA project. It is intentionally not the original team
repository and has no shared Git history with it.

## Purpose

Maintain reproducible FPGA-side iterations for:

`HDMI input -> video path -> PCIe DMA -> RK3568`

The project records each RTL, constraint, PDS, simulation, timing, debugger,
and board-validation iteration. Generated PDS output directories, bitstreams,
logs, and temporary waveforms are excluded from Git.

This repository is deliberately named and located separately from the original
team project. It has its own `main` branch and commit history; changes here do
not rewrite or replace the original project.

## Current Baseline

- Version: `codex-baseline-20260813-134325`
- Baseline time: `2026-08-13 13:43:25 +08:00`
- FPGA device: `PG2L100H`, `-6`, `FBG484`
- Video format: `1280x720`, BGR565, 2 bytes/pixel
- PCIe: Gen2 x2
- Control registers: aligned BAR0 map in `src/pcie/pio_crtl.v`
- Current diagnostic video path: restored to the original pure PCIe path
- Current preprocessing source: retained in the PDS source list, not active in
  the diagnostic video path

## Build Entry

Open `hdmi_loop.pds` in Pango Design Suite. PDS compilation, SBIT/SFC
generation, Flash programming, Verify, and physical board reboot remain manual
operations.

## Version Discipline

Every future code change must:

1. Update `CODEX_CHANGELOG.md` with a timestamped entry.
2. Record the reason, observed result, verification, and remaining risk.
3. Commit the complete change as a new version.
4. Push the commit to the separate GitHub repository configured for this
   project.

The local repository is ready for its first push, but no GitHub remote is
configured yet. The remote URL will be added only after the empty, separate
GitHub repository is created and its URL is supplied.
