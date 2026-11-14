# Embedded Video IP 验证记录

记录范围是可复用库本身，包括 SystemVerilog 核心、PS C 库、Vivado 打包流程和目标器件 OOC 综合。消费工程的应用配置、板级部署产物和运行数据由各自工程保存。

## 自动回归

- Python 主机测试：18 项通过。覆盖库安装器、构建缓存、SHA-256 输入清单、profile 参数和 Vivado 报告解析。
- C 主机测试：`test_video_out` 通过。覆盖视频配置、fit 几何、VDMA 参数、状态读取和错误处理。
- Vivado XSim：缩放器 LUTRAM 与 BRAM 两种实现、RGB565 BRAM 读端、通用视频管线和静态直通配置均通过。
- XSim 检查了输出停顿期间的 `TDATA`、`TUSER` 和 `TLAST` 稳定性。BRAM 实现通过同步读寄存器提供像素，并在有效输出被接收时重填读级。

## IP 包与目录验证

Vivado 2025.2.1 将核打包为 `panfpga.org:video:video_pipeline:1.0`。IP Catalog/BD 检查覆盖固定源、缩放使能、最大缓冲尺寸和行缓冲实现选择。

## OOC 综合

本轮对 `generic`、`vdma_scaler_lutram`、`vdma_scaler_bram` 和 `passthrough` 运行 XC7Z020 OOC 综合。每个 profile 记录 LUT、FF、LUTRAM、BRAM、DSP、控制集、WNS/TNS、WHS/THS，以及 Vivado 版本、输入哈希和报告哈希。

| Profile | LUT | FF | LUTRAM | BRAM tile | DSP | WNS | WHS | TNS/THS |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `generic` | 1,455 | 954 | 320 | 0 | 0 | +1.393 ns | +0.262 ns | 0 / 0 |
| `vdma_scaler_lutram` | 1,210 | 760 | 320 | 0 | 0 | +1.446 ns | +0.269 ns | 0 / 0 |
| `vdma_scaler_bram` | 823 | 755 | 0 | 1 | 0 | +1.941 ns | +0.269 ns | 0 / 0 |
| `passthrough` | 349 | 509 | 0 | 0 | 0 | +4.193 ns | +0.262 ns | 0 / 0 |

在这个 Zynq-7000 OOC 配置中，BRAM 行缓冲比 LUTRAM 版本少 387 LUT、5 FF 和 320 LUTRAM，多用 1 个 BRAM tile。WNS 提高 0.495 ns，WHS 不变。两种实现都满足 100 MHz OOC setup/hold 门槛。目标消费工程应根据器件资源余量选择实现，并单独检查完整器件时序。

各 profile 的报告位于 `out/synth/xc7z020clg400-1`。`qor.json` 保存资源、时序以及输入和报告哈希。`out/manifest.json` 用于验证缓存产物是否仍匹配当前输入。

## 板级范围

库内的首个平台适配器面向 Zybo Z7-20 / Zynq-7000。板级 VTC、AXI VDMA、时钟、HDMI PHY、PS 应用和部署脚本由消费工程组合。库内保留通用接口、器件适配边界和可复用验证流程，不保存消费工程的应用数据、运行日志或 bitstream/XSA。

HLS AXI4-Stream 和 BRAM 帧读源目前有 RTL 仿真覆盖。其他器件系列的板级组合需要各自验证后，才能加入支持矩阵。
