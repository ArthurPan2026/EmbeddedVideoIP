# 构建与使用

首次使用请先读[PL+PS 快速上手](quickstart-zh.md)和[组合式顶层接口](composite-ip-api.md)。自动验证范围见[验证流程](validation.md)。集成系统在 Vivado BD 中实例化 `panfpga.org:video:embedded_video_ip:1.0`，并按平台 profile 连接 PS、DDR、VDMA、PCM 和 TMDS。

## 工具与依赖

版本取自 `VERSION` 文件。Vivado packaging 使用 canonical SystemVerilog 和 `ip_repo/if` 中的接口文件。`video_flow.py` 使用 Python 3；XSim/C 回归需要 Vivado、GCC 和 Python unittest。

## 分阶段命令

```sh
python3 tools/video_flow.py doctor
python3 tools/video_flow.py sim
python3 tools/video_flow.py package
python3 tools/video_flow.py validate
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile vdma_scaler_bram
python3 tools/video_flow.py status
```

`sim` 运行 RTL、Host C 和流程测试。`package` 生成内部视频处理核和组合式 IP-XACT 包。`validate` 在 Vivado IP Catalog 中实例化组合式 IP，检查端口、地址映射和参数。`synth` 对指定器件和 profile 做 OOC 综合。

构建使用内容 SHA-256 指纹。阶段日志、利用率/时序报告和 `qor.json` 保存在 `out/`。Composite profile 的时序报告是预布线 OOC 数据，不作为完整器件签核。

## 综合 profile

| Profile | 配置 | 用途 |
|---|---|---|
| `generic` | 保留运行时源/格式选择，启用 scaler | 通用基线 |
| `vdma_scaler_lutram` | 固定 VDMA/XRGB，最近邻 scaler 使用 LUTRAM | LUTRAM 资源充足时 |
| `vdma_scaler_bram` | 固定 VDMA/XRGB，最近邻 scaler 使用同步 BRAM | BRAM 行缓冲配置 |
| `passthrough` | 固定 VDMA/XRGB，静态关闭 scaler | 不需要缩放时 |
| `composite_audio_off` | 静态关闭 HDMI 音频 | 比较关闭音频后的资源 |
| `composite_audio_on` | 启用 HDMI 音频 | 比较音频逻辑资源 |

## 封装结构

- `ip/video_pipeline_1_0/hdl/`：唯一 canonical RTL 源码。
- `tools/package_ip.tcl`：生成内部视频处理核。
- `tools/package_composite_ip.tcl`：生成组合式 IP。
- `ip_repo/`：Vivado IP Catalog 生成包。
- `software/`：平台无关 PS C API和可选平台 adapter。
- `platforms/`：器件、时钟、I/O 和支持矩阵 profile。

外部系统只实例化一个 EmbeddedVideoIP 顶层。系统自行连接 VDMA/HLS/BRAM 源、PCM AXI-Stream、AXI-Lite 控制口、HPD/DDC 和 TMDS 引脚。
