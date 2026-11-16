# EmbeddedVideoIP

EmbeddedVideoIP 0.2.0-dev.4 是面向 Vivado PL+PS 工程的可复用视频输出子系统。消费者在 Vivado IP Integrator 中使用一个组合式顶层 IP；内部集成视频处理、输出时序、HDMI 发送适配和可选 HDMI 音频。配套 PS C 库负责配置视频、VDMA 和 HDMI 音频。

V1 只交付 PL+PS 配套产品，不支持 PL-only。既有视频输出路径已在 Zybo Z7-20 / XC7Z020 / Zynq-7000 上验证，构建工具为 Vivado/Vitis 2025.2.1。2026-11-16 已在 GBA 消费工程上完成 HDMI 音频信号路径预验证：C1-1 USB3 Audio 采到 48 kHz PCM，且采集电平随音量设定变化。这证明音频数据到达采集卡，不代表显示器扬声器听感或 HDMI 标准符合性已经通过；正式板级验收与 HDMI 认证仍未完成。细节见[HDMI 音频预验证记录](docs/validation-2026-11-16-hdmi-audio.md)。

## 功能结构

- 输入支持 BRAM RGB565、HLS AXI4-Stream Video 和 AMD AXI VDMA MM2S 视频流。
- 视频处理支持 RGB 格式归一化、旁路、最近邻缩放、等比例留边和拉伸。
- scaler 行缓冲可选择 LUTRAM 或同步 BRAM；未使用的输入源和 HDMI 音频可由综合参数静态裁剪。
- Composite IP 内部包含 video pipeline、`v_axi4s_vid_out`、VTC、板级时钟 profile 和 7-series HDMI 发送适配器；消费者只添加 EmbeddedVideoIP 顶层。
- 可选 HDMI 音频接收通用双声道 PCM AXI4-Stream，并输出 HDMI LPCM 音频。该 IP 不包含 I²S codec 发送路径；消费者可以在自己的板级和应用工程中保留其他音频设备。

内部视频流使用 AXI4-Stream Video。`TUSER[0]` 标记帧首，`TLAST` 标记行尾；视频核心对 RGB888 做通道归一化后处理。跨时钟源应在消费 BD 中按其时钟关系配置合适的 AXI4-Stream Clock Converter。

## HDMI 音频接口

V1 音频只实现固定 640×480p60 视频模式下的双声道 16-bit/48 kHz LPCM、ACR、Audio InfoFrame 和数据岛子集。实现参考公开的 HDMI 1.3 资料、AMD PG235 与 XAPP460，2026-11-16 已在 GBA 消费工程完成音频信号路径预验证；正式 HDMI 认证和板级音频验收仍未完成，详见[预验证记录](docs/validation-2026-11-16-hdmi-audio.md)。PCM 输入每次握手传输一对有符号 16-bit 样本：`TDATA[15:0]` 为左声道，`TDATA[31:16]` 为右声道。V1 默认采样率为 48 kHz。AXI4-Stream 的 `TVALID/TREADY` 负责背压；消费项目负责提供采样节拍正确的 PCM 样本。

音频链路通过 `AUDIO_CTRL` 控制 HDMI 音频使能和静音，通过 `AUDIO_GAIN_Q15` 配置音量，并可读取 FIFO 欠载状态。V1 的状态寄存器 bit 2 保留并恒为 0。详细接口见[组合式顶层接口](docs/composite-ip-api.md)和[寄存器表](docs/register-map.md)。

## 快速上手

第一次使用请按[PL+PS 快速上手](docs/quickstart-zh.md)执行。完整的系统边界、板级适配和接口约定见[架构说明](docs/architecture.md)及[兼容性矩阵](docs/compatibility.md)。

## 构建与验证

```sh
python3 tools/video_flow.py doctor
python3 tools/video_flow.py build --part xc7z020clg400-1 --profile composite_audio_off
python3 tools/video_flow.py status
```

`build --profile composite_audio_off` 运行 XSim/主机回归、打包组合式 IP、执行 IP Catalog 验证，并综合音频关闭 profile。将 profile 改为 `composite_audio_on` 可测 HDMI 音频开启的资源开销。综合 profile 及输入/产物哈希写入 `out/manifest.json`；中间项目和报告保存在 `out/`。阶段说明、增量规则和音频 profile 见[构建与使用](docs/build-and-use.md)；验证范围和结果归档见[验证流程](docs/validation.md)。

## 仓库结构

- `ip/video_pipeline_1_0/hdl/`：唯一 canonical 视频处理 RTL 源码及 7-series HDMI 输出适配 RTL。
- `tools/package_ip.tcl`：生成内部视频处理核。
- `tools/package_composite_ip.tcl`：生成消费者使用的单一 EmbeddedVideoIP 顶层 IP。
- `ip_repo/`：由打包流程生成的 Vivado IP Catalog 产物，不手工编辑。
- `software/`：平台无关 PS API，以及 Zynq-7000 VDMA/MMIO adapter。
- `platforms/`：板级时钟、引脚和器件配置。
- `tests/`：HDL 仿真、PS C API 和构建流程回归。

HDMI 输出后端与视频算法分层管理。Zybo Z7-20 使用 7-series TMDS/OSERDES 适配；更换器件系列前，必须对对应后端、约束、时序和实板功能重新验证。

## 许可与依赖

第三方 Digilent 源码和依赖版本通过 `dependencies.lock.json` 固定；复制或修改时必须保留其原始许可证。项目自有代码的再分发条件及来源说明见 [NOTICE.md](NOTICE.md)。
