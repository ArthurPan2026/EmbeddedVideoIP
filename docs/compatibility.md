# 兼容性与支持矩阵

## 产品配置

V1 是配套 PL+PS 的 EmbeddedVideoIP composite IP。Vivado IP Integrator 中的消费者入口是 `panfpga.org:video:embedded_video_ip:1.0`。PL-only 用法不属于当前支持配置。

## 当前验证范围

| 层级 | 当前支持声明 | 验证边界 |
|---|---|---|
| 组合式 EmbeddedVideoIP | Vivado 2025.2.1 | IP Catalog 和组合 BD 验证 |
| 视频处理 RTL | 采用标准 AXI4-Stream Video、未直接例化 AMD 器件原语 | XSim 与 XC7Z020 OOC profile |
| VDMA 视频源 | AMD AXI VDMA MM2S AXI4-Stream | Zybo Z7-20 消费系统板测 |
| HLS 视频源 | AXI4-Stream Video | RTL 仿真，尚未在板上逐源验证 |
| BRAM RGB565 源 | 同步 BRAM 读接口 | RTL 仿真，尚未在板上逐源验证 |
| HDMI 发送适配器 | 7-series / Zybo Z7-20 / XC7Z020 | 目标板约束与系统验证 |
| HDMI 音频 | 固定 2 声道 16-bit/48 kHz LPCM、ACR、Audio InfoFrame 与数据岛子集 | RTL/XSim覆盖；未完成完整 HDMI 认证或正式板级音频验收 |
| 其他器件系列 | 暂无开箱即用声明 | 需另做 PHY、时钟、I/O、综合、时序和板测验证 |

## 器件适配说明

通用视频处理 RTL 与具体 HDMI PHY 分开。Zybo Z7-20 使用 7-series TMDS/OSERDES 后端；该后端不能直接移植到 UltraScale、Versal 等系列。Digilent rgb2dvi 只发送 DVI 兼容视频，不能只增加 PCM 端口就发送 HDMI 音频。EmbeddedVideoIP 自行实现音频包、ACR 和数据岛调度，并复用锁定版本的 Digilent 编码器与串行输出源码。

当前 Vivado 2025.2.1 Catalog 中，AMD HDMI TX Subsystem 将 XC7Z020 标为不支持，并要求购买该 IP 的完整功能许可。当前 Zybo profile 因此使用自定义的 7-series HDMI audio TX adapter；该选择不会把 PHY 逻辑放进通用 scaler/source core。

AMD AXI VDMA 的确切可用性按安装版本和器件 IP Catalog 检查。产品包装时会验证所需 IP，不能仅凭器件系列名称推断某块板已经开箱即用。

## 加入新器件的准入条件

新增一个受支持器件/板卡前，至少完成：

1. Vivado IP Catalog 中确认 VDMA、视频输出、VTC、时钟和 HDMI 后端均可用。
2. 参数化组合 IP 的打包、BD 检查和目标器件综合。
3. 板级时钟/IO/复位与 TMDS 约束检查。
4. Post-route setup/hold、DRC 和利用率检查。
5. HDMI 视频、音频输出和路由切换实板验收。

只要其中一项未覆盖，支持矩阵就应标为“未验证”，不能用 RTL 可移植性代替板级支持声明。
