# Codex 改版记录

本文件用于记录后续由 Codex 协助完成的代码改版、验证状态和遗留问题。

## 记录规则

- “已验证跑通”必须写明验证时间、验证环境和关键命令/结果。
- 本地只完成静态检查、未上板运行、缺少交叉编译工具链的改动，统一标记为“待验证”。
- 涉及 PDS 编译、bitstream、SFC、Flash 烧录的步骤默认由用户手动执行；Codex 只记录步骤和结果。

## 2026-08-01 17:00 - RK 侧 BAR0 控制/状态通道验证工具

验证状态：RK 侧小工具虚拟机交叉编译已通过；板端已验证基础 RK -> FPGA BAR0 控制/状态闭环。

修改内容：

- 新增 RK3568 用户态测试工具：
  `D:\a_fpga\codex\5_12_HDMI_IN_DDR3_HDMI_OUT\else\1\Yolo_LPR_RK3568_FPGA\4_NPU_Yolov8_Traffic_Demo\tools\fpga_bar0_ctrl_test.c`
- 修改 Traffic Demo 构建脚本：
  `D:\a_fpga\codex\5_12_HDMI_IN_DDR3_HDMI_OUT\else\1\Yolo_LPR_RK3568_FPGA\4_NPU_Yolov8_Traffic_Demo\CMakeLists.txt`
- 新工具复用现有 `pango_pci_driver` / `pango_pci.h` 流程，通过 `PCI_MAP_BAR0_CMD` 获取 BAR0 物理地址，再 mmap `/dev/mem` 访问 FPGA BAR0。
- 默认只读取现有 `BAR0 + 0x140` 帧状态寄存器；可选写 `BAR0 + 0x000` 的 legacy stop/start 命令。
- `--start` 会先调用现有 DMA 配置和地址映射 ioctl，避免在 DMA 基地址未准备好时启动 FPGA MWr；默认轮询后写 stop 并释放 DMA 映射。

保持不变：

- 未修改 FPGA RTL。
- 未修改 PCIe IP、PDS 工程、FDC 约束或 bitstream。
- 不需要重新跑 PDS 编译。

预期板端验证命令：

```bash
./fpga_bar0_ctrl_test --status
./fpga_bar0_ctrl_test --stop --status
./fpga_bar0_ctrl_test --start --poll 30 --delay-ms 100
```

验证状态：

- 本地已完成代码结构检查；待板子连接后进行 ADB/板端编译运行验证。

下一步判断：

- 如果 `0x140` 可读且 `frame_done/wr_index` 有合理变化，说明现有 RK 读 FPGA 状态通道已打通。
- 如果 `0x140` 一直为 0 或读失败，再进入 FPGA 侧 Debugger，观察 `pio_rd_en`、`pio_rd_addr`、`pio_rd_data` 以及 MRD/CPLD 应答路径。

## 2026-08-01 17:25 - FPGA BAR0 控制寄存器 v1

验证状态：RTL 单文件语法检查通过；待用户手动 PDS 编译/下载后板端验证。

修改内容：

- 修改 `src\pcie\pio_crtl.v`，新增 BAR0 `0x100` 段 RK 可见控制寄存器：
  `magic/version/scratch/capture_ctrl/preproc_mode/threshold/ROI/debug_trigger/frame_cfg/ctrl_status`。
- 保留原有 legacy start/stop、DMA 地址寄存器和 `0x140` 帧状态寄存器。
- 本版只建立 RK -> FPGA 配置读写闭环，暂不接入真实预处理数据路径。
- 同步扩展 RK 工具 `fpga_bar0_ctrl_test.c`，新增 `--regs`、`--scratch`、`--control`、`--read`、`--write --value`。
- 2026-08-01 17:40 修正 `REG_CTRL_STATUS` 拼接位宽为 32 位，避免读回值被截断。

已完成检查：

- ModelSim 单文件编译 `pio_crtl.v`：
  `Errors: 0, Warnings: 0`

待验证命令：

```bash
./fpga_bar0_ctrl_test --regs
./fpga_bar0_ctrl_test --scratch 0x12345678 --regs
./fpga_bar0_ctrl_test --control 1 --regs
./fpga_bar0_ctrl_test --control 0 --regs
```

## 2026-08-06 21:18 - 仿真/Debugger 工具链确认与 BAR0 寄存器现状

验证状态：

- ModelSim 目录已确认可用，后续仿真优先走项目根目录脚本。
- Debugger 工具链已确认可用，后续优先复用项目内现成 tcl/parser。
- 本次仅更新文档和接手规则，未改 RTL。

补充规则：

