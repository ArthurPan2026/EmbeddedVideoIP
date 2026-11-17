# PL+PS 快速上手

## 支持范围

EmbeddedVideoIP 0.3.0-dev.1 以配套 PL+PS 产品交付。消费者在 IP Integrator 中只添加 `panfpga.org:video:embedded_video_ip:1.0` 顶层组件。V1 板级参考配置为 Zybo Z7-20 / XC7Z020 / Zynq-7000，Vivado/Vitis 2025.2.1，视频输出固定 640×480p60。

视频输入支持 VDMA MM2S、HLS AXI4-Stream 和 BRAM RGB565。HDMI 音频配置为固定 2 声道 16-bit/48 kHz LPCM，并生成 ACR、Audio InfoFrame 和数据岛子集。2026-11-16 的 GBA 消费工程预验证已在 C1-1 采到 PCM；显示器扬声器听音、正式板级验收和 HDMI 认证仍未完成，详见[预验证记录](validation-2026-11-16-hdmi-audio.md)。EmbeddedVideoIP 不包含 I²S codec 输出；如果消费板需要 codec，codec 数据与初始化留在消费工程。

## 构建和验证 IP

在安装了 Vivado 2025.2.1 的 Linux 主机上运行：

```sh
python3 tools/video_flow.py doctor
python3 tools/video_flow.py build --part xc7z020clg400-1 --profile composite_audio_off
```

`build` 运行 XSim 和主机 C/Python 回归，生成内部视频核与组合式 IP 包，验证 IP Catalog，再对所选综合 profile 做 OOC 综合。结果、输入指纹和报告哈希记录在 `out/manifest.json`。

常用单阶段命令：

```sh
python3 tools/video_flow.py sim
python3 tools/video_flow.py package
python3 tools/video_flow.py validate
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile vdma_scaler_bram
python3 tools/video_flow.py status
```

## 在消费工程中实例化

将 EmbeddedVideoIP 的 `ip_repo/` 加入 Vivado 工程 IP Repository，更新 Catalog，并添加 `EmbeddedVideoIP` 顶层。消费工程不需要逐块连接 VTC、`v_axi4s_vid_out`、Clock Wizard 或 7-series HDMI 发送后端。

顶层主要连接：

- `s_axi`：连接 PS AXI 主端口，作为唯一的视频/HDMI 音频控制接口。
- `aclk/aresetn`：连接 100 MHz PS FCLK 和低有效复位。
- `hdmi_ref_clk`：Zybo Z7-20 profile 使用 PS FCLK0 50 MHz 作为 HDMI 时钟参考。
- `s_axis_vdma`：连接消费工程 AMD AXI VDMA 的 MM2S AXI4-Stream 输出。
- `s_axis_hls`：需要 HLS 视频源时连接其 AXI4-Stream Video 输出。
- BRAM 读接口：需要 BRAM 源时连接帧缓存双口 RAM。
- `audio_pcm_clk` 与 `s_axis_audio_pcm_*`：HDMI 音频启用时，输入 100 MHz 时钟和 48 kHz 立体声 PCM 样本流。
- `tmds_tx_*`：约束到目标板 HDMI TX 引脚。时钟 profile 当前生成约 25.178571 MHz 像素时钟和 125.892857 MHz 串行时钟。HPD 与 DDC 不属于 EmbeddedVideoIP 顶层。消费系统继续用 PS GPIO/IIC 管理这两路信号。

消费工程仍负责 PS/DDR、VDMA 帧地址和 stride、AXI 时钟/复位、BRAM/HLS 源数据，以及 HDMI DDC/HPD 的板级连线。HDMI 音频以外的音频输出设备也由消费工程管理。

## 配置 HDMI 音频

音频流每次 AXI 握手传输左右声道一对有符号 16 位 PCM 样本：`TDATA[15:0]=L`，`TDATA[31:16]=R`。源端以 48 kHz 节拍拉高 `s_axis_audio_pcm_tvalid`，并在 `s_axis_audio_pcm_tready` 为低时保持数据。PCM AXI 音频时钟为 100 MHz。

PS 端调用配套 API：

```c
#include "video_out_xilinx.h"

VideoOutXilinx_SetHdmiAudioEnabled(&video, 1U);
VideoOutXilinx_SetAudioMute(&video, 0U);
VideoOutXilinx_SetAudioGainQ15(&video, 32768U); /* 单位增益 */
```

采样率与静态功能由 Vivado IP 参数配置。若项目不使用 HDMI 音频，将 `ENABLE_HDMI_AUDIO=0`，综合会裁掉 PCM FIFO、LPCM/ACR/Audio InfoFrame 逻辑和动态包存储，保留 HDMI 1.4b 所需的 AVI Data Island。I²S codec 路由由消费工程独立管理，消费 UI 可在 HDMI 音频使能与 codec 播放之间切换。

寄存器和 API 细节见[寄存器表](register-map.md)和[组合式 IP 接口](composite-ip-api.md)。

## 可验证 profile

`vdma_scaler_lutram` 与 `vdma_scaler_bram` 使用同一条源代码路径，分别选择 LUTRAM/BRAM 行缓冲。`passthrough` 固定 VDMA 源并关闭 scaler。HDMI 音频 off/on profile 也使用同一个 EmbeddedVideoIP VLNV，通过静态参数裁剪。完整构建与验收流程见[构建与使用](build-and-use.md)。
