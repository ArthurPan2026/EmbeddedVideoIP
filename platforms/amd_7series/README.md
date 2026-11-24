# AMD 7-series 板级适配

当前板级验证目标为 Zybo Z7-20（XC7Z020）。EmbeddedVideoIP 使用 PS FCLK1 100 MHz 作为 AXI 和视频控制时钟，使用 PS FCLK0 50 MHz 作为 HDMI 时钟参考。

PL 支持 VIC 1 480p60、VIC 4 720p60、VIC 34 1080p30 和 VIC 16 1080p60。VGA profile 像素时钟约为 25.178571 MHz。四模式 HD 参考生成 74.25 MHz 或 148.5 MHz 像素时钟，串行时钟保持 5:1。1080p60 对应 742.5 MHz，在 XC7Z020-1 上按超频配置记录。

Composite 内部包含 AXI4-Stream 视频输出桥、时序发生器、VGA/HD 参考和 serializer MMCM。MMCM 经 BUFIO/BUFR 驱动 OSERDESE2，BUFG 驱动像素逻辑。消费工程连接 PS、DDR、AXI VDMA、参考时钟和复位，HPD/DDC 接 PS GPIO/IIC。

HDMI TX 使用 TMDS 编码和 OSERDESE2/OBUFDS。音频静态关闭时裁剪 PCM FIFO 与 packetizer，开启时使用 24-bit LPCM、ACR 和 Audio InfoFrame。XSim 检查协议逻辑，GBA 消费工程记录最终时序、显示和音频采集结果。

其他器件的适配内容包括 PHY、时钟、约束、综合实现与板级验证。
