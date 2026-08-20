# FPGA 视频预处理与 RK3568 PCIe 控制技术说明

## 1. 文档目的

本文说明当前 FPGA 视频预处理功能的实现、数据路径、寄存器控制协议、参数
含义、阈值写入方式、RK3568 侧操作方法以及已完成的验证边界。

本文对应的 FPGA 稳定发布版本：

```text
工程目录：D:\a_fpga\codex\5_12_HDMI_IN_DDR3_HDMI_OUT\else\1\fpga_stage06_release
分支：stable/stage06-20260814
提交：f377509 Release verified Stage 06 video controls
```

当前版本的目标是证明：

```text
RK3568 通过 PCIe BAR0 写入控制参数
        -> FPGA 控制寄存器保存并输出参数
        -> FPGA 视频链路根据模式和参数实时处理像素
        -> 处理后的帧继续通过原 PCIe DMA 路径发送到 RK3568
```

## 2. 已确认的整体视频链路

当前视频主链路保持原有 PCIe/DMA 架构：

```text
HDMI 输入
  -> HDMI 接收与视频时序处理
  -> video_crtl
  -> video_preproc
  -> RGB565 数据整理
  -> pcie_tx_fun / 原 PCIe DMA 发送路径
  -> RK3568 PCIe 驱动
  -> RK3568 Qt/YOLO/PP-OCR 程序
```

预处理模块位于视频时序处理之后、PCIe 发送数据整理之前。它处理视频数据和
视频有效信号，但不负责 PCIe 建链、DMA 映射、帧缓冲分配或 RK3568 推理。

本版本明确保持不变的接口包括：

- PCIe IP 配置。
- PCIe endpoint 的 Vendor/Device 标识。
- Gen2 x2 链路配置。
- BAR0 映射机制。
- 原有 legacy DMA 启动命令和停止命令。
- PCIe DMA 帧大小和 BGR565 传输格式。
- RK3568 驱动读取 DMA 帧的方式。

因此，新增预处理控制面的设计目标不是重做 PCIe，而是在原视频流上增加可配置
的像素处理选择。

## 3. 当前支持的处理模式

当前最终稳定版本支持以下模式：

| `preproc_mode` | 名称 | 功能 | 阈值寄存器作用 |
|---:|---|---|---|
| `0` | bypass | 原始视频直通 | 不参与像素计算 |
| `1` | brightness | 亮度/增益调节 | 作为增益和亮度偏移参数 |
| `2` | contrast | 对比度增强 | 作为对比度系数 |

### 3.1 模式 0：原图旁路

模式 0 是严格旁路：输入像素、输入 VSYNC 和输入 DE 直接作为输出。

这一模式的 RTL 选择关系等价于：

```text
output_data = input_data
output_vs   = input_vs
output_de   = input_de
```

模式 0 不经过模式 1/2 的寄存器计算路径，因此不会额外引入预处理寄存器级的
视频延迟。它是上电后首先应验证的安全模式，也是判断预处理模块是否影响原始
PCIe 链路的基准模式。

### 3.2 模式 1：亮度/增益调节

模式 1 对 R、G、B 三个 8-bit 通道分别计算调节结果，然后进行 0 到 255 的
饱和限制。

当前 RTL 的计算形式为：

```text
delta = threshold - 128

channel_gain = ((input_channel - 128) * threshold) >> 7

output_channel = channel_gain + 128 + (delta >> 1)
```

这里的 `threshold` 名称沿用了既有寄存器命名，但在模式 1 中它不是二值化门限，
而是一个 8-bit 亮度/增益调节参数。

参数特点：

- `128`：中性参考值，输出接近原始亮度和对比关系。
- 大于 `128`：增强整体亮度/增益效果，过大时可能出现高光饱和。
- 小于 `128`：减弱亮度/增益效果，过小时可能使画面偏暗。
- 计算结果小于 `0` 时输出 `0`。
- 计算结果大于 `255` 时输出 `255`。

模式 1 的数据、VSYNC 和 DE 经过一个视频时钟周期对齐后输出。切换模式时，
应以完整帧边界作为观察起点，不应把切换瞬间的半行数据作为结果判断依据。

### 3.3 模式 2：对比度增强

模式 2 以 128 作为像素中心，对每个颜色通道执行带符号缩放：

