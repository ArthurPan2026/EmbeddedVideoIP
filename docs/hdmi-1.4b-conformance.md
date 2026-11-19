# EmbeddedVideoIP 1.4b 模式实现与测试映射

当前实现范围以用户提供的 HDMI Specification 1.4b 为准，视频时序遵循 CEA-861-D VIC 定义。以下表格记录设计对应的规范条款和 RTL 验证项。

## 视频和色彩

| 功能 | 标准依据 | RTL 实现 | RTL 验证 |
|---|---|---|---|
| 640×480p、720p60、1080p30 | HDMI 1.4b §6.3.1、§6.3.2；CEA-861-D VIC 1、4、34 | VIC 1 使用 VGA clock；VIC 4 和 VIC 34 共用 HD clock；时序发生器按 profile 选择 porch、sync 和 active 区 | timing generator bench 逐点检查三种 profile 的 H/V totals、active、blank、sync 极性、profile change 与 frame wrap |
| RGB 4:4:4 8 bpc | HDMI 1.4b §6.2.3、§6.5 Table 6-1 | 默认 RGB888 TMDS 编码，AVI InfoFrame 声明 RGB 和 VIC | RGB encoder bench 覆盖全部 8-bit 输入码 |
| YCbCr 4:4:4 8 bpc | HDMI 1.4b §6.2.3、§6.5 Table 6-1 | 静态 profile 可选择 BT.601/BT.709 与 Full/Limited range；AVI 色彩字段跟随参数 | 矩阵、range、AVI 字段和 checksum benches |
| Deep Color | HDMI 1.4b §6.5 Table 6-1 | 当前 TX pixel interface 为 RGB888，输出为 8 bpc | 不作为本次实现项；10 bpc 需要 30-bit pixel-group packing 和 1.25 倍 TMDS clock |

HD profile 的时钟合成器输出 74.218750 MHz，CTA 标称值为 74.25 MHz，误差约 421 ppm。仿真使用实际频率计算音频 ACR。HDMI 接收端容差需在开发板上测量。

## HDMI packet 与音频

| 功能 | 标准依据 | RTL 实现 | RTL 验证 |
|---|---|---|---|
| AVI InfoFrame | HDMI 1.4b §8.2.1；CEA-861-D | VIC、aspect、pixel encoding、colorimetry 和 quantization range 来自 active profile | VIC 1/4/34、色彩模式、checksum、封包次序 |
| Data Island 和 BCH | HDMI 1.4b §5.2、§5.3 | 系统级 HDMI/DVI mux、包前导、保护带、控制周期和 BCH | packet assembler、TMDS mode mux、line-slot scheduler |
| 24-bit LPCM | HDMI 1.4b §7.3.3 Table 7-5 | 48-bit AXI4-Stream，每帧为双声道 24-bit PCM；默认 48 kHz | 正负满幅、零样本、背压、FIFO 满空、采样包字段 |
| ACR | HDMI 1.4b §7.2.3、§7.8.2 | N=6144/12288/24576 对应 48/96/192 kHz；CTS 基于实际 PCLK 和 H_TOTAL | 三个视频 profile × 三个采样率的 ACR cadence |
| EDID 能力 | HDMI 1.4b §8.1、§8.3.2 Table 8-16；E-EDID / E-DDC | PS 消费端解析 CEA VIC、HDMI VSDB 最大 TMDS 和 LPCM SAD | C host parser 测 checksum、截断块、重复/保留 VIC、TMDS 边界与 SAD |
| DVI-safe fallback | HDMI 1.4b §4.2、§5.2 | PS 发送模式请求；PL 在切换期间保持 DVI-safe，等时钟锁定和新 VSYNC | mode controller bench 覆盖请求、锁定等待、config-ready、VSYNC 与超时 |

TX 使用 8-bit pixel profile。HDMI 1.4b 高码率音频 HBR、3D、4K、HDCP、CEC、ARC/eARC 不包含在本次功能范围。

## 消费端验证范围

GBA 消费端按 sink 能力优先选择 VIC 4，再选 VIC 34，其他情况使用 VIC 1。默认 GBA PS 配置生成原生 1280×720 LVGL/XRGB8888 VDMA 输入。PL scaler 负责匹配 sink 选择的输出模式。

Vivado Simulator 2025.2.1 的完整 RTL 回归、IP Catalog 验证、GBA PS 应用构建和开发板输出模式验收分别记录在相应 validation 文件中。RTL/XSim 结果验证逻辑和边界，不替代开发板电气、时钟容差或 HDMI CTS 测试。
