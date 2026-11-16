# 2026-11-16 HDMI 音频信号路径预验证

## 目的和结论

本记录补充 EmbeddedVideoIP 0.2.0-dev.4 的消费工程板测状态。GBA 工程锁定 EVIP 提交 2008d713bf3ee37495bbc940634ad7b917a0ba78，在 Zybo Z7-20 / XC7Z020 上运行 MechPlatoon。

本轮确认 HDMI 视频和音频信号都能到达 C1-1 USB3 采集卡。音频采样电平会随 GBA 的音量设置变化。这是信号路径预验证；不代表已经确认扬声器听感，也不等于正式音频验收或 HDMI 标准认证。

## 测试配置

- Vivado/Vitis：2025.2.1。
- EmbeddedVideoIP：0.2.0-dev.4，提交 2008d713bf3ee37495bbc940634ad7b917a0ba78。
- GBA：MechPlatoon，ROM code AKGE，8,388,608 bytes。
- HDMI 视频：640×480、60 fps。
- HDMI 音频：48 kHz、16-bit、双声道；未静音；测试音量为 45 和 70。

GBA 复用现有 I²S 发送器的 48 kHz 样本节拍，将相同的 PCM 样本通过 AXI4-Stream 接入 EmbeddedVideoIP。I²S codec 和输出切换仍由 GBA 消费工程实现；EmbeddedVideoIP 不包含 I²S 路径。

## 视频与复位状态

首次部署时显示器报告无信号。UART 诊断显示 MMCM、像素时钟和串行时钟都在运行，但像素复位仍有效，VSYNC 没有变化。原因是组合 IP 内的 proc_sys_reset 将 aux_reset_in 接常量 0，却把 C_AUX_RESET_HIGH 配为 0；这使常量低电平一直请求复位。

打包脚本现将辅助和外部复位极性配置为高有效。修复后，hdmi diag 读回 pixel_reset_released=1、serial_seen=1、vsync_seen=1、mmcm_locked=1、pixel_clk_seen=1、pixel_ext_reset=0。该参数语义见 AMD [PG164 Processor System Reset Module](https://docs.amd.com/r/en-US/pg164-proc-sys-reset)。

C1-1 USB3 Video 以 640×480、60 fps 采集 3 秒，共收到 180 帧；画面显示 MechPlatoon。采集卡已经识别连续 HDMI 视频时序。显示器扬声器没有做单独听音测试。

## 音频采集结果

UART 音频状态显示：采样率 48 kHz、位宽 16 bit、静音关闭、输出路径 HDMI、路由状态 idle、错误 0、PCM overflow 0。EVIP AUDIO_CTRL=0x1，AUDIO_STATUS=0x1；AUDIO_STATUS bit 0 表示 HDMI 音频使能，bit 1 欠载状态为 0。

C1-1 USB3 Audio 的采样电平如下：

| GBA 音量 | 采样时长 | 平均电平 | 峰值电平 |
| ---: | ---: | ---: | ---: |
| 45 | 6 s | -62.3 dBFS | -50.9 dBFS |
| 70 | 6 s | -46.1 dBFS | -35.5 dBFS |

提高音量后采集电平上升，说明 HDMI 音频数据到达采集卡。测试后音量恢复为 45。音量 45 的采集电平较低，需要继续确认显示器或扬声器的实际听感。

采集文件留在板测工作站的 E:/Ubuntu-FPGA/out/capture/，没有复制游戏画面或音轨到 EmbeddedVideoIP 仓库。

## 已覆盖和待完成项

已覆盖 EVIP 启用 HDMI 音频后的消费工程信号路径、48 kHz PCM 到达采集卡、音量变化响应、HDMI 使能与欠载状态读取，以及视频像素复位恢复。

正式板级验收仍需在扬声器上确认听感，检查静音和更完整的增益范围，验证长时间欠载状态与音视频同步。EmbeddedVideoIP 尚未完成 HDMI 认证。GBA 的 I²S/HDMI 用户切换是消费工程功能，不纳入 EVIP 库级验收。