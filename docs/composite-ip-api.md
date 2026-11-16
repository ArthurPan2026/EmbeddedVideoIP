# EmbeddedVideoIP 组合式顶层接口

## 产品边界

当前开发版本为 0.2.0-dev.4，PS C 库和发布包共用该版本。Vivado 外部 VLNV 固定为 panfpga.org:video:embedded_video_ip:1.0，作为 IP-XACT 兼容标识独立维护。消费者在 Vivado IP Integrator 中只实例化一个顶层组件：`panfpga.org:video:embedded_video_ip:1.0`。该组件内部组合现有视频处理核、视频输出桥、VTC、Zybo Z7-20 时钟 profile 和 7-series HDMI 发送适配器；消费者不在自己的 BD 中逐块连接 scaler、VTC、`v_axi4s_vid_out` 或 TMDS 发送逻辑。

EmbeddedVideoIP 是配套的 PL+PS 产品：PL 侧提供一个 Vivado IP Catalog 顶层组件，PS 侧提供匹配的通用 C API 与 Zynq-7000 adapter。PS/DDR 控制器、源数据生产器、系统时钟/复位及板级引脚仍由消费工程提供。

`video_pipeline` 保留为内部视频处理子块。Canonical RTL 位于 `ip/video_pipeline_1_0/hdl/`；`ip_repo/` 由 `tools/package_ip.tcl` 和 `tools/package_composite_ip.tcl` 从 canonical 源码重新生成，禁止手改生成副本。外层由参数化 RTL 顶层包装固定的视频输出 BD，所有内部子模块仍在本仓库中分层维护。

## 顶层 Vivado 组件

### 时钟与复位

| 接口 | 方向 | 用途 |
|---|---|---|
| `aclk` | 输入 | PS AXI-Lite 和视频 AXI4-Stream 使用的 100 MHz 时钟 |
| `aresetn` | 输入 | 系统 `aclk` 域低有效复位；内部音频与像素域同步释放复位 |
| `hdmi_ref_clk` | 输入 | 50 MHz HDMI 时钟参考，接入板级 Clock Wizard profile |

Zybo Z7-20 时钟 profile 使用 50 MHz `hdmi_ref_clk`，输出像素时钟约 25.178571 MHz、TMDS 串行时钟约 125.892857 MHz；VTC 固定为 640×480p60，不对其单独暴露 AXI-Lite 配置口。V1 采用固定的 Zybo Z7-20 时钟参数。其他消费板必须提供匹配的参考频率和输出 profile。

### 视频源

| 接口 | 方向 | 用途 |
|---|---|---|
| `s_axis_vdma` | 输入 | AMD AXI VDMA MM2S 的 32-bit 像素流，`TUSER` 为帧首，`TLAST` 为行尾 |
| `s_axis_hls` | 输入 | HLS AXI4-Stream Video 源 |
| BRAM 读接口 | 双向/输入输出 | `bram_en`、`bram_addr`、`bram_dout`、`bram_busy`、`bram_frame_done`；单周期延迟的 RGB565 双像素读口 |

源选择、输入格式、尺寸、stride、scale/bypass 和 fit/stretch 沿用视频处理核现有语义。VDMA 和帧缓冲由消费系统配置，EmbeddedVideoIP 接收 VDMA 的 AXI4-Stream 输出，不拥有 Zynq PS 的 DDR 控制器。

### PCM 音频源

| 信号 | 方向 | 定义 |
|---|---|---|
| `audio_pcm_clk` | 输入 | 100 MHz PCM AXI4-Stream 时钟 |
| `s_axis_audio_pcm_tdata[31:0]` | 输入 | 每个样本拍打包一对有符号 16-bit PCM；`[15:0]` 为左声道、`[31:16]` 为右声道 |
| `s_axis_audio_pcm_tvalid` | 输入 | 当前立体声样本对有效 |
| `s_axis_audio_pcm_tready` | 输出 | HDMI 音频通路可接受样本对时拉高 |

PCM 按 AXI4-Stream 规则握手：生产者只在 `TVALID && TREADY` 时推进样本，并在被背压期间保持 `TVALID/TDATA` 稳定。V1 的音频范围固定为 2 声道 16-bit/48 kHz LPCM，并匹配 25.178571 MHz 像素时钟。消费者不分别配置采样率和像素时钟；音源适配器负责按 48 kHz 提供样本有效节拍。实现覆盖 ACR、Audio InfoFrame 和 HDMI 数据岛子集，参考公开 HDMI 1.3 资料、AMD PG235 与 XAPP460。2026-11-16 在 GBA 消费工程中完成信号路径预验证，C1-1 捕获到音频 PCM；尚未确认扬声器听感，也未完成正式板级验收或 HDMI 认证，详见[预验证记录](validation-2026-11-16-hdmi-audio.md)。接口不包含应用或游戏专属语义。ACR 由静态 profile 的实际像素时钟计算。

### 控制与音频状态

| 接口 | 方向 | 用途 |
|---|---|---|
| `s_axi` | 输入/输出 | 唯一 AXI4-Lite 控制口，包含视频寄存器和 HDMI 音频控制寄存器 |

音频寄存器如下。PS API 与寄存器语义一致，消费应用不需要直接写寄存器。

| 偏移 | 名称 | 访问 | 定义 |
|---|---|---|---|
| `0x34` | `AUDIO_CTRL` | RW | bit 0：HDMI 音频使能；bit 1：静音；其他位保留 |
| `0x38` | `AUDIO_GAIN_Q15` | RW | bits `[16:0]`：增益 `0..32768`，`32768` 为 unity gain；其他位保留 |
| `0x3C` | `AUDIO_STATUS` | RO | bit 0：`HDMI_AUDIO_ENABLED` 配置状态；bit 1：音频欠载 sticky 状态；bit 2：保留，V1 恒为 0；其他位保留 |

`AUDIO_STATUS.bit1` 的欠载 sticky 状态由 `CTRL.bit10` 清除。V1 通过 AXI4-Stream 背压处理 FIFO 满状态，不产生溢出事件；因此 `AUDIO_STATUS.bit2` 保留并恒为 0。HDMI 音频使能变化经跨时钟同步，并在当前数据包结束后清空 FIFO。静音和增益在像素时钟域同步后作用于后续从 FIFO 读取的样本。

### 顶层接口名称

| BD接口/端口 | 方向 | 定义 |
|---|---|---|
| `s_axi` | 输入/输出 | AXI4-Lite 控制 |
| `s_axis_vdma` | 输入 | VDMA MM2S AXI4-Stream Video |
| `s_axis_hls` | 输入 | HLS AXI4-Stream Video 源 |
| BRAM pins | 双向/输入输出 | `bram_en`、`bram_addr`、`bram_dout`、`bram_busy`、`bram_frame_done` |
| `s_axis_audio_pcm` | 输入 | 32-bit 双声道 PCM AXI4-Stream |
| `tmds_tx_clk_p/n` | 输出 | HDMI TMDS 时钟差分对 |
| `tmds_tx_data_p/n[2:0]` | 输出 | HDMI TMDS 三组数据差分对 |

`aclk` 关联 `s_axi`、`s_axis_hls` 和 `s_axis_vdma`，频率为 100 MHz。`audio_pcm_clk` 关联 `s_axis_audio_pcm`，频率也为 100 MHz。共用的 `aresetn` 在 `aclk` 接口元数据中声明，内部音频和像素时钟域分别同步释放复位。固定视频输出 BD 把 `v_axi4s_vid_out`、VTC 和时钟配置接到 HDMI TX。EmbeddedVideoIP 不提供 I²S、HPD 或 DDC 接口；其他音频设备和 HDMI sideband 由消费项目管理。

Zybo Z7-20 使用 7-series HDMI 发送适配器。其他器件系列只能在提供匹配的时钟/PHY 子模块并完成器件、时序和板级验证后加入支持矩阵。

## 静态功能配置

同一 IP 版本用 Vivado 参数裁剪 HDMI 音频逻辑：

- `ENABLE_HDMI_AUDIO=0` 时不综合 PCM FIFO、音频格式化和 HDMI 音频 packetizer，但视频 TMDS 输出仍可用。
- `ENABLE_HDMI_AUDIO=1` 时综合完整的 HDMI 音频路径，可由 `AUDIO_CTRL` 在运行时使能/静音。
- V1 固定双声道 48 kHz PCM 和 Zybo HDMI 时钟 profile；采样率/像素时钟作为匹配配置一起生成。

这些是同一 EmbeddedVideoIP 版本的静态 profile，不发布相互分叉的核心版本。需要 HDMI 音频与不需要音频的消费项目通过配置选择所需逻辑。

## 配套 PS C API

通用接口提供 `VideoOut_SetHdmiAudioEnabled`、`VideoOut_SetAudioMute`、`VideoOut_SetAudioGainQ15` 和 `VideoOut_GetAudioStatus`；Zynq-7000 adapter 提供对应的 `VideoOutXilinx_` 封装。视频和音频共用同一个 `VideoOutIo` AXI-Lite 访问对象。

消费工程的 UI 自己管理完整音频输出路径。选择 HDMI 时调用 `VideoOutXilinx_SetHdmiAudioEnabled(..., 1)`；使用其他音频后端时关闭 HDMI 音频并由消费工程配置该路径。音源和 UI 路由均留在消费工程，EmbeddedVideoIP 不依赖特定音源。

## IP Catalog、构建与验证

`tools/video_flow.py package` 先生成内部 `video_pipeline`，再从 canonical HDL、Digilent 源码和固定视频输出 BD 打包外层 `embedded_video_ip`。消费者只添加外层 VLNV。外层内部包含 `video_pipeline`、`v_axi4s_vid_out`、VTC、Zybo 时钟 profile 和 `embedded_video_ip_7series_tx`，不包含 PS/CIPS、I²S、HPD 或 DDC。

`validate` 检查 composite IP 的端口映射、AXI-Lite 地址段、音频静态参数和 IP Catalog 实例。`synth --profile composite_audio_off` 与 `composite_audio_on` 使用同一视频配置，分别记录 LUT/FF/LUTRAM/BRAM、WNS/WHS/TNS/THS、输入哈希和产物哈希。
