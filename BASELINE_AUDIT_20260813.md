# Pure PCIe/HDMI Baseline A/B Audit

Timestamp: 2026-08-13 16:24 +08:00

Compared projects:

- Control/debug project:
  `else/1/pcie_test_img_100h`
- Known-good pure-PCIe/full-HDMI project:
  `else/pcie_720p/pcie_test_img_100h`

The reference called "pure PCIe" is not PCIe-only. It contains the complete
HDMI input, video-control, packing, DMA, and PCIe path and has produced smooth
1280x720 frames with the current RK application.

## Byte-identical inputs

- All generated files under `ipcore/`: zero hash differences.
- `src/hdmi_loop.fdc`: identical SHA-256.
- `src/ms7200_ctl.v`, including the complete MS7200 initialization table.
- `src/ms72xx_ctl.v`, `src/ms7210_ctl.v`, and `src/iic_dri.v` relative to the
  selected pure-PCIe reference.
- `src/pcie/video_crtl.v`.
- Every PCIe DMA controller/wrapper source except the separately listed top
  helper files below.
- `PLL_50mHZ` generated IP.

## Actual source differences

Only four source-list differences were found:

1. `src/hdmi_loop.v`
   - BAR0 configuration output wires and `pio_crtl` port connections added.
   - Debug attributes and passive diagnostic sticky registers added.
   - Declarations moved, without changing functional connections.
   - HDMI d0/d1 sampling, `video_crtl`, `r_vs_rst`, frame counters, DMA request,
     and AXIS wiring are otherwise unchanged.
2. `src/pcie/pio_crtl.v`
   - Adds aligned BAR0 registers and readback/status muxing.
   - The legacy start/stop process is line-for-line functionally unchanged:
     same `pcie_clk`, reset, BAR0 address zero, start value `0xffffffe5`, and
     stop value `0xffffff00`.
   - `capture_ctrl` is a separate shadow register and does not drive or gate
     `r_start_flag`.
3. `src/pcie/pcie_tx_fun.v`
   - Whitespace-only difference. No functional RTL difference.
4. `src/pcie/video_preproc.v`
   - Present only in the control project source list.
   - It is not instantiated in the active diagnostic top, so it should be
     removed from a minimal A/B source list to eliminate ambiguity, although
     synthesis should otherwise discard it.

## PDS and IP result

- PDS HDL input order is the same except for `video_preproc.v`.
- Active FDC is the same.
- Generated IP tree has zero differences.
- Compile, synthesize, device-map, and place-route databases differ, as expected
  from changed top/PIO logic and different Debugger insertion.
- No evidence was found that a different PCIe IP configuration or HDMI IP is
  selected.

## Clock constraints

Both projects explicitly constrain:

- PCIe `pclk`: 250 MHz
- PCIe `pclk_div2`: 125 MHz
- PCIe `ref_clk`: 100 MHz

Both projects fail to correctly constrain `sys_clk`, `pixclk_in`, and generated
PLL outputs. PDS reports these as 1 MHz and emits `SDC-2025`. This is a shared
defect, not a control-project-only difference. It makes timing closure claims
for the HDMI pixel domain unreliable and can make two place/route results behave
differently at the real pixel frequency.

## Debugger difference

- Reference FIC: historical wide probe, depth 4096, sampled by
  `nt_pixclk_in`, including counters and video data.
- Current prepared FIC: focused 8-bit probe, depth 1024, sampled by
  `pixclk_in`, covering raw/d0/d1/video-control DE and VS.
- Debug attributes and inserted cores change optimization, fanout, placement,
  and routing. This is currently a stronger implementation-level difference
  than the legacy start logic.

## Start/CDC conclusion

The hypothesis "BAR0 shadow changed the legacy start state machine" is not
supported by the RTL comparison. Board readback also proved the legacy command
sets `start=1`.

The design does contain unsafe shared CDC behavior, including pixel-domain
`r_vs_rst` and other control/status signals consumed in `pclk_div2` without a
formal synchronizer. However, that logic is common to both projects. It can
explain implementation sensitivity after layout changes, but it cannot by
itself identify the unique source difference.

## Controlled next experiment

Do not change CDC and BAR0 behavior simultaneously. The next A/B build should
change one variable only:

1. Start from the known-good reference source/top and implementation settings.
2. Replace only `pio_crtl.v` with the aligned-register version and connect only
   its additional outputs as unused wires.
3. Do not include `video_preproc.v`.
4. Remove all newly added sticky diagnostic registers and extra
   `PAP_MARK_DEBUG` attributes.
5. Use the reference FIC unchanged if its stored ADF path is regenerated for
   the new project, or omit Debugger from both A/B builds. Do not compare a
   wide-reference-FIC build against a different debug-core build.
6. Keep legacy start/stop semantics exactly unchanged.

Interpretation:

- If this minimal BAR0 build works, the register bank is safe and the failure
  came from later top/debug/preprocessing changes or implementation movement.
- If it fails, compare one additional build with the original `pio_crtl.v` but
  identical FIC/options. That isolates PIO expansion/resource-placement effects.
- Only after that result should the shared CDC be repaired in a separate commit
  and tested against both configurations.

No new PDS build is requested by this audit document itself.

## Candidate prepared, 2026-08-13 16:23 +08:00

The controlled BAR0-only candidate has now been applied to the active PDS
project:

- top restored from the known-good pure-PCIe/full-HDMI source
- only six expanded-`pio_crtl` output wires and port connections added
- declaration ordering cleaned for strict Verilog compilation; no connection or
  behavior changed
- `video_preproc.v` references in active PDS: 0
- active FIC references in PDS: 0
- matching 8-bit pixel-domain FIC retained on disk but deliberately inactive
- inactive lightweight companion FIC now uses only pure-top preserved signals:
  start, DMA done, frame done, write index, and synchronized line request
- The user requested GUI visibility before build, so the lightweight FIC was
  subsequently registered in `wgt_my_fic_src`. The upcoming hardware image is
  explicitly the `BAR0 baseline + 8-bit probe` candidate.
- ModelSim compile: Errors 0, Warnings 0

This candidate requires one PDS/SBIT/SFC/flash/physical-restart test. Its first
test must use bypass defaults and legacy start only; do not apply preprocessing
register values before confirming complete frames.
# Pure PCIe A/B baseline branch

Branch: `baseline/pure-pcie-no-bar0-20260813`

Purpose: isolate whether the BAR0 control-plane extension is responsible for
the missing first frame. This branch restores the known-good pure PCIe HDMI
chain and removes the BAR0 register extension, preprocessing path, and active
Debugger FIC from the PDS GUI project.

Static checks:

- `src/hdmi_loop.v` matches the pure reference project.
- `src/pcie/pio_crtl.v` matches the pure reference project.
- PDS GUI Verilog inputs: 41; all exist and pass module dependency checking.
- PDS GUI FIC inputs: 0.
- `video_preproc.v` is not instantiated or listed.

This is an A/B isolation image, not the feature image. Do not write BAR0
configuration registers during its first test. First test only the original RK
legacy DMA start path and compare complete-frame display against the known-good
pure PCIe image.

## Hardware result after 2026-08-13 flash/reboot

- Endpoint enumerated normally as `0755:0755`, Gen2 x2.
- RK UI entered `Capturing PCIe Frames` after the display button was clicked.
- The DMA loop repeatedly reported `ready=0`, with no complete frame and no
  display output.
- Therefore this test does not support the hypothesis that the BAR0 register
  extension alone is the cause. It also means this branch must be compared
  against the exact previously successful pure image at the generated SBIT/SFC
  and RK deployment levels before changing RTL again.
