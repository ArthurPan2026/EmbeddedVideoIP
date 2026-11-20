# EmbeddedVideoIP AXI-Lite 寄存器表

寄存器宽度为 32 bit，地址按字节计，小端。AXI-Lite 的 AW 和 W 通道独立握手。接口支持 byte strobe，地址窗口至少为 0x40 字节。

## 控制与状态

CTRL bit 8 提交视频几何。bit 9 启动一帧 BRAM 读取。bit 10 清除 sticky 错误。bit 11 暂停输入并丢弃当前不完整帧。bit 12 恢复输入。bit 13 选择 DVI 或 HDMI framing。复位时进入 DVI-safe 状态。

模式请求放在 CTRL[15:14]。模式 0 对应 VIC 1，模式 1 对应 VIC 4，模式 2 对应 VIC 34；模式 3 保留。只有同一次 CTRL 写入同时置 bit 8 和 bit 16，才会提交新模式和 scaler 几何。

| 偏移 | 名称 | 访问 | 字段 |
|---|---|---|---|
| 0x00 | CTRL | RW/W1P | bit 0 视频使能；bits [2:1] 视频源；bit 3 最近邻 scaler；bit 4 stretch；bits [6:5] 像素格式；bit 8 几何提交；bit 9 BRAM frame start；bit 10 清错；bit 11 暂停/中止；bit 12 恢复；bit 13 link mode；bits [15:14] 输出模式；bit 16 mode commit 脉冲 |
| 0x04 | INPUT_SIZE | RW | bits [15:0] 输入宽度；bits [31:16] 输入高度 |
| 0x08 | STRIDE_BYTES | RW | 源帧相邻行首地址的字节间距 |
| 0x0C | BRAM_BASE_WORD | RW | BRAM 读取器起始地址，单位为 32-bit word |
| 0x10 | STATUS | RO | 模式错误、切换忙、活动模式、HDMI 遥测、活动视频源、BRAM/pipeline busy、配置待提交、stream held 和视频使能 |
| 0x14 | FRAME_COUNT | RO | 已完成输出帧数 |
| 0x18 | ERROR_FLAGS | RO | scaler、输入 profile 和 BRAM 的 sticky 错误 |
| 0x1C | ACTIVE_SIZE_CFG | RW | 活动画面宽度和高度 |
| 0x20 | OFFSETS | RW | 输出画布 x/y offset |
| 0x24 | SOURCE_ORIGIN | RW | 输入裁剪起点 |
| 0x28 | X_RATIO | RW | source step 和 DDA remainder |
| 0x2C | Y_RATIO | RW | source step 和 DDA remainder |
| 0x30 | ACTIVE_SIZE | RO | 活动画面宽度和高度 |
| 0x34 | AUDIO_CTRL | RW | bit 0 HDMI 音频使能；bit 1 静音 |
| 0x38 | AUDIO_GAIN_Q15 | RW | Q15 增益，0～32768；32768 为 unity gain |
| 0x3C | AUDIO_STATUS | RO | 音频使能状态和欠载 sticky |

EDID 读取和输出模式选择由外部控制软件完成。PL 在旧帧边界等待，再切换像素时钟、时序和 scaler 几何。时钟未锁定、几何无效或新时序未出现 VSYNC 时，控制器保持 reset hold 和 DVI-safe framing。

## PCM AXI4-Stream 格式

Composite 顶层提供 `audio_pcm_clk` 和 48-bit AXI4-Stream PCM 输入。`TDATA[23:0]` 是有符号 24-bit 左声道，`TDATA[47:24]` 是有符号 24-bit 右声道。每个 `TVALID && TREADY` 握手表示一对立体声样本。源端在背压期间保持 `TDATA` 和 `TVALID` 稳定。默认采样率为 48 kHz。
