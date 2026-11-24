# 兼容性与支持矩阵

## 已实现配置

| 层级 | 配置 |
| --- | --- |
| 工具链 | Vivado/Vitis 2025.2.1 |
| 目标范围 | AMD/Xilinx 7-series；提供可选 Zynq-7000 adapter |
| 视频输出 | VIC 1、4、34、16，480p60、720p60、1080p30、1080p60 |
| 视频颜色 | RGB 4:4:4 8 bpc；可选 YCbCr 4:4:4 |
| HDMI 音频 | 双声道 24-bit LPCM，默认 48 kHz；静态 profile 支持 96/192 kHz |
| 输入接口 | VDMA MM2S、HLS AXI4-Stream、BRAM RGB565 |

输出时序由外部系统根据 sink 能力请求。PL 根据输入尺寸计算缩放几何，并在帧边界安全切换 profile。

## 验证层级

| 层级 | 验证方式 |
| --- | --- |
| 视频 scaler、模式控制、时序发生器和时钟 mux | Vivado Simulator SystemVerilog RTL bench |
| HDMI TMDS、AVI InfoFrame、LPCM packet 和 ACR | Vivado Simulator SystemVerilog RTL bench |
| PS EDID parser、模式选择和几何计算 | Host C tests，由集成系统提供或复用 |
| Composite IP 结构 | Vivado IP Catalog / Block Design validation |
| 板级输出 | 目标器件和板卡单独验证 |

## 新平台适配

新增器件 profile 时，配置 HDMI 时钟、TMDS I/O、复位和板级管脚。综合与实现记录器件资源和 setup/hold，目标板记录显示和音频结果。XC7Z020-1 的 1080p60 使用超频串行化配置，结果见[dev.6 验证记录](validation-2026-11-24.md)。
