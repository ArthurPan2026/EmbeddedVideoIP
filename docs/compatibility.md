# 兼容性与支持矩阵

## 已实现配置

| 层级 | 配置 |
|---|---|
| 工具链 | Vivado/Vitis 2025.2.1 |
| 目标板 | Zybo Z7-20、XC7Z020、Zynq-7000 |
| 视频输出 | CEA-861-D VIC 1、VIC 4、VIC 34 |
| 视频颜色 | RGB 4:4:4 8 bpc；YCbCr 4:4:4 8 bpc，支持 BT.601/BT.709 与 Full/Limited range |
| HDMI 音频 | 双声道 24-bit LPCM，默认 48 kHz；静态 profile 支持 96/192 kHz |
| PS 视频输入 | GBA LVGL 默认1280×720 XRGB8888；640×480 profile可供低负载构建使用 |

HDMI 输出时序由消费端 EDID 能力决定。GBA 优先请求 VIC 4，再选择 VIC 34。sink 仅声明 VIC 1 时，消费端请求 640×480p60。PL 根据输入尺寸计算缩放几何，并在帧边界安全切换 profile。

## 验证层级

| 层级 | 验证方式 |
|---|---|
| 视频 scaler、模式控制、时序发生器和时钟 mux | Vivado Simulator SystemVerilog RTL bench |
| HDMI TMDS、AVI InfoFrame、LPCM packet 和 ACR | Vivado Simulator SystemVerilog RTL bench |
| PS EDID parser、模式选择和几何计算 | C host tests |
| Composite IP 结构 | Vivado IP Catalog / Block Design validation |
| GBA 消费工程 | PS app build 与 VDMA/EVIP 参数检查 |
| 板级输出 | Zybo Z7-20 HDMI/TMDS 时钟与视频输出测试 |

## 时钟 profile

VGA profile 使用 25.178571 MHz pixel clock 和 125.892857 MHz TMDS serial clock。VIC 4 和 VIC 34 使用 74.218750 MHz pixel clock 和 371.093750 MHz serial clock。HD clock 实际值比 74.25 MHz CTA 标称值低约 421 ppm，音频 ACR 按实际频率计算。

## 新板卡适配

新增器件 profile 时，需要配置 HDMI 时钟、TMDS I/O、复位和板级管脚。综合与实现报告记录器件资源和 setup/hold。HDMI 模式、音频和显示器兼容性通过目标板验证后，加入板卡支持矩阵。
