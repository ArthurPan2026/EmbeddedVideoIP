# AMD 7-series 板级适配

V1 板级验证 profile 为 Zybo Z7-20（XC7Z020）。组合式 EmbeddedVideoIP 使用 PS FCLK1 100 MHz 作为 AXI/视频控制时钟，使用 PS FCLK0 50 MHz 作为 HDMI 时钟参考；当前 MMCM 配置输出约 25.178571 MHz 像素时钟和 125.892857 MHz TMDS 串行时钟。

Composite 内部包含 AXI4-Stream 视频输出桥、VTC 和 7-series HDMI 发送器。消费工程连接 PS/DDR、AXI VDMA 和时钟/复位。EmbeddedVideoIP 只输出 TMDS；HPD/DDC 由消费工程接到 PS GPIO/IIC。外部 VDMA 的 MM2S AXI4-Stream 接入 `s_axis_vdma`。

HDMI TX 复用 Digilent `TMDS_Encoder`、`OutputSERDES` 和 `DVI_Constants` 7-series 源码，并由 EmbeddedVideoIP 自有逻辑生成音频数据岛与 InfoFrame。`ENABLE_HDMI_AUDIO=0` 时静态裁剪音频逻辑。新增 HDMI 音频当前只通过 RTL/XSim 覆盖，尚未完成 HDMI 认证或正式板级音频验收。其他器件系列需配置匹配的 HDMI PHY、时钟并完成实板验证后再列入支持范围。
