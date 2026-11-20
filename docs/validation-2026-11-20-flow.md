# 流程与仿真验证记录

## 验证范围

日期：2026 年 11 月 20 日。环境为 Ubuntu 22.04.5、Vivado 和 XSim 2025.2.1、Python 3.15.2。

RTL 测试使用 `tests/rtl_manifest.toml` 中的源文件和顶层。默认运行参数为 `--jobs 2`。测试日志保存在 `out/tests/`。

## 结果

| 检查 | 结果 | 范围 |
| --- | --- | --- |
| XSim RTL 回归 | 27 个 bench 通过 | 25 个重新运行，2 个复用同指纹结果。 |
| Host C | 通过 | `test_video_out`。 |
| Python 检查 | 32 项通过 | 契约、打包、输入分区和测试运行器。 |
| Icarus Verilog 11.0 | 6 个 bench 通过 | CI 中声明的可移植 RTL 子集。 |
| IP 包身份 | 通过 | 检查 canonical RTL、包内文件和 VSYNC 连接。 |

XSim 日志中的完整运行标记为 `VIDEO_TESTS_PASS`。本次运行器的 SHA-256 为 `2ca3a51d8bfa8946384565295fd9be3c5313c93909136930cf1690d5e2c6d798`。

重新打包时，检查发现生成的 `vtg_vsync` 曾被接到常量 0。打包脚本改用独立的 `vsync_raw` 观察引脚，生成的 `vtg_vsync` 已连接到时序发生器。包身份检查会拒绝常量连接。

本记录没有对修改后的 IP 包进行综合、布局布线、板卡运行或 HDMI 接收设备验收。之前的板卡结果属于对应的历史产物，不能替代本次修改后的板卡验证。