```text
output_channel = 128 + (((input_channel - 128) * threshold) >> 7)
```

之后同样执行 8-bit 饱和限制：

```text
output_channel < 0   -> 0
output_channel > 255 -> 255
```

参数特点：

- `128`：中性对比度，理论上保持原始通道值。
- 大于 `128`：扩大像素相对中灰点的距离，表现为对比度增强。
- 小于 `128`：压缩像素相对中灰点的距离，表现为对比度减弱。
- `0`：所有通道趋近中间灰度值。
- `255`：接近最大增强系数，但仍会经过饱和限制。

例如，理想整数运算下：

```text
input = 128, threshold = 任意值 -> output = 128
threshold = 128                -> output 约等于 input
input > 128 且 threshold > 128 -> output 更接近白色
input < 128 且 threshold > 128 -> output 更接近黑色
```

模式 2 与模式 1 一样，输出视频数据和时序信号经过一个视频时钟周期对齐。

## 4. 阈值参数的准确含义

### 4.1 寄存器命名说明

寄存器地址 `0x160` 的历史名称是 `threshold`。在当前稳定版本中，它的实际含义
随模式变化：

```text
mode 0：不使用
mode 1：亮度/增益参数
mode 2：对比度系数
```

它不是一个固定意义的“二值化阈值”。当前稳定版本没有把它用于黑白二值判断。

### 4.2 有效位宽和取值范围

RK 端工具接受十进制 `0` 到 `255`：

```text
有效值：0..255
实际计算：threshold[7:0]
寄存器写入：32-bit BAR0 写入，低 8 bit 生效
```

例如：

```text
128 -> 0x00000080
194 -> 0x000000C2
64  -> 0x00000040
```

虽然 BAR0 写事务是 32-bit 工具参数，但 FPGA 像素计算只使用 `0x160[7:0]`。
建议始终将高 24 bit 写为 0，避免后续协议扩展时产生歧义。

### 4.3 阈值写入链路

一次参数写入经过以下路径：

```text
RK3568 用户态命令
  -> fpga_preproc_ctrl.sh
  -> fpga_bar0_ctrl_test
  -> pango_pci_driver
  -> PCIe BAR0 Memory Write
  -> FPGA PIO 接收逻辑
  -> pio_crtl.v 地址译码
  -> threshold shadow register
  -> 视频时钟域使用 threshold[7:0]
  -> video_preproc.v 像素计算
```

由于当前 PIO 用户数据通道按 16-byte 对齐访问，控制寄存器采用 16-byte 间隔。
因此 `0x160` 不能改写成 `0x164`、`0x168` 或 `0x16c` 来节省地址空间；当前
稳定协议只保证下面的对齐地址。

### 4.4 参数是否持久化

这些寄存器是 FPGA 运行时寄存器，不是 Flash 参数：

- 断电后不会保存上一次阈值。
- FPGA 重新配置后恢复 RTL 默认值。
- RK 端写入成功后，在当前 FPGA 工作周期内保持。
- 程序退出不会改变 FPGA bitstream，但 RK UI 可以在关闭流程中主动恢复默认。

因此，每次启动演示前建议读取寄存器并显式写入期望模式和阈值，而不是假设上次
程序退出时的参数仍然存在。

## 5. BAR0 控制寄存器表

当前控制面采用 16-byte 对齐地址：

| 地址 | 名称 | 读写 | 当前用途 |
|---:|---|---|---|
| `0x100` | magic | R | 固定识别值 `0x46504331` |
| `0x110` | version | R | FPGA 控制面/版本标识 |
| `0x120` | scratch | R/W | 读写回环测试 |
| `0x130` | capture_ctrl | R/W | 控制面 shadow 状态；不替代 legacy DMA 启动协议 |
| `0x140` | frame_status | R | 帧状态 |
| `0x150` | preproc_mode | R/W | `0/1/2` 模式选择 |
| `0x160` | threshold | R/W | 8-bit 亮度/对比度参数 |
| `0x190` | debug_trig | W/R | 调试触发参数 |
| `0x1a0` | frame_cfg | R/W | 预留帧配置记录 |
| `0x1b0` | ctrl_status | R | 控制状态、启动状态和配置写计数 |

当前正式预处理功能只依赖：

```text
0x150 preproc_mode
0x160 threshold
```

## 6. RK3568 侧控制方式

