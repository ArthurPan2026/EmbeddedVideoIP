# EmbeddedVideoIP 组合式顶层接口

## 产品边界

消费者在 Vivado IP Integrator 中实例化 `panfpga.org:video:embedded_video_ip:1.0`。该 IP 内部包含视频源适配、scaler、AXI4-Stream Video 输出桥、运行时视频时序、双 profile 时钟和 7-series HDMI 发送器。HDMI 音频按静态参数裁剪。

消费工程连接 PS/CIPS、DDR、AXI VDMA、输入帧缓冲、系统时钟和板级引脚。消费端 PS 软件读取 EDID，并按 sink 能力选择输出模式。

## 视频输出模式

| 模式码 | CTA VIC | 活动区 | 像素时钟标称值 | 当前实现频率 |
|---|---:|---:|---:|---:|
| 0 | 1 | 640×480 | 25.175 MHz | 25.178571 MHz |
| 1 | 4 | 1280×720 | 74.250 MHz | 74.218750 MHz |
| 2 | 34 | 1920×1080 | 74.250 MHz | 74.218750 MHz |

VIC 4 和 VIC 34 共用 HD clock profile。时序发生器按 profile 选择水平、垂直 totals、porches 和同步极性。TMDS 串行时钟保持像素时钟的 5 倍。HD profile 的实际像素时钟比 CTA 标称值低约 421 ppm。ACR 使用实际频率计算。

切换模式时，控制器等待当前帧结束，再切换时钟。像素域保持复位，直到新时钟稳定且 scaler 几何已提交。控制器释放复位后等待新模式 VSYNC。

## 视频输入

`s_axis_vdma` 接收 AMD AXI VDMA MM2S 的 32-bit 像素流。`TUSER[0]` 标记帧首，`TLAST` 标记行尾。输入尺寸最大 1280×720。源帧、行 stride 和三帧缓冲区由消费工程配置。

`s_axis_hls` 接收 HLS AXI4-Stream Video。BRAM 源使用同步 32-bit 读口，每个字包含两个 RGB565 像素，低半字先输出。

视频处理核支持 RGB565、RGB888 和 XRGB8888 输入转换。scaler 支持旁路、最近邻缩放、fit 几何和 stretch。输出尺寸最大 1920×1080。行缓冲可选 LUTRAM 或同步 BRAM；Zybo Z7-20 GBA profile 使用 BRAM 行缓冲。

GBA 消费工程默认使用 LVGL 原生 1280×720 XRGB8888 输入。每帧 slot 为 4 MiB，三帧共 12 MiB。显式关闭 `PS_APP_NATIVE_720P_INPUT` 可构建 640×480 低负载输入。

## PCM 音频输入

| 信号 | 方向 | 定义 |
|---|---|---|
| `audio_pcm_clk` | 输入 | PCM AXI4-Stream 时钟，Zybo profile 为 100 MHz |
| `s_axis_audio_pcm_tdata[47:0]` | 输入 | `[23:0]` 是有符号左声道；`[47:24]` 是有符号右声道 |
| `s_axis_audio_pcm_tvalid` | 输入 | 当前立体声样本对有效 |
| `s_axis_audio_pcm_tready` | 输出 | HDMI 音频 FIFO 可接收样本对时拉高 |

音源按 `AUDIO_SAMPLE_RATE_HZ` 提供 PCM。默认采样率为 48 kHz，静态 profile 还支持 96 kHz 和 192 kHz。源端只在 TVALID 与 TREADY 同时为 1 时推进样本，并在背压期间保持数据稳定。

## 像素格式

`OUTPUT_COLOR_MODE=0` 发送 RGB 4:4:4、8 bpc。`OUTPUT_COLOR_MODE=1` 发送 YCbCr 4:4:4、8 bpc。`COLORIMETRY` 选择 BT.601 或 BT.709，`YCC_RANGE` 选择 Limited 或 Full。AVI InfoFrame 跟随像素格式、色度和 VIC 更新。

`OUTPUT_COLOR_DEPTH` 的当前有效值为 8。HDMI 1.4b Deep Color 10 bpc 需要 30-bit 像素组打包和新的 TMDS 时钟 profile。

## AXI-Lite 控制

`s_axi` 是唯一控制口。完整寄存器定义见[寄存器表](register-map.md)。消费端先写输入尺寸、stride 和几何字段，再置 CTRL bit 8 提交。CTRL[15:14] 选择输出模式；同一次 CTRL 写入同时置 bit 8 与 bit 16 时，几何和模式一起提交。

GBA 端校验 EDID/CEA 扩展后，优先选择 sink 支持的 VIC 4，其次选择 VIC 34。输入画面按目标活动区居中适配。模式切换期间，消费端等活动模式与请求模式一致后再恢复新帧提交。

## TMDS 输出与打包

`tmds_tx` 输出 TMDS clock 和三组 data 差分信号。物理端口名保持 `tmds_tx_clk_p/n` 与 `tmds_tx_data_p/n[2:0]`，便于延用板级 XDC。TMDS 接口定义位于 `ip_repo/if/tmds_v1_0/`。

`tools/video_flow.py package` 生成内部视频核和组合式 EmbeddedVideoIP。`validate` 检查 IP Catalog 的接口、寄存器窗口和参数。`sim` 运行 SystemVerilog RTL 回归、PS C API 主机测试和构建流程测试。
