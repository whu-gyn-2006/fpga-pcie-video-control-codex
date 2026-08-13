# Branch Handoff: Start/CDC Baseline Investigation

Timestamp: 2026-08-13 16:12 +08:00

## Frozen dynamic-debug route

- Branch: `main`
- Frozen commit: `861be95`
- Tag: `debugger-input-boundary-20260813`
- Board fingerprint: BAR0 version `0x20260813`
- Board PCIe state: endpoint `0755:0755`, Gen2 x2, BAR0 read/write healthy.
- RK application is not the primary variable: the same current RK build displayed
  smooth complete frames with the original pure-PCIe/full-HDMI FPGA image.

## Reliable hardware facts

1. The MS7200 input boundary is healthy.
   - receiver reset released
   - initialization complete
   - FSM in `STA_RD`, command index 300
   - pixel activity counter changed through all 256 values
   - pixel-domain sticky observations saw both raw DE and raw VS
2. A legacy BAR0 start command sets `start=1`.
3. With start asserted, BAR0 still reports `frame_done=0`, `wr_index=0`.
4. The second-stage sticky capture reported no delayed DE, video-control DE/VS,
   or frame done. AXIS ready was high; AXIS valid/last sticky bits were high.
5. Because that second capture read sticky flags across clock domains, it does
   not yet prove where DE/VS disappear. An 8-bit FIC is prepared to sample raw,
   d0, d1, and video-control DE/VS directly on `pixclk_in`; it has not been
   built or flashed.

## Superseded observation

The first 14-bit probe sampled raw HDMI DE/VS using `pclk_div2` and saw both
low. That result must not be interpreted as proof that HDMI DE/VS were absent.
The later native-pixel-domain sticky capture proved raw pixel, DE, and VS
activity. The first result was an asynchronous sampling limitation.

## Static comparison already completed

- Current and known-good pure-PCIe/full-HDMI projects have byte-identical:
  - `src/ms7200_ctl.v`
  - active MS7200 register table
  - `src/hdmi_loop.fdc`
  - `PLL_50mHZ` generated IP files
- Both projects explicitly constrain PCIe `pclk=250 MHz`,
  `pclk_div2=125 MHz`, and `ref_clk=100 MHz`.
- Both projects leave `sys_clk`, `pixclk_in`, and PLL outputs without valid
  clock constraints. PDS consequently reports them as 1 MHz. The pure image
  working does not make these constraints correct; it means its implementation
  happened to operate on hardware.
- Current timing had two approximately `-0.001 ns` PCIe-IP hold violations.
  These are implementation differences but are not evidence for the missing
  frame by themselves.

## New branch objective

Branch: `investigate/start-cdc-baseline`

Perform a reproducible A/B audit against:

`D:/a_fpga/codex/5_12_HDMI_IN_DDR3_HDMI_OUT/else/pcie_720p/pcie_test_img_100h`

Before functional edits, compare:

1. PDS source and IP input lists.
2. All RTL file hashes and meaningful diffs.
3. Parameters, generate choices, and synthesis/device-map/place-route options.
4. FDC/FIC and debug-preservation attributes.
5. Legacy start generation and every consumer of `w_start_flag`.
6. Pixel-to-PCIe CDC, especially `r_vs_rst`, `video_dma_req`, `r_line_reg`,
   `frame_done`, and frame counters.
7. Synthesized schematic/netlist connectivity and constant-folded signals.

Do not modify start/CDC behavior until the static audit identifies a concrete
difference or a protocol violation. Do not request another PDS build until a
matching FIC is present for any probe-based experiment.

## Recovery points

- Return to dynamic probing: checkout tag
  `debugger-input-boundary-20260813` or branch `main`.
- Current prepared FIC:
  `synthesize/hdmi_loop_syn_20260813_hdmi_input.fic`
- Capture script:
  `scripts/debugger_capture_hdmi_input.tcl`
- Parser:
  `scripts/parse_debugger_hdmi_input_wf.ps1`