### 6.1 控制工具位置

板端程序目录中的控制工具：

```text
./fpga_bar0_ctrl_test
```

控制脚本：

```text
./fpga_preproc_ctrl.sh
```

运行前需要确保 PCIe 驱动已经加载，并且当前 FPGA 固件确实是包含控制面的
版本。

### 6.2 读取控制面

进入板端程序目录后执行：

```bash
./fpga_bar0_ctrl_test --regs
```

重点检查：

```text
magic          BAR0+0x100 = 0x46504331
preproc_mode   BAR0+0x150 = 当前模式
threshold      BAR0+0x160 = 当前参数
```

如果 `magic` 不正确，先不要判断预处理效果，应先确认 FPGA 固件、PDS 工程和
烧录版本。

### 6.3 直接写模式

旁路原图：

```bash
./fpga_bar0_ctrl_test --write 0x150 --value 0 --read 0x150
```

亮度/增益模式：

```bash
./fpga_bar0_ctrl_test --write 0x150 --value 1 --read 0x150
```

对比度模式：

```bash
./fpga_bar0_ctrl_test --write 0x150 --value 2 --read 0x150
```

每条命令都执行了：

```text
BAR0 写入
-> FPGA 寄存器读回
-> 工具打印 readback
```

读回值正确只能证明控制面写入成功；要证明图像链路响应，还需要在视频输入
稳定时观察输出帧变化。

### 6.4 直接写阈值

设置中性参数 128：

```bash
./fpga_bar0_ctrl_test --write 0x160 --value 128 --read 0x160
```

设置增强参数 194：

```bash
./fpga_bar0_ctrl_test --write 0x160 --value 194 --read 0x160
```

设置较弱参数 64：

```bash
./fpga_bar0_ctrl_test --write 0x160 --value 64 --read 0x160
```

注意模式和阈值是两个独立寄存器。推荐先写阈值，再写模式，最后读取寄存器：

```bash
./fpga_bar0_ctrl_test --write 0x160 --value 194 --read 0x160
./fpga_bar0_ctrl_test --write 0x150 --value 2 --read 0x150
./fpga_bar0_ctrl_test --regs
```

最终 `--regs` 应至少显示：

```text
preproc_mode = 0x00000002
threshold    = 0x000000C2
```

### 6.5 使用控制脚本

读取状态：

```bash
./fpga_preproc_ctrl.sh status
```

设置旁路：

```bash
./fpga_preproc_ctrl.sh mode bypass
```

设置亮度/增益模式：

```bash
./fpga_preproc_ctrl.sh mode brightness
```

设置对比度模式：

```bash
./fpga_preproc_ctrl.sh mode contrast
```

单独设置参数：

```bash
./fpga_preproc_ctrl.sh threshold 194
```

一次设置模式和参数：

```bash
./fpga_preproc_ctrl.sh apply contrast 194
```

脚本的 `apply` 操作实际拆成两次寄存器写入：

```text
写 0x150 = 2
读回 0x150
写 0x160 = 194
读回 0x160
```

脚本只接受 `0..255` 的十进制参数，超出范围会直接报错，不会向 FPGA 写入。
每个寄存器最多尝试三次，写入后立即读回。

## 7. Qt UI 控制关系

RK Qt 界面提供 FPGA 模式选择和参数应用入口。UI 的核心控制逻辑是：

```text
用户选择模式和参数
  -> Qt 组装 shell 参数
  -> /bin/sh fpga_preproc_ctrl.sh apply <mode> <threshold>
  -> 脚本调用 fpga_bar0_ctrl_test
  -> 写入并读回 0x150/0x160
  -> Qt 根据退出码和读回结果显示成功或失败
```

UI 的模式名称与寄存器值对应关系：

```text
旁路       -> 0
亮度调节   -> 1
对比度增强 -> 2
```

参数应用失败时，应先看终端中的以下信息：

```text
FPGA control command:
FPGA control output:
FPGA control error:
FPGA control exit:
```

常见原因包括：

- 控制工具不存在。
- 控制工具没有执行权限。
- 驱动没有加载，`/dev/pango_pci_driver` 不存在。
- 当前 FPGA 固件不是包含 BAR0 控制面的版本。
- BAR0 写入成功但读回值不一致。
- 运行中的程序目录被覆盖，导致脚本、工具和程序版本不匹配。

