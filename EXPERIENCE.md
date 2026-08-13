# Engineering Notes

## 2026-08-13: A/B isolation

The original pure PCIe FPGA image produced smooth complete frames with the
current RK application. The RK log's `driver status 2` was accepted as a full
DMA buffer and the `ready` counter increased. Therefore PCIe enumeration,
driver startup, DMA allocation, HDMI source, and Qt display were not the cause
of the no-frame result in the modified image.

The modified image reported `capture_ctrl=1`, `start=1`, and `cfg_writes=0`.
This proves the UI start command reached the FPGA and that no preprocessing
parameter write was involved in that test.

The reliable debugging lesson is to keep the first comparison narrow: preserve
the original video/DMA path, then add one control-plane or preprocessing change
at a time. A Debugger FIC must match the programmed bitstream; applying a FIC
from a different netlist can produce misleading observations and must be
avoided.

## 2026-08-13 14:12: first-frame probe narrowed

The board still reports `0x20260801`, so the previously prepared non-gating
source has not yet been flashed. PCIe remains Gen2 x2 and BAR0 remains healthy;
the missing frame is still an FPGA frame-generation failure.

The Debugger scope is now deliberately limited to 14 bits and four boundaries:
raw HDMI DE/VS, delayed HDMI DE/VS, `video_crtl` DE/VS, then frame completion
and PCIe AXIS valid/ready/last. It excludes PIO buses, pixel data, and unrelated
PCIe internals. This is sufficient to classify the first-frame failure without
adding a large debug core that could change timing.

The current timing comparison also showed that extra `sys_clk` and
`pixclk_in` constraints changed the implementation result and introduced a
`pixclk_in` reset-path violation. Constraint changes therefore belong in the
same timestamped version record as RTL changes.

## 2026-08-13: invalid Debugger evidence is a process failure

The first lightweight BAR0 baseline FIC observed top-level
`r_line_req_d0/d1/d2`. Their source, `r_line_reg`, was declared but never
assigned. The real DMA implementation was inside `u_pcie_tx_fun`, with a
different `r_line_req` and PCIe-domain synchronization chain. Treating the
top-level constant zeros as evidence about the active path was incorrect.

The first parser compounded the error: it converted `$BitOffset / 8` to
`[int]`, which rounds under Windows PowerShell. Packed samples crossing byte
boundaries were decoded at the wrong byte and made stable level signals appear
to toggle 256 times. Integer shifts and masks are required for packed-bit
indices.

This class of mistake must not consume another hardware iteration. Before a
FIC is delivered, every channel must have a documented driver, active path,
exact synthesized-netlist match, correct clock domain, and parser test vector.
Any impossible decoded behavior is a parser or probe-integrity alarm, not a
hardware finding. A failed check invalidates the conclusion and blocks rebuild
instructions until corrected.

## 2026-08-13: pure no-BAR0 A/B result

The independently built and flashed no-BAR0 branch enumerated PCIe normally,
but the RK capture loop still remained at `ready=0` with no frame. This rules
out treating the BAR0 extension as the sole proven root cause. Before another
RTL change, compare this build with the exact previously successful pure image:
PDS source/FDC, generated synthesis/implementation artifacts, SBIT/SFC, HDMI
mode, and RK binary/driver must all be identified. A branch source match alone
does not prove the programmed bitstream matches the historical successful
image.

## 2026-08-13: child VM names are not flattened Inserter names

Device Map failed with `Inserter-0005` for
`u_pcie_tx_fun/r_video_start_tx_flag_d1`. The leaf register existed in the
synthesized child module, but the hierarchical FIC path did not exist after
netlist flattening. Searching a `.vm` for a leaf name was therefore an
insufficient validation and must not be reported as an Inserter-ready result.

The robust pattern is explicit observability: export required internal states
through debug-only module outputs, connect them to top-level
`PAP_MARK_DEBUG` wires, and probe those stable top-level names. After adding
those wires, rerun synthesis and validate the new ADF before Device Map. An
ADF produced before the debug outputs were added cannot validate them.
