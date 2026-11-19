# EmbeddedVideoIP

EmbeddedVideoIP 0.3.0-dev.2 是面向 Vivado PL+PS 工程的视频输出子系统。消费者在 IP Integrator 中实例化一个组合式顶层。PL 包含视频 scaler、时序 profile、HDMI packet 处理、TMDS 编码和 7-series 串行器。PS C 库配置 VDMA、视频几何和 HDMI 音频。

## HDMI 1.4b 视频 profile

| CTA VIC | 时序 | 活动区 | 实际像素时钟 |
|---:|---|---:|---:|
| 1 | 640×480p60 | 640×480 | 25.178571 MHz |
| 4 | 720p60 | 1280×720 | 74.218750 MHz |
| 34 | 1080p30 | 1920×1080 | 74.218750 MHz |

PS 消费端读取 EDID，并优先选择 VIC 4，其次选择 VIC 34。PL 在帧边界切换像素时钟和输出时序。音频 ACR 按实际像素时钟计算。

VIC 4 和 VIC 34 的时钟 profile 实际输出 74.218750 MHz；CTA 标称值为 74.25 MHz。差异约 421 ppm。

## 视频和颜色

视频源支持 BRAM RGB565、HLS AXI4-Stream Video 和 VDMA MM2S。最近邻 scaler 可做旁路、fit 和 stretch。最大输入为 1280×720，最大输出为 1920×1080。行缓冲可选 LUTRAM 或同步 BRAM。

颜色默认使用 RGB 4:4:4、8 bpc。静态参数还可选择 YCbCr 4:4:4、BT.601/BT.709 和 Full/Limited range。AVI InfoFrame 随 VIC 和颜色 profile 更新。当前 HDMI TX 使用 8 bpc profile。

## 24-bit LPCM 音频

Composite 顶层接收 48-bit PCM AXI4-Stream：TDATA[23:0] 是有符号左声道，TDATA[47:24] 是有符号右声道。默认采样率为 48 kHz；静态 profile 还支持 96 kHz 和 192 kHz。GBA 的 16-bit PCM 在消费端符号扩展到 24 bit，I²S codec 路径保持原配置。

## 构建和验证

    python3 tools/video_flow.py doctor
    python3 tools/video_flow.py sim
    python3 tools/video_flow.py package
    python3 tools/video_flow.py validate
    python3 tools/video_flow.py build --part xc7z020clg400-1 --profile composite_audio_on

`build` 运行 SystemVerilog RTL 回归、PS C API 主机测试、IP Catalog 验证和 OOC 综合。HDMI 1.4b 功能与 RTL 测试对应关系见 [HDMI 合规映射](docs/hdmi-1.4b-conformance.md)。构建输入、输出哈希和报告保存在 `out/`。

## GBA 消费工程

GBA 的 `PS_APP_NATIVE_720P_INPUT` 编译选项默认开启。LVGL、软件合成器和 VDMA 使用 1280×720 XRGB8888 帧。三帧缓冲区各预留 4 MiB，内存范围为 0x18000000～0x18C00000。设置该选项为 `OFF` 可使用 640×480 输入，并由 PL scaler 放大。

## 仓库结构

- `ip/video_pipeline_1_0/hdl/`：canonical SystemVerilog / Verilog。
- `tools/package_ip.tcl`：生成内部视频处理核。
- `tools/package_composite_ip.tcl`：生成组合式 IP。
- `ip_repo/`：Vivado IP Catalog 产物。
- `ip_repo/if/tmds_v1_0/`：项目维护的 TMDS 总线定义。
- `software/`：平台无关 PS C API 和 Zynq-7000 adapter。
- `tests/rtl/`：SystemVerilog 仿真。