## 8. 推荐验证顺序

### 8.1 固件和 PCIe 基础确认

```bash
./fpga_bar0_ctrl_test --regs
```

确认 `magic` 正确后再进行模式测试。

### 8.2 旁路基线

```bash
./fpga_preproc_ctrl.sh apply bypass 128
./fpga_bar0_ctrl_test --regs
```

此时应确认 RK 程序可以显示原始 PCIe 图像，作为后续图像比较基线。

### 8.3 亮度/增益测试

```bash
./fpga_preproc_ctrl.sh apply brightness 64
./fpga_bar0_ctrl_test --regs

./fpga_preproc_ctrl.sh apply brightness 194
./fpga_bar0_ctrl_test --regs
```

观察参数读回和输出画面是否随参数发生稳定变化。

### 8.4 对比度测试

```bash
./fpga_preproc_ctrl.sh apply contrast 128
./fpga_preproc_ctrl.sh apply contrast 194
./fpga_preproc_ctrl.sh apply contrast 64
./fpga_bar0_ctrl_test --regs
```

对比度测试应以 `128` 作为中性参考，再分别测试高于和低于 128 的参数。

### 8.5 重启后状态

关闭 RK 程序并重新启动后，不能假设上一次运行的参数仍然存在。重新读取：

```bash
./fpga_bar0_ctrl_test --regs
```

如果 FPGA 发生过物理重启，寄存器应以 RTL 默认值为准；如果只是关闭并重启 RK
程序，寄存器是否恢复取决于 RK 程序退出路径和当前固件行为。因此演示启动时应
显式执行一次：

```bash
./fpga_preproc_ctrl.sh apply bypass 128
```

## 9. 验证边界与不能夸大的结论

当前已确认的内容：

- RK3568 可以通过 PCIe BAR0 访问 FPGA 控制寄存器。
- 16-byte 对齐地址的模式和参数写入/读回路径已验证。
- 模式 0、模式 1、模式 2 已写入 FPGA 视频路径。
- Stage06 发布版本保持原 PCIe/DMA/FIFO/start 行为。
- 参数可在不重新烧录 FPGA 的情况下由 RK 运行时修改。

本文不宣称以下内容：

- 不宣称所有亮度或对比度参数都适合实际识别精度。
- 不宣称预处理一定提升 YOLO、车牌识别或 OCR 准确率。
- 不宣称模式切换可以在任意像素时刻无缝完成。
- 不宣称旧固件、旧 RK 工具和新控制寄存器天然兼容。
- 不把寄存器读回成功等同于图像质量或算法效果已经通过完整评测。

## 10. 版本、构建和固化说明

预处理 RTL 主要文件：

```text
src/pcie/video_preproc.v
src/pcie/pio_crtl.v
hdmi_loop.pds
```

PDS 源文件加入方式必须以当前 `.pds` 文件和 PDS GUI 的工程源列表为准。修改
RTL 后，应执行：

```text
ModelSim 语法/仿真
-> PDS Compile
-> Synthesize
-> Device Map
-> Place & Route
-> Timing Report
-> Generate SBIT
-> Generate SFC
-> Flash Verify
-> 物理重启
```

生成 SFC 时确认：

```text
Flash：XT25BF128FSSIGU-W
工具器件：xt25f128
JEDEC ID：0x1C7118
CFG BANK VOLTAGE：3.3V
```

只有固化、Verify 和物理重启完成后，才能把板端寄存器读回结果归属于这一次
FPGA 版本。

## 11. 相关文档和源代码索引

FPGA：

```text
TECHNICAL_DOC_VIDEO_PREPROCESSING.md
VERSION.md
readme.md
CODEX_CHANGELOG.md
src/pcie/video_preproc.v
src/pcie/pio_crtl.v
```

RK：

```text
Yolo_LPR_RK3568_FPGA/5_QT_UI_Demo/fpga_preproc_ctrl.sh
Yolo_LPR_RK3568_FPGA/5_QT_UI_Demo/src/main_pcie_qt.cc
Yolo_LPR_RK3568_FPGA/5_QT_UI_Demo/README_1280X800_HANDOFF.md
```

本文只描述当前已确认的三种模式和两项控制参数，作为项目技术文档中的 FPGA
预处理与 RK 控制接口章节。
