# AMD 7-series 板级适配

当前板级验证目标为 Zybo Z7-20（XC7Z020）。EmbeddedVideoIP 使用 PS FCLK1 100 MHz 作为 AXI 和视频控制时钟，使用 PS FCLK0 50 MHz 作为 HDMI 时钟参考。

PL 支持三种输出时序：VIC 1 640×480p60、VIC 4 720p60 和 VIC 34 1080p30。VGA profile 的实际像素时钟为 25.178571 MHz，TMDS 串行时钟为 125.892857 MHz。两个 HD profile 共用 74.218750 MHz 像素时钟和 371.093750 MHz TMDS 串行时钟。HD 实际像素时钟比 CTA 标称 74.25 MHz 低约 421 ppm。TMDS 串行时钟与像素时钟保持 5:1。

Composite 内部包含 AXI4-Stream 视频输出桥、SystemVerilog 时序发生器、双 profile Clock Wizard、BUFGCTRL 时钟选择器和 7-series HDMI 发送器。消费工程连接 PS、DDR、AXI VDMA、参考时钟和复位。EmbeddedVideoIP 输出 TMDS；HPD/DDC 由消费工程接到 PS GPIO/IIC。

HDMI TX 的 TMDS 编码和 OSERDESE2/OBUFDS 串行输出由本项目维护。音频静态关闭时会裁掉 PCM FIFO 和音频 packetizer。音频开启时使用 24-bit LPCM、ACR 和音频 InfoFrame。当前 XSim 覆盖这些 RTL 功能；显示器兼容性和 HDMI 合规认证仍需目标板与测试仪器验证。

其他器件系列需要各自匹配的 HDMI PHY、时钟和约束。完成综合、实现、时序和实板验证后，才能加入支持范围。
