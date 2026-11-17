# 构建与使用

首次使用请先读[PL+PS 快速上手](quickstart-zh.md)和[组合式顶层接口](composite-ip-api.md)。自动验证与验收记录见[验证流程](validation.md)。消费者在 Vivado BD 中只实例化 `panfpga.org:video:embedded_video_ip:1.0`，PS 侧安装同版本 C 库。

## 工具与依赖

项目与配套 PS 库版本取自 VERSION 文件，当前为 0.3.0-dev.1。外部 EmbeddedVideoIP VLNV 保持 panfpga.org:video:embedded_video_ip:1.0。

- 当前 Zybo Z7-20 profile 固定 Vivado/Vitis 2025.2.1。
- Digilent `TMDS_Encoder`、`DVI_Constants` 和 `OutputSERDES` 源码的来源提交与哈希固定在 `dependencies.lock.json`。
- `video_flow.py` 使用 Python 3；XSim/C 回归需要 Vivado、GCC 和 Python unittest。

## 分阶段命令

```sh
python3 tools/video_flow.py doctor
python3 tools/video_flow.py sim
python3 tools/video_flow.py package
python3 tools/video_flow.py validate
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile vdma_scaler_bram
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile composite_audio_off
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile composite_audio_on
python3 tools/video_flow.py status
```

`doctor` 检查 Vivado 版本。`sim` 运行 XSim 视频/音频 RTL 测试、PS C API 主机测试和库安装器回归。`package` 先生成内部视频处理核，再生成唯一的 `panfpga.org:video:embedded_video_ip:1.0` IP-XACT 包。`validate` 在 Vivado IP Catalog 中实例化组合式 EmbeddedVideoIP，并验证端口、地址映射和参数。`synth` 对指定器件和静态 profile 做 OOC 综合。

`build` 顺序运行 `sim → package → validate → synth`：

```sh
python3 tools/video_flow.py build --part xc7z020clg400-1 --profile vdma_scaler_bram
```

构建使用内容 SHA-256 指纹。只有阶段输入、Vivado 版本和目标参数相同且所有输出哈希匹配时才命中缓存。阶段日志、利用率/时序报告和 `qor.json` 保存在 `out/`；失败阶段不会覆盖最后一次成功记录。 Composite profile 的时序报告是预布线 OOC 数据，不作为板级签核；最终时序以消费工程的 post-route STA 为准。

## 综合 profile

当前视频 profile 用于选择 scaler 和行缓冲：

| Profile | 配置 | 用途 |
|---|---|---|
| `generic` | 保留运行时源/格式选择，启用 scaler | 通用基线 |
| `vdma_scaler_lutram` | 固定 VDMA/XRGB，最近邻 scaler 使用 LUTRAM | BRAM 紧张时 |
| `vdma_scaler_bram` | 固定 VDMA/XRGB，最近邻 scaler 使用同步 BRAM | LUT 紧张时 |
| `passthrough` | 固定 VDMA/XRGB，静态关闭 scaler | 不需要缩放时 |
| `composite_audio_off` | Zybo 参考 profile，静态关闭 HDMI 音频 | 保留 AVI serializer，检查音频路径的静态裁剪 |
| `composite_audio_on` | 相同视频 profile，启用 HDMI 音频 | 对比音频逻辑的资源开销 |

音频 profile 使用同一个 EmbeddedVideoIP VLNV，只改变静态参数 `ENABLE_HDMI_AUDIO`。关闭音频时，综合会裁掉 PCM FIFO、LPCM/ACR/Audio InfoFrame 逻辑和动态包存储，保留固定 AVI Data Island 路径。开启音频时，综合双声道 48 kHz PCM 和通用 packet store。`validate` 和 OOC 综合分别覆盖音频开关，并记录资源与时序报告。

## 封装结构

- `ip/video_pipeline_1_0/hdl/`：唯一 canonical RTL 源码。
- `tools/package_ip.tcl`：生成内部视频处理核。
- `tools/package_composite_ip.tcl`：在一个 RTL 顶层 IP 中组合内部视频核、固定视频输出 BD、时钟与 7-series HDMI TX。
- `ip_repo/`：Vivado IP Catalog 生成包，只由 packaging stage 写入。
- `software/`：平台无关 PS C API。
- `software/platforms/xilinx_zynq7000/`：Zynq-7000 VDMA/MMIO adapter；HDMI 音频控制 API 复用同一个 AXI-Lite 接口。
- `platforms/amd_7series/`：Zybo Z7-20 时钟、I/O 和支持矩阵。

消费者只实例化一个 EmbeddedVideoIP 顶层。PS/CIPS 和 DDR memory controller 仍属于消费系统；消费工程连接 VDMA/HLS/BRAM 源、PCM AXI-Stream、单一 AXI-Lite 控制口和 TMDS 引脚。HPD/DDC 由消费系统单独接到 PS GPIO/IIC。
