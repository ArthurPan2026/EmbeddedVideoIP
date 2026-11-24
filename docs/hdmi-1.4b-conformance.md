# EmbeddedVideoIP HDMI 1.4b 模式实现与测试映射

本文对应 HDMI 1.4b 视频、音频和数据岛实现，按标准章节关联 RTL 模块与测试。视频时序使用 VIC 定义，板级测量按目标器件和配置归档。

## 视频和色彩

| 功能 | 标准依据 | RTL 实现 | RTL 验证 |
|---|---|---|---|
| 480p60、720p60、1080p30、1080p60 | VIC 1、4、34、16 | 四模式时钟和 VIC 时序发生器 | totals、active、blank、sync 极性、profile change、frame wrap |
| RGB 4:4:4 8 bpc | HDMI 1.4b §6.2.3、§6.5 | RGB888 TMDS 编码，AVI 声明 RGB 和 VIC | RGB encoder 与 AVI checksum |
| YCbCr 4:4:4 8 bpc | HDMI 1.4b §6.2.3、§6.5 | BT.601/BT.709、Full/Limited 静态 profile | 矩阵、range、AVI 字段和 checksum |

## HDMI packet 与音频

| 功能 | 标准依据 | RTL 实现 | RTL 验证 |
|---|---|---|---|
| AVI InfoFrame | HDMI 1.4b §8.2.1 | VIC、aspect、pixel encoding、colorimetry 和 quantization range 来自 active profile | VIC、色彩模式、checksum、封包次序 |
| Data Island 和 BCH | HDMI 1.4b §5.2、§5.3 | packet assembler、BCH、line-slot scheduler 和 TMDS mux | packet、控制周期和保护带 |
| 24-bit LPCM | HDMI 1.4b §7.3.3 | 48-bit AXI4-Stream，双声道 24-bit PCM | 满幅、零样本、背压、FIFO、采样包字段 |
| ACR | HDMI 1.4b §7.2.3、§7.8.2 | `N=6144/12288/24576`，CTS 由像素时钟 profile 选择 | 4 个视频模式 × 3 个采样率 |
| EDID / E-DDC | HDMI 1.4b §8.1、§8.3.2 | 外部控制软件解析 CEA VIC、VSDB 和 LPCM SAD | 库级接口和外部 parser 可独立验证 |
| DVI-safe fallback | HDMI 1.4b §4.2、§5.2 | 模式切换期间等待 lock 和新 VSYNC | mode controller、boot timing、超时和恢复 |

## 验证记录

RTL/XSim 覆盖视频、packet、FIFO、采样节奏、复位和模式事务。实板结果记录器件、profile、工具、测量方法和输入产物哈希。当前 dev.6 的实现与 GBA 采集结果见[2026-11-24 验证记录](validation-2026-11-24.md)。
