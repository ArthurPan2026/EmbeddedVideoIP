# EmbeddedVideoIP 组合式顶层接口

## 顶层组成

外部系统在 Vivado IP Integrator 中实例化 `panfpga.org:video:embedded_video_ip:1.0`。该 IP 包含视频源适配、scaler、AXI4-Stream Video 输出桥、运行时视频时序、四模式时钟和 7-series HDMI 发送器。HDMI 音频按静态参数配置。

外部系统连接 PS/CIPS、DDR、AXI VDMA、输入帧缓冲、系统时钟和板级引脚。EDID 读取、sink 能力选择和模式请求由外部控制软件完成。

## 视频输出模式

| 模式码 | CTA VIC | 活动区 | 像素时钟标称值 | 当前实现频率 |
|---|---:|---:|---:|---:|
| 0 | 1 | 640×480 | 25.175 MHz | 25.178571 MHz |
| 1 | 4 | 1280×720 | 74.250 MHz | 74.250000 MHz |
| 2 | 34 | 1920×1080 | 74.250 MHz | 74.250000 MHz |
| 3 | 16 | 1920×1080 | 148.500 MHz | 148.500000 MHz |

VIC 4、VIC 34 和 VIC 16 使用 HD 参考源，serializer MMCM 通过输出分频生成对应时钟。切换时控制器等待当前帧结束，再切换时钟并等待新模式 VSYNC。双行 BRAM 读取、行 bank 生命周期和 AXI 停顿行为见[缩放器架构图](architecture.md#双行-bram-预取缩放器)。

## 视频输入

`s_axis_vdma` 接收 AMD AXI VDMA MM2S 的 32-bit 像素流。`TUSER[0]` 标记帧首，`TLAST` 标记行尾。输入尺寸最大 1280×720，源帧、stride 和帧缓存由外部系统配置。

视频处理核支持 RGB565、RGB888 和 XRGB8888 输入转换。scaler 支持精确 1:1 旁路、最近邻缩放、fit 和 stretch，输出尺寸最大 1920×1080。`LINE_BUFFER_IMPLEMENTATION=0` 选择单行 scaler，可使用 LUTRAM 或同步 BRAM。`LINE_BUFFER_IMPLEMENTATION=1` 选择双行 BRAM 预取 scaler。

## PCM 音频输入

| 信号 | 方向 | 定义 |
|---|---|---|
| `audio_pcm_clk` | 输入 | PCM AXI4-Stream 时钟 |
| `s_axis_audio_pcm_tdata[47:0]` | 输入 | `[23:0]` 左声道；`[47:24]` 右声道 |
| `s_axis_audio_pcm_tvalid` | 输入 | 当前立体声样本对有效 |
| `s_axis_audio_pcm_tready` | 输出 | 音频 FIFO 可接收样本对时拉高 |

源端只在 `TVALID && TREADY` 时推进样本，并在背压期间保持数据稳定。默认采样率为 48 kHz，静态 profile 支持 96 kHz 和 192 kHz。

## AXI-Lite 控制

`s_axi` 是唯一控制口。先写输入尺寸、stride 和几何字段，再置 CTRL bit 8 提交。CTRL[15:14] 选择输出模式；同一次 CTRL 写入同时置 bit 8 与 bit 16 时，几何和模式作为一个事务提交。

## TMDS 输出与打包

`tmds_tx` 输出 TMDS clock 和三组 data 差分信号。TMDS 接口定义位于 `ip_repo/if/tmds_v1_0/`。`tools/video_flow.py package` 生成内部视频核和组合式 EmbeddedVideoIP，`validate` 检查 Catalog 接口、寄存器窗口和参数。
