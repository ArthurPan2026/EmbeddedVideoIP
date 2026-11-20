# EmbeddedVideoIP HDMI 1.4b 模式实现与测试映射

当前实现是 HDMI 1.4b 的产品子集。视频时序遵循 CEA-861-D VIC 定义。RTL 结果只证明仿真覆盖的逻辑和边界，不替代目标设备的电气测试或 HDMI 认证。

## 视频和色彩

| 功能 | 标准依据 | RTL 实现 | RTL 验证 |
|---|---|---|---|
| 640×480p、720p60、1080p30 | CEA-861-D VIC 1、4、34 | VGA/HD 时钟 profile 和 VIC 时序发生器 | totals、active、blank、sync 极性、profile change、frame wrap |
| RGB 4:4:4 8 bpc | HDMI 1.4b §6.2.3、§6.5 | RGB888 TMDS 编码，AVI 声明 RGB 和 VIC | RGB encoder 与 AVI checksum |
| YCbCr 4:4:4 8 bpc | HDMI 1.4b §6.2.3、§6.5 | BT.601/BT.709、Full/Limited 静态 profile | 矩阵、range、AVI 字段和 checksum |
| Deep Color | HDMI 1.4b §6.5 | 当前像素接口为 RGB888，输出 8 bpc | 10/12/16 bpc 未纳入；需要新的像素打包和时钟 profile |

## HDMI packet 与音频

| 功能 | 标准依据 | RTL 实现 | RTL 验证 |
|---|---|---|---|
| AVI InfoFrame | HDMI 1.4b §8.2.1 | VIC、aspect、pixel encoding、colorimetry 和 quantization range 来自 active profile | VIC、色彩模式、checksum、封包次序 |
| Data Island 和 BCH | HDMI 1.4b §5.2、§5.3 | packet assembler、BCH、line-slot scheduler 和 TMDS mux | packet、控制周期和保护带 |
| 24-bit LPCM | HDMI 1.4b §7.3.3 | 48-bit AXI4-Stream，双声道 24-bit PCM | 满幅、零样本、背压、FIFO、采样包字段 |
| ACR | HDMI 1.4b §7.2.3、§7.8.2 | `N=6144/12288/24576`，CTS 使用实际 PCLK 和 `H_TOTAL` | 3 个视频 profile × 3 个采样率 |
| EDID / E-DDC | HDMI 1.4b §8.1、§8.3.2 | 外部控制软件解析 CEA VIC、VSDB 和 LPCM SAD | 库级接口和外部 parser 可独立验证 |
| DVI-safe fallback | HDMI 1.4b §4.2、§5.2 | 模式切换期间等待 lock 和新 VSYNC | mode controller、boot timing、超时和恢复 |

## 未纳入功能

当前版本不包含 Deep Color、3D、4K、HBR 音频、HDCP、CEC、ARC/eARC。新增这些功能需要扩展接口、时钟、packet 和安全/物理层设计，并单独建立验证矩阵。

## 验证边界

RTL/XSim 不替代 TMDS 电气特性、显示器时钟容差、EDID 兼容性、长时间音视频同步、扬声器听感和 HDMI 认证。外部系统应记录目标器件、平台 profile、工具版本和测量方法。