- ModelSim 优先从 `scripts\` 调 `run_modelsim_all.ps1`，单测可直接跑 `sim\xxx.do`。
- 新增 testbench 不能只放 `sim\`，还要写入 `HDMI_IN_DDR3_HDMI_OUT.pds` 的 `wgt_simulation/_input`。
- Debugger 统一用 `cdt_dbg.exe`，波形通常落在当前工程目录的 `data.wf`，解析时要对应本地 split project 的 `.fic`。

当前代码链路判断：

- `build-fpga-bar0-tool.sh` 的编译目标和 CMake 目标一致，推入的 `fpga_bar0_ctrl_test` 不是错版本工具链产物。
- 板上现象仍是 `magic` 可读，但 `version/scratch/capture_ctrl/ctrl_status` 读回 0，`--write 0x108` 回读也为 0。
- 目前更像 FPGA 侧 `pio_wr_en/pio_wr_addr/pio_wr_data` 写通路未真正落到新寄存器块，下一步应优先用 Debugger 抓这些信号。

## 2026-08-06 21:18 - BAR0 readback and version mismatch note

Verification:
- pio_crtl.v already contains the new register block and REG_VERSION = 32'h20260801.
- hdmi_loop.v wires ips2l_pcie_dma o_pio_* into u_pio_crtl.
- Today's hdmi_loop.pds, hdmi_loop.sbit, and hdmi_loop.sfc are all new.
- Board readback still shows magic=0x46504331, but version/scratch/capture_ctrl/ctrl_status read back as 0.

Current guess:
- The board image / active FIC may still be stale.
- Another possibility is that the write path does not really reach the new register block.

Next step:
- Capture pio_wr_en, pio_wr_addr, pio_wr_data, pio_rd_en, pio_rd_addr, pio_rd_data with Debugger.

## 2026-08-06 22:55 - pcie_test_img_100h PIO Debugger FIC repaired

Verification:
- `synthesize/hdmi_loop_syn.adf` exists and is nonzero.
- `synthesize/hdmi_loop_syn.fic` was recreated as a hand-authored 91-channel FIC, size 7559 bytes.
- `hdmi_loop.pds` already references `synthesize/hdmi_loop_syn.fic` under `wgt_my_fic_src`; its timespec was refreshed.
- FIC channel count equals `triggerPortWidth<0>=91`.
- The new FIC does not contain the stale `D:/work/demo/...` path.

Changes:
- Replaced the zero-byte `synthesize/hdmi_loop_syn.fic` with a valid hand-authored PIO/BAR0 Debugger FIC.
- Updated `hdmi_loop.pds` FIC timespec to `2026-08-06T22:55:00`.
- Disabled `scripts/debug_inserter_pio_ctrl_fic.tcl` with an explicit error because the old `cdt_ins` route can leave a zero-byte FIC.
- Set the active FIC file read-only after a Fabric Inserter auto-save overwrote it with a 256-bit empty probe.
- Added `scripts/parse_debugger_pio_ctrl_wf.ps1` for the 91-bit PIO/BAR0 waveform.

Next user-side step:
- Close and reopen PDS GUI, rebuild from Device Map/Inserter or full bitstream, then download/program the bitstream containing this Debug Core before running Debugger capture.
- After capture, parse the waveform with:
  `powershell -ExecutionPolicy Bypass -File D:\a_fpga\codex\5_12_HDMI_IN_DDR3_HDMI_OUT\scripts\parse_debugger_pio_ctrl_wf.ps1 -Path D:\a_fpga\codex\5_12_HDMI_IN_DDR3_HDMI_OUT\else\1\pcie_test_img_100h\data.wf`

## 2026-08-06 23:40 - FIC 调试耗时反思与后续规则

Problem:
- 本次写一个 FIC 耗时过长，主要原因是前期没有先建立“有效文件判据”和“工具副作用边界”，而是过早顺着 `cdt_ins` 失败路径试。
- `cdt_ins` 的 `-file` 如果传 Windows 反斜杠路径，会被 Tcl 转义破坏，例如 `\a`、`\5` 一类字符会导致脚本路径失真。
- Tcl 中 `pio_wr_addr[9:0]` 这类写法如果没有正确保护，会被当作命令替换；即使加 `{}`，本项目里 `ins_set_net -connect` 对信号名/总线连接仍不够可靠。
- Fabric Inserter GUI/进程可能在关闭或自动保存时把 FIC 覆盖成空探针，例如本次出现过 256-bit、无 `triggerChannel` 的坏 FIC。
- 只看“文件存在”不够；0 字节 FIC、无通道 FIC、旧路径 FIC 都必须视为失败。

Rules for future work:
- 先读文档和现有成功样例，再改脚本；优先复制本项目已验证的 `.fic` 明文格式，而不是临场猜 CLI 参数。
- 每次生成/修改 FIC 后立刻做四项检查：文件非 0、`designInputFile` 是当前工程 ADF、`triggerChannel` 数量等于 `triggerPortWidth`、没有 `D:/work/demo` 等旧路径。
- 在确认 FIC 有效之前，不进入 PDS rebuild、Debugger capture、板端结论分析。
- FIC/Debugger 脚本涉及 Windows 路径时统一用正斜杠 `/`，不要把反斜杠路径直接喂给 Tcl。
- 如果 PDS/Fabric Inserter GUI 打开过 FIC，结束后重新检查 FIC 是否被覆盖；必要时对已确认有效的手写 FIC 设置只读保护。
- 修改 FIC 后必须提醒：Debug Core 需要重新插入并生成新的 bitstream，板上旧 bitstream 不会自动拥有新探针。
- 不要为了“赶紧试一下”运行已知有风险的旧脚本；旧脚本应禁用或加显式错误，避免把正确文件覆盖坏。

Better next-time workflow:
1. 明确目标信号和采样时钟。
2. 从 RTL/综合网表确认信号名存在。
3. 手写或生成 FIC。
4. 本地静态校验 FIC。
5. 更新 `.pds` timespec 和记录。
6. 用户侧重开 PDS，重跑插桩/bitstream。
7. 抓 `data.wf` 后先用 parser 解码，再判断 RTL 问题。

## 2026-08-06 23:56 - FIC 耗时复盘固化

这次问题不是 FIC 本身复杂，而是流程顺序错了：一开始把重点放在“让工具生成
FIC”，没有先定义“什么才算一个有效 FIC”。结果在坏脚本、Tcl 转义、GUI 自动保存、
旧路径和空探针之间来回排查，浪费了接近半小时。

以后写 FIC/Debugger 相关代码前，必须先做这些事：

- 先找本工程或同系列工程里已经跑通过的 `.fic` 明文样例，确认字段格式、`designInputFile`、`triggerPortWidth`、`triggerChannel` 写法。
- 先列出目标信号、位宽、采样时钟和预期总宽度；不要边写边猜。
- 先写静态校验规则，再生成/修改 FIC。至少检查：文件非 0、ADF 路径属于当前工程、通道数等于总宽度、无旧工程路径、无空 probe。
- Tcl/Debugger/PDS 脚本中的 Windows 路径统一转换为 `/`；包含 `[9:0]` 的总线名不能裸写给 Tcl 解释器。
- 第一次 `cdt_ins` 或 GUI 插入异常后不要继续盲试同一路径；应立刻检查输出文件和日志，若出现 0 字节/空通道/旧路径，切换到已验证的手写 FIC 格式。
- 修改已验证 FIC 前先备份；如果 GUI 有覆盖风险，确认有效后可以临时设置只读。
- FIC 文件写好不等于板上已有探针；必须重新插入 Debug Core、重新生成 bitstream，并下载/固化后，`data.wf` 才有意义。
- parser 应该和 FIC 同步准备。抓波形后先让 parser 验证 sample size/bit width，再做 RTL 结论。

以后 Debugger/FIC 的最小闭环：

1. Define signals and sample clock.
2. Confirm names from RTL/netlist.
3. Create or edit FIC.
4. Run static FIC checks.
5. Update PDS reference/timespec.
6. Reopen PDS and rebuild bitstream.
7. Capture `data.wf`.
8. Parse waveform before changing RTL.

时间约束：如果 10 分钟内还没有得到一个通过静态校验的 FIC，应停止当前工具路线，
回到文档和已验证样例，不再靠连续尝试推进。

## 2026-08-07 00:41 - BAR0 PIO lane 问题定位与 16-byte 寄存器地址修正

验证状态：

- 用户已重新编译、固化、物理重启，ADB 已连接。
- RK3568 PCIe 枚举正常：
  - endpoint `0755:0755`
  - `PCIe Gen.2 x2 link up`
  - `/dev/pcie_dma_memcpy` 存在
- `pango_pci_driver.ko` 手动 `insmod` 后 `/dev/pango_pci_driver` 正常出现。
- 板端原现象复现：`magic@0x100 = 0x46504331`，但 `version@0x104`、`scratch@0x108`、`capture_ctrl@0x10c` 均读 0。

Debugger 结论：

- 91-bit FIC 已确认在板上有效，`data.wf` 为 11776 bytes，即 `1024 * 92bit / 8` 的 bit-packed 格式。
- 已修正 `scripts/parse_debugger_pio_ctrl_wf.ps1`，支持 bit-packed 和 byte-aligned 两种 `data.wf`。
- 用板端临时编译的 `fpga_bar0_ctrl_test_burst --burst-write` 配合立即触发抓到：
  - `pio_wr_en` 有效。
  - `pio_wr_addr` 能正确到达 `u_pio_crtl`。
  - 写 `BAR0+0x100` 时，`pio_wr_data` 能看到真实递增数据。
  - 写 `BAR0+0x104/0x108/0x10c` 时，`pio_wr_addr` 正确但 `pio_wr_data=0`。

根因判断：

- 当前 PCIe BAR0 PIO 写/读路径底层是 128-bit / 16-byte 粒度。
- `ips2l_pcie_dma_rx_top` 输出 `o_bar0_wr_data[127:0]`，但 `ips2l_pcie_dma` 顶层给 PIO 的端口是 `o_pio_wr_data[31:0]`，实际只使用低 32-bit lane。
- 因此只有 16-byte 对齐的 BAR0 地址能通过低 32-bit lane 稳定读写。
- 这解释了为什么 `magic@0x100` 可读，而按 4-byte 排布的 `0x104/0x108/0x10c` 读写都像失效。

修改内容：

- 修改 `src/pcie/pio_crtl.v`：
  - 保留 `REG_MAGIC = 0x100`。
  - 保留 legacy `WR_FRAME_DONE = 0x140`。
  - 将 RK 可见控制寄存器改成 16-byte 对齐：
    - `REG_VERSION = 0x110`
    - `REG_SCRATCH = 0x120`
    - `REG_CAPTURE_CTRL = 0x130`
    - `REG_PREPROC_MODE = 0x150`
    - `REG_THRESHOLD = 0x160`
    - `REG_ROI_XY = 0x170`
    - `REG_ROI_WH = 0x180`
    - `REG_DEBUG_TRIG = 0x190`
    - `REG_FRAME_CFG = 0x1a0`
    - `REG_CTRL_STATUS = 0x1b0`
- 修改 RK 测试工具：
  `Yolo_LPR_RK3568_FPGA\4_NPU_Yolov8_Traffic_Demo\tools\fpga_bar0_ctrl_test.c`
  - 同步新寄存器地址。
  - 新增 `--burst-write N` 调试选项，用于一次 mmap 后连续写 BAR0，方便 Debugger 抓窄脉冲。
- 新增 Debugger 辅助脚本：
  - `scripts/debugger_capture_pio_wr_en.tcl`
  - `scripts/debugger_capture_pio_wraddr0_static.tcl`
  - `scripts/debugger_capture_pio_allx_run.tcl`
  - `scripts/debugger_stop.tcl`

本地验证：

- `pio_crtl.v` ModelSim 单文件语法检查通过：
  `Errors: 0, Warnings: 0`
- 板端 gcc 临时编译新版测试工具通过：
  `/tmp/fpga_bar0_build/fpga_bar0_ctrl_test_burst`

下一步用户侧动作：

1. 重新用 PDS 编译 `pcie_test_img_100h` 并生成 bitstream/SFC。
2. 固化后物理重启开发板/RK3568。
3. 重新编译并推入新版 `fpga_bar0_ctrl_test`。
4. 板端运行：

```bash
cd /userdata/rknn_yolov8_ppocr_qt_ui_demo/yolov8_ppocr_pcie_qt_ui
insmod ./pango_pci_driver.ko 2>/dev/null || true
chmod +x ./fpga_bar0_ctrl_test
./fpga_bar0_ctrl_test --regs
./fpga_bar0_ctrl_test --scratch 0x12345678 --regs
./fpga_bar0_ctrl_test --control 1 --regs
./fpga_bar0_ctrl_test --control 0 --regs
```

预期结果：

- `version BAR0+0x110 = 0x20260801`
- `scratch BAR0+0x120` 写后能读回 `0x12345678`
- `capture_ctrl BAR0+0x130` 写 1/0 后能反映到 `ctrl_status start`
- `frame_status BAR0+0x140` 继续保留旧状态读法

## 2026-08-07 00:58 - BAR0 16-byte 对齐寄存器板上验证通过

验证状态：已上板验证通过。

验证环境：

- 用户重新 PDS 编译、固化并物理重启后，ADB 已连接。
- RK3568 侧 PCIe endpoint 正常枚举：`0755:0755`。
- `/dev/pcie_dma_memcpy` 和 `/dev/pango_pci_driver` 均存在。
- 板端临时 gcc 编译新版 `fpga_bar0_ctrl_test` 成功。

验证结果：

- `./fpga_bar0_ctrl_test --regs`：
  - `magic BAR0+0x100 = 0x46504331`
  - `version BAR0+0x110 = 0x20260801`
- `./fpga_bar0_ctrl_test --scratch 0x12345678 --regs`：
  - `scratch BAR0+0x120 = 0x12345678`
  - `ctrl_status cfg_writes=1`
- `./fpga_bar0_ctrl_test --control 1 --regs`：
  - `capture_ctrl BAR0+0x130 = 0x00000001`
  - `ctrl_status start=1`
- `./fpga_bar0_ctrl_test --write 0x150 --value 0x00000002 --read 0x150`：
  - `preproc_mode BAR0+0x150 = 0x00000002`
- `./fpga_bar0_ctrl_test --control 0 --regs`：
  - `capture_ctrl BAR0+0x130 = 0x00000000`
  - `ctrl_status start=0`
  - `ctrl_status cfg_writes=4`

板端工具状态：

- 已将新版测试工具复制到：
  `/userdata/rknn_yolov8_ppocr_qt_ui_demo/yolov8_ppocr_pcie_qt_ui/fpga_bar0_ctrl_test`
- 旧版已备份为：
  `/userdata/rknn_yolov8_ppocr_qt_ui_demo/yolov8_ppocr_pcie_qt_ui/fpga_bar0_ctrl_test.old_20260807`

结论：

- RK -> FPGA BAR0 控制/状态读写闭环已经打通。
- 当前可作为后续“预处理模式选择、阈值、ROI、采集开关、调试触发”的控制面基础。
- 下一步可以开始把 `preproc_mode/threshold/roi/debug_trig` 从仅寄存器保存，接入实际预处理或采集控制逻辑。
## 2026-08-07 01:28 - v1_4 BAR0-controlled preprocessing enters video path

Verification status:

- Local ModelSim syntax check passed:
  `vlog src\pcie\video_preproc.v src\pcie\pio_crtl.v src\hdmi_loop.v`
  reported `Errors: 0, Warnings: 0`.
- Pending user-side PDS rebuild, SFC/Flash update, physical restart, and board
  video verification.

Changes:

- Added `src/pcie/video_preproc.v`.
  - mode 0: bypass
  - mode 1: grayscale
  - mode 2: threshold using `threshold[7:0]`
  - mode 3: ROI mask using `roi_xy={y,x}` and `roi_wh={h,w}`
- Updated `src/hdmi_loop.v`.
  - Connected `pio_crtl` exported registers to top-level wires.
  - Synchronized slow BAR0 config registers from `pclk_div2` to `pixclk_in`
    with two-stage sampling.
  - Inserted `video_preproc` after `video_crtl`.
  - Changed RGB565 packing and `pcie_tx_fun` `vs/de` inputs to use the
    preprocessed stream.
  - Moved `pclk_div2/core_rst_n/dma_tx_done` declarations to avoid ModelSim
    duplicate implicit-wire errors during syntax checking; functional drivers
    are unchanged.
- Updated `hdmi_loop.pds`.
  - Added `src/pcie/video_preproc.v` to `wgt_my_design_src`.
  - Refreshed timespecs for `src/hdmi_loop.v` and `src/pcie/pio_crtl.v`.
- Updated `readme.md` with mode meanings and board-side commands.

Next verification:

1. User closes/reopens PDS GUI and rebuilds `pcie_test_img_100h`.
2. User generates SFC / flashes / verifies, then physically restarts the board.
3. On RK3568, first test bypass mode to confirm the original path did not
   regress, then switch to grayscale / threshold / ROI.

## 2026-08-10 13:00 - Current stable-control-interface checkpoint

Current phase is interface construction and stability verification. Image
display or preprocessing visual effects have not been validated yet and must
not be reported as completed.

Confirmed on the current board image through ADB:

- `0x100` magic reads `0x46504331`.
- `0x110` version reads `0x20260801`.
- `0x150` preproc mode, `0x160` threshold, `0x170` ROI XY, and `0x180` ROI WH
  accept aligned BAR0 writes and return the written values.
- `0x130` capture control changes the FPGA `start` status between 0 and 1.
- `0x190` debug trigger and `0x1a0` frame configuration are present as
  readable/writable control registers; `frame_cfg` remains state-only.
- `ctrl_status.cfg_writes` increments after recognized control-register writes.

The stable control map remains 16-byte aligned:

`0x100 magic`, `0x110 version`, `0x120 scratch`, `0x130 capture_ctrl`,
`0x140 frame_status`, `0x150 preproc_mode`, `0x160 threshold`, `0x170 roi_xy`,
`0x180 roi_wh`, `0x190 debug_trig`, `0x1a0 frame_cfg`, `0x1b0 ctrl_status`.

Next step is to preserve this interface and continue interface-level checks.
Do not move to image capture or visual mode comparison until this checkpoint
is explicitly closed.

## 2026-08-10 23:56 - FIC path/date cross-check

The user supplied the canonical `cdt_ins` recipe using lowercase `ins_*`
commands, forward-slash absolute paths, the current project ADF, and
`ins_save`. Two non-destructive temporary tests were attempted against a
temporary output path, first with `-file` and then with
`-netlist <current ADF> -file`; both `cdt_ins` processes remained running
without producing `ins_save` output and were stopped. The active FIC was not
overwritten.

Current target-project FIC:

`D:/a_fpga/codex/5_12_HDMI_IN_DDR3_HDMI_OUT/else/1/pcie_test_img_100h/synthesize/hdmi_loop_syn.fic`

It is nonzero (`7559` bytes), references the local `else/1` ADF, and its file
header is dated 2026-08-06. The April 2026 FIC with `D:/work/demo` belongs to
the old `else/pcie_720p` reference project and must not be used by the active
PDS project.

## 2026-08-11 00:45:43 +08:00 - Correct FPGA image restored

The user confirmed that the previously programmed image was the wrong version,
then completed PDS build, SFC generation, Flash programming, and physical
restart with the corrected image.

Board-side verification after loading `pango_pci_driver.ko`:

- PCIe endpoint enumerated as vendor/device `0x0755/0x0755`, Gen2 x2.
- BAR0 `magic=0x46504331` and `version=0x20260801` were restored.
- Scratch readback passed with `0x12345678`.
- `preproc_mode`, `threshold`, `roi_xy`, and `roi_wh` accepted writes and
  returned the same values.
- Final safe state was restored: `preproc_mode=0`, `capture_ctrl=0`.
- No Qt process or DMA test was started during this verification.

This closes the wrong-image explanation for the earlier all-zero BAR0 result.

## 2026-08-11 01:08:05 +08:00 - Qt no-frame checkpoint and strict bypass fix

The user ran the newly deployed 1280x800 Qt application with a stable HDMI
source and clicked the display/capture start control. The observed terminal
state was:

- PCIe endpoint remained `0x0755/0x0755`, Gen2 x2.
- BAR0 control registers remained readable and writable.
- The Qt log reported `PCIe: no FPGA frame arrived within 1000 ms; stopping DMA.`
- After the timeout, `capture_ctrl=0`, `ctrl_status.start=0`,
  `frame_status=0`, and `frame_done=0`.
- `pidof` still showed the Qt process, so this result is a capture-session
  failure rather than proof that the PCIe endpoint disappeared.

The RK-side timeout cleanup explains the final `capture_ctrl=0`: the application
clears the FPGA capture bit after no frame-status progress. The control writes
for mode, threshold, and ROI were already confirmed by the incrementing
`ctrl_status.cfg_writes` value.

Minimal RTL correction applied in `src/pcie/video_preproc.v`:

- `preproc_mode=0` now directly selects the original `video_crtl` data, VS,
  and DE signals.
- Modes 1/2/3 retain the registered preprocessing path.
- This removes the extra preprocessing-stage cycle from the bypass path and
  restores the original video timing before further mode testing.

Local ModelSim check of the edited module passed with `Errors: 0, Warnings: 0`.
The new RTL is not on the board until the user rebuilds the FPGA project,
generates SBIT/SFC, programs Flash, and physically restarts the board.

Next hardware checkpoint: test only bypass mode after the new FPGA image is
running. If `frame_status` still does not advance, use the HDMI-path Debugger
instrumentation to distinguish missing `pixclk/de/vs` activity from a
downstream packet problem. The previously drafted HDMI activity FIC was
invalid and was not programmed; do not run its capture script against the
current image. First generate and insert a valid matching FIC, then rebuild
the bitstream. Do not switch preprocessing modes until bypass produces a
frame.
## 2026-08-11 18:58:33 +08:00 - Post-reboot driver and BAR0 verification

After the user programmed the corrected FPGA image and physically restarted
the board, ADB returned normally but the PCIe driver was not loaded
automatically:

- `/dev/pango_pci_driver` was initially absent.
- `lsmod` did not list `pango_pci_driver`.
- The FPGA endpoint was still present on the RK PCI bus.

Loading the deployed module from the application directory succeeded with
`INSMOD_RC=0`. The driver then created `/dev/pango_pci_driver` and reported
vendor/device `0x0755/0x0755`, Gen2 x2, BAR0 `0xf0200000`, MPS 128, and MRRS
512 in the kernel log.

BAR0 verification after loading the driver passed:

- magic `0x46504331`
- version `0x20260801`
- `preproc_mode=0`
- `capture_ctrl=0`
- `frame_status=0` before a capture session

The Qt process was then started once and remained alive as PID `3329`; it had
not entered the capture worker yet, so `capture_ctrl=0` was expected. The next
manual action is one click on the UI display-start control, followed by a
single BAR0/status read. Do not start another Qt process or use raw
`--control 1` before that result is collected.
## 2026-08-11 19:02:33 +08:00 - Bypass retest still has no frame

After the user programmed the strict mode-0 bypass image, the deployed Qt
application was started once and the user clicked the display-start control.
The application stopped its capture worker with:

`PCIe: no FPGA frame arrived within 1000 ms; stopping DMA.`

The process was then closed deliberately with SIGTERM so the user could start
it from an interactive terminal. The `Received signal 15` line is from that
deliberate shutdown, not an application crash.

Post-test BAR0 verification remained healthy:

- PCIe Gen2 x2 and BAR0 mapping succeeded.
- magic `0x46504331` and version `0x20260801` remained correct.
- `capture_ctrl=0`, `frame_status=0`, `frame_done=0`, and `wr_index=0`.

Conclusion: the strict mode-0 bypass did not yet produce a frame. The Qt
timeout/cleanup path and the PCIe control plane are no longer the leading
suspects. The next diagnostic must observe HDMI-side `pixclk`, `vs`, `hs`,
`de`, and RGB activity with a valid matching Fabric Debugger insertion. Do not
repeat UI/DMA attempts until that observation is available.
## 2026-08-11 19:12:55 +08:00 - Static root cause found in frame completion

Static comparison of the current project against the old `else/pcie_720p`
reference confirmed that `video_crtl.v` and `pcie_tx_fun.v` were previously
identical. The current top-level mode-0 path is cycle-aligned with the old
`video_crtl` output, so the preprocessing mux was not the remaining reason
for `frame_status=0`.

A real completion-status bug was found in `src/pcie/pcie_tx_fun.v`:

- `i_start_tx_flag` is a held-high capture enable.
- The PCIe-clock frame counter had an `else if(i_start_tx_flag)` branch that
  reset `r_frame_cnt` every PCIe clock while capture was enabled.
- The frame-done logic also cleared `r_frame_done` whenever the same held-high
  flag was asserted.
- Consequently `o_check_data[0]`, which feeds PIO register `0x140`, could never
  report a completed frame.

Minimal fix applied:

- Keep reset behavior for `i_start_tx_flag == 0`.
- Remove the unconditional start-high counter reset.
- Make `r_frame_done` reset on reset or start-low, then assert only after the
  final DMA transaction.

The PDS source timestamp for `pcie_tx_fun.v` was refreshed. Standalone
ModelSim compilation passed with `Errors: 0`; it reported four pre-existing
warnings for undeclared FIFO status nets (`almost_full`, `rd_empty`,
`w_rd_water_level`, and `almost_empty`).

The board has not been rebuilt or reprogrammed with this fix yet. The next
required hardware action is a manual PDS rebuild, SBIT/SFC generation, Flash
program/verify, physical restart, and then one bypass-mode Qt test.

## 2026-08-11 20:39:31 +08:00 - Stable RK statistics but visible frame jitter

The user completed a 10-second Qt PCIe display run in bypass mode. RK-side
statistics were stable:

- Captured: 1569 frames, 26.14 FPS.
- Display pipeline: 1559 frames, 25.97 FPS.
- Qt painted: 1557 frames, 25.84 FPS.
- Display queue drops: 0.
- Display failures: 0.
- Overlay failures: 0.
- Fatal PCIe driver errors: 0.

The driver reported many `EPERM` retries while polling for the next frame
(`7478` total), but these are the existing nonblocking "frame not ready"
retries; successful frames continued at approximately 26 FPS and no fatal
error occurred. This does not indicate a broken PCIe link or a Qt queue
backlog.

Static inspection of the active FPGA video path found a throughput risk:
`ipcore/video_buffer/video_buffer.v` uses a 16-bit write side with
`WR_DEPTH_WIDTH=12`, equivalent to only 8192 bytes of buffering, while
`pcie_tx_fun.v` reads 128 bits per DMA read and the input video stream writes
every active pixel. The FIFO `wr_full` output is currently left unconnected in
`pcie_tx_fun.v`. If HDMI pixel input runs faster than the measured PCIe frame
delivery rate, the FIFO can overflow and lose pixels, producing frame jitter,
horizontal displacement, or tearing before RK/Qt receives the data.

The current `pcie_tx_fun.v` data path still matches the old `else/pcie_720p`
reference; its local change only fixes frame completion reporting. The
preprocessing mode is currently `0` and the direct board control test passes.
Therefore the next low-risk A/B test is to reduce the HDMI source refresh rate
to 30 Hz or lower, keep FPGA mode 0, and repeat the same Qt run. If jitter
substantially decreases, the FIFO/throughput hypothesis is confirmed. A real
fix then requires frame-sized buffering or a frame-aware DDR3 path, not more
Qt repaint tuning.

## 2026-08-11 20:49:14 +08:00 - Preprocessing semantics and ROI preview update

The preprocessing controls were aligned with useful demonstration behavior:

- mode 0 remains the original bypass path.
- mode 1 is brightness adjustment; register `0x160[7:0]` uses 128 as neutral.
- mode 2 is contrast enhancement; register `0x160[7:0]` uses 128 as neutral.
- mode 3 now keeps the selected ROI at full brightness and dims the rest of
  the frame instead of making the context completely black.

The FPGA stage remains a streaming pixel operation. Full-frame ROI scaling is
not implemented in RTL because it would require line/frame buffering. The RK
preview performs the corresponding ROI crop and fast scale to the preview
viewport, so `roi_xy={Y,X}` and `roi_wh={H,W}` now produce a visible zoom
without changing the PCIe frame format or the full-frame geometry seen by RK
inference. Mode 3 still applies its dimmed-background preprocessing to the
inference pixels outside the ROI.

The FPGA RTL needs a new PDS build before this mode-3 dimming change reaches
the board. The Qt control script and UI need a cross-build and deployment.

## 2026-08-11 22:14:59 +08:00 - HDMI activity Debugger FIC selected

The board continued to enumerate PCIe correctly after both the current image
and the older known-working SBIT were tried, but neither produced a completed
frame. Static inspection found that the PDS project still referenced the old
PIO-only FIC `synthesize/hdmi_loop_syn.fic`; the prepared 57-bit HDMI activity
FIC was not part of the generated Debug Core.

The PDS FIC source was changed to
`synthesize/hdmi_loop_syn_hdmi_activity.fic`. This probe observes
`w_start_flag`, `frame_done`, `pixclk_in`, `vs_in`, `hs_in`, `de_in`,
`w_video_crtl_de`, `w_preproc_de`, RGB data, and `dma_tx_done` on `pixclk_in`.
The change is diagnostic only; PCIe/DMA RTL and the Qt application were not
changed. PDS must be closed/reopened and rebuilt before the matching Debugger
capture is meaningful.

## 2026-08-11 22:42:24 +08:00 - Preprocessing timing and functional simulation check

The stable A/B test used the current RK application with the original
no-preprocessing PCIe FPGA image. The image was stable without jitter or offset,
so the remaining suspicion is the modified FPGA video path rather than Qt,
driver, or PCIe enumeration.

The existing post-route timing report says `All Constraints Met`, but its clock
table assigns `pixclk_in`, `sys_clk`, and the HDMI PLL output a default 1000 ns
period (1 MHz). The active FDC has no real `create_clock` for `pixclk_in`, so
this report does not yet prove HDMI-path timing. A real pixel-clock period must
be confirmed from the HDMI input mode before updating the FDC.

A temporary ModelSim testbench was run at
`tmp/tb_video_preproc.v`. It passed cycle-alignment checks for bypass,
brightness, contrast, and ROI modes, including ROI coordinate reset at a new
frame. This is a module-level functional result only; it does not replace a
top-level video-to-DMA simulation or a timing report with a real `pixclk_in`
constraint.

## 2026-08-11 22:49:29 +08:00 - 720p60 pixel-clock constraints added

For the selected 1280x720@60 HDMI input, `src/hdmi_loop.fdc` now declares
`pixclk_in` as 74.25 MHz (`13.468 ns` period) and `sys_clk` as 50 MHz
(`20.000 ns` period). This is a constraints-only change; no RTL, bitstream,
or RK package was changed. The PDS project must be closed/reopened and timing
analysis rerun before using the new slack values.

## 2026-08-11 22:54:02 +08:00 - Final HDMI timing/debug probe prepared

The active HDMI Debugger FIC was expanded from 57 to 81 channels before the
next PDS build. It retains the raw/preprocessed RGB and DE channels and adds
raw/preprocessed VS, the VS edge/extension state, RGB565 output, and the
pixel-domain latched preprocessing mode. The related signals in
`src/hdmi_loop.v` are marked for Debug retention. The PDS project already
selects `synthesize/hdmi_loop_syn_hdmi_activity.fic`, so one rebuild can serve
both timing analysis and the later Debugger capture.

## 2026-08-11 - Inserter-0026 recovery

PDS rejected the hand-authored `synthesize/hdmi_loop_syn_hdmi_activity.fic`
with `Inserter-0026` / `Inserter-0003`. The file contained channel metadata but
not the complete Fabric Inserter `triggerBus` / `busInserter` structure required
by PDS. The active project was restored to the known-good
`synthesize/hdmi_loop_syn.fic`, which is kept as the compile-safe FIC.

The HDMI activity probe must be regenerated from the current synthesized ADF
through `cdt_ins` using the `ins_*` commands; it must not be created by manual
editing. The rejected activity FIC remains unreferenced as a draft. Close and
reopen PDS before continuing the build so the restored FIC is reloaded.

The project now includes
`scripts/debugger_make_hdmi_activity_fic.tcl`, which generates the activity
FIC with the Inserter command flow after synthesis. It is intentionally not
run as part of the current recovery, so the PDS compile path remains on the
known-good PIO FIC.

## 2026-08-12 - PIO capture confirmed; HDMI activity FIC still pending

After the latest Flash rebuild and physical restart, the board-side control
plane was healthy after manually loading `pango_pci_driver.ko`:

- PCIe endpoint `0x0755:0x0755`, Gen2 x2, BAR0 mapped.
- `magic=0x46504331`, `version=0x20260801`.
- `capture_ctrl=0`, `preproc_mode=0`, and all control registers were at the
  expected post-reset values.

The validated 91-bit PIO Debug Core was captured successfully. The new
`data.wf` was 11776 bytes and decoded as 1024 packed samples, confirming that
the Debugger cable, board Debug Core, and PIO FIC match. No BAR0 writes were
made during that capture, so the absence of write events is expected.

The synthesized ADF was parsed by `cdt_ins`. Its net-list is emitted into
`log/ins.log`, and net indices are regenerated on each parse; indices cannot be
reused across Inserter processes. A temporary numeric-index HDMI probe was
therefore rejected and not used.

The current HDMI activity FIC is now nonzero (7901 bytes), points to the
current ADF, and contains `triggerBus`/`busInserter` entries. However, the
Inserter validation still returns `Inserter-0018`, so this FIC is not yet
approved for PDS Device Map or board programming. The board remains on the
previous PIO Debug Core image. Do not run the HDMI capture script until the
FIC is accepted by PDS and a new Debug-Core bitstream is programmed.

Additional diagnosis on 2026-08-12:

- The latest timing report is not fully clean. `pixclk_in` to `pixclk_in`
  has positive slack of about `7.427 ns`, but a generated-clock to `pixclk_in`
  path has `-2.771 ns` setup slack. The report summary is
  `Some Constraints Violated`; this must be fixed or explicitly reviewed
  before claiming timing closure.
- The PIO FIC capture was repeated with the correct root-level script and
  produced `data.wf=11776` bytes. The parser decoded 1024 samples using the
  91-bit FIC plus one raw trigger bit. No BAR0 write events occurred during
  the capture because no control command was issued at that time.
- `cdt_ins -netlist <current ADF> -fic <PIO FIC> -mode 1` returns
  `Inserter-0002` because the validated PIO FIC is intentionally protected;
  it must not be used as a rewrite target. The HDMI draft returns
  `Inserter-0018` after parsing and writing, even when reduced to one added
  HDMI scalar channel, so it is not approved for insertion.

Current safe state: `hdmi_loop.pds` continues to reference
`synthesize/hdmi_loop_syn.fic`. The next HDMI Debugger insertion must be done
in the PDS Fabric Inserter GUI against the current ADF, selecting the HDMI
signals there and saving a newly generated FIC. Do not flash the current
activity draft or run its capture script on the board.

## 2026-08-12 - Pixel-domain reset timing cleanup

The active PDS image remains on the validated PIO FIC; no HDMI activity FIC was
enabled or programmed. Board-side checks after reboot confirmed ADB, the Pango
driver, PCIe Gen2 x2, BAR0 magic/version, and the aligned control register map.

Timing review found the only failing setup group is a `sys_clk`/`cfg_clk` reset
path into the `pixclk_in` group, with approximately `-2.771 ns` slack. The
`r_vs_en` and `r_vs_ext_cnt/r_vs_rst` pixel-domain state previously used
`rstn_out`, which is generated in the configuration-clock domain. They now use
the existing HDMI PLL lock reset `pll_rst_n`, matching the other pixel-domain
video state and removing that asynchronous clock-domain dependency. No PCIe,
PIO, preprocessing algorithm, or HDMI port was changed.

The user must manually rebuild and regenerate timing after this RTL change.
The next acceptance check is `Design Summary : All Constraints Met` (or a
remaining violation with a different, explicitly identified path), followed by
the existing mode-0 video test. No HDMI FIC is required for this step.

## 2026-08-12 - capture_ctrl pixel-domain CDC cleanup

The software-controlled capture gate changes startup behavior compared with the
former power-on self-start flow. `w_start_flag` is generated in the PCIe
`pclk_div2` domain but was connected directly to the HDMI `pixclk_in` domain.
The top-level now synchronizes it through two pixel-clock registers before it
enters `video_crtl`. PCIe DMA-domain logic still uses the original signal.
No PCIe IP, DMA packet format, BAR0 map, or preprocessing algorithm changed.
ModelSim syntax check passed with zero errors and zero warnings.

## 2026-08-12 - mode-0 top-level hard bypass

The capture_ctrl pixel-domain synchronizer was rebuilt and tested on hardware,
but the Qt application still timed out without a first frame. To make the
original-path A/B test unambiguous, the top-level now selects the original
`video_crtl` data, VS, and DE directly whenever `preproc_mode=0`. Modes 1-3
continue to use `video_preproc`. The selected signals feed the VS startup
logic, RGB565 conversion, and `pcie_tx_fun`, so mode 0 no longer relies on the
preprocessing module's bypass outputs. ModelSim syntax check passed with zero
errors and zero warnings. No PCIe IP, DMA protocol, BAR0 map, or RK sources
were changed.

Post-build verification on 2026-08-12: the refreshed timing report now reports
`Design Summary : All Constraints Met`. The board still enumerates correctly,
but the Qt run timed out before receiving a frame; the final cleanup snapshot
was `capture_ctrl=0`, `frame_status=0`, and `frame_done=0`. This is now a
video-data-path issue rather than the previously observed timing violation.

## 2026-08-13 - pure PCIe A/B result and diagnostic baseline

The original pure PCIe FPGA project was flashed and tested with the current RK
application. It produced complete, smooth 1280x720 frames. The RK log showed
`read returned driver status 2; accepting the DMA buffer as one complete frame`
followed by increasing `ready` counts, which is a successful frame path rather
than a PCIe failure.

This isolates the no-frame regression to the modified FPGA integration, not the
RK application, PCIe endpoint/link, driver, or HDMI source.

The current project was then reduced to a diagnostic baseline: `pio_crtl.v`
and its aligned BAR0 control-register outputs remain connected, while
`hdmi_loop.v` restores the original video path, original start signal,
original VS reset path, original RGB565 conversion, and original VS/DE inputs
to `pcie_tx_fun`. The two changed frame-counter reset conditions in
`pcie_tx_fun.v` were also restored to the pure PCIe behavior. The
`video_preproc.v` source remains in the PDS source list but is not instantiated
in this diagnostic baseline.

ModelSim syntax check for `video_crtl.v`, `video_preproc.v`, `pio_crtl.v`,
`pcie_tx_fun.v`, and `hdmi_loop.v`: Errors 0, Warnings 0.

This diagnostic baseline has not been built or flashed. The next user action
is to rebuild, generate SBIT/SFC, flash, verify, and physically reboot. If it
produces frames, the BAR0 register interface can be retained and the video
preprocessing path can be reintroduced one controlled change at a time.

## 2026-08-13 - diagnostic baseline aligned with pure PCIe constraints

The board-side diagnostic baseline still produced no frame while BAR0 reported
`capture_ctrl=1`, `start=1`, `cfg_writes=0`. This confirms the UI start command
was accepted and no preprocessing parameter was involved.

Comparison with the working pure PCIe project found that the active diagnostic
FDC had added `sys_clk=50 MHz` and `pixclk_in=74.25 MHz` clocks. Its timing
report then showed a `pixclk_in` reset-path violation of about `-2.679 ns`,
while the pure PCIe project reports all constraints met. Those two added clock
constraints were removed for this diagnostic baseline, and `pcie_tx_fun.v` was
restored byte-for-byte to the pure PCIe version. ModelSim syntax remains
Errors 0, Warnings 0.

The next rebuild/flash test is intended to separate implementation-constraint
effects from the remaining BAR0 register integration. No RK recompilation is
needed.

For the same baseline test, the PDS `wgt_my_fic_src` entry was removed so the
next bitstream has no stale PIO Debugger core. A matching Debugger FIC will be
created only after the working video baseline is restored.
首帧/视频数据路径问题 rather than the previously observed timing violation.
# 2026-08-13 HDMI input-boundary diagnostic

- First hardware capture passed the input boundary: MS7200 initialized, pixel clock active, and DE/VS seen. Replaced the probe with a focused 7-bit second-stage probe for delayed DE, `video_crtl` DE/VS, frame completion, and AXIS valid/ready/last. All pulse observations are sticky registers captured in their native clock domains.
- Device Map initially stopped because flattened combinational nets `rstn_out` and `init_over` could not be resolved by Inserter. Replaced those two FIC channels with preserved `cfg_clk` registers `dbg_rst_released` and `dbg_init_over`; diagnostic meaning is unchanged.
- Static comparison confirmed `ms7200_ctl.v`, the active MS7200 initialization table, and `src/hdmi_loop.fdc` are byte-identical to the known-good pure PCIe project.
- The previous 14-bit first-frame capture proved DMA start asserted while raw `de_in` and `vs_in` remained low for all 1024 samples.
- Added passive pixel-domain summaries `dbg_pixclk_count`, `dbg_de_seen`, and `dbg_vs_seen`; they do not feed back into the video path.
- Added compact 31-bit `cfg_clk` Debugger FIC `synthesize/hdmi_loop_syn_20260813_hdmi_input.fic` covering only RX reset/init FSM/frequency status and pixel/DE/VS activity.
- Added matching capture and parser scripts under `scripts/`. The PDS project now references this FIC before the next build.
