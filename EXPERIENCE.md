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

The current timing comparison also showed that extra `sys_clk` and
`pixclk_in` constraints changed the implementation result and introduced a
`pixclk_in` reset-path violation. Constraint changes therefore belong in the
same timestamped version record as RTL changes.

