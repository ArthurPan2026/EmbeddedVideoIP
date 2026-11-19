# EmbeddedVideoIP AXI-Lite 寄存器表

寄存器宽度为 32 bit，地址按字节计，小端。AXI-Lite 的 AW 和 W 通道独立握手。接口支持 byte strobe，地址窗口至少为 0x40 字节。

## 控制与状态

CTRL bit 8 提交视频几何。bit 9 启动一帧 BRAM 读取。bit 10 清除 sticky 错误。bit 11 暂停输入并丢弃当前不完整帧。bit 12 恢复输入。bit 13 选择 DVI 或 HDMI framing。复位时进入 DVI-safe 状态。

模式请求放在 CTRL[15:14]。模式 0 对应 VIC 1（640×480p60），模式 1 对应 VIC 4（720p60），模式 2 对应 VIC 34（1080p30）；模式 3 保留。只有同一次 CTRL 写入同时置 bit 8 和 bit 16，才会提交新模式和 scaler 几何。bit 16 是一次性 mode-commit 脉冲，不会读回为 1。

| 偏移 | 名称 | 访问 | 字段 |
|---|---|---|---|
| 0x00 | CTRL | RW/W1P | bit 0 视频使能；bits [2:1] 视频源（0=BRAM、1=HLS、2=VDMA）；bit 3 最近邻 scaler；bit 4 stretch；bits [6:5] 像素格式；bit 8 几何提交；bit 9 BRAM frame start；bit 10 清错；bit 11 暂停/中止；bit 12 恢复；bit 13 link mode（0=DVI、1=HDMI）；bits [15:14] 输出模式；bit 16 mode commit 脉冲 |
| 0x04 | INPUT_SIZE | RW | bits [15:0] 输入宽度；bits [31:16] 输入高度 |
| 0x08 | STRIDE_BYTES | RW | 源帧相邻行首地址的字节间距 |
| 0x0C | BRAM_BASE_WORD | RW | BRAM 读取器起始地址，单位为 32-bit word |
| 0x10 | STATUS | RO | bit 31 模式错误；bit 30 模式切换忙；bits [29:28] 活动模式；bits [13:8] HDMI 运行状态遥测；bits [7:6] 活动视频源；bit 5 BRAM busy；bit 4 pipeline busy；bit 2 配置待提交；bit 1 stream held；bit 0 视频使能 |
| 0x14 | FRAME_COUNT | RO | 已完成输出帧数 |
| 0x18 | ERROR_FLAGS | RO | scaler、输入 profile 和 BRAM 的 sticky 错误；CTRL bit 10 清除 |
| 0x1C | ACTIVE_SIZE_CFG | RW | bits [10:0] 活动画面宽度；bits [26:16] 活动画面高度 |
| 0x20 | OFFSETS | RW | bits [10:0] x offset；bits [26:16] y offset |
| 0x24 | SOURCE_ORIGIN | RW | bits [10:0] source x；bits [26:16] source y |
| 0x28 | X_RATIO | RW | bits [10:0] source step；bits [26:16] DDA remainder |
| 0x2C | Y_RATIO | RW | bits [10:0] source step；bits [26:16] DDA remainder |
| 0x30 | ACTIVE_SIZE | RO | 活动画面宽度和高度，均为 11 bit |
| 0x34 | AUDIO_CTRL | RW | bit 0 HDMI 音频使能；bit 1 静音；其他位保留 |
| 0x38 | AUDIO_GAIN_Q15 | RW | bits [16:0] Q15 增益，0～32768；32768 为 unity gain |
| 0x3C | AUDIO_STATUS | RO | bit 0 HDMI 音频使能状态；bit 1 欠载 sticky；bit 2 保留；其他位为 0 |

状态寄存器的 HDMI 遥测位定义如下：

| 位 | 状态 |
|---|---|
| bit 13 | 像素复位的外部复位输入有效 |
| bit 12 | 像素时钟已检测到运行 |
| bit 11 | 所选时钟 profile 已锁定 |
| bit 10 | VSYNC 已发生变化 |
| bit 9 | TMDS 串行时钟已检测到运行 |
| bit 8 | 像素复位已释放 |

EDID 读取和输出模式选择由消费端 PS 软件完成。消费端按 sink 能力请求 VIC 1、4 或 34。PL 在旧帧边界等待，再切换像素时钟、时序和 scaler 几何。时钟未锁定、几何无效或新时序未出现 VSYNC 时，控制器保持 reset hold 和 DVI-safe framing。

## PCM AXI4-Stream 格式

Composite 顶层提供 `audio_pcm_clk` 和 48-bit AXI4-Stream PCM 输入。`TDATA[23:0]` 是有符号 24-bit 左声道，`TDATA[47:24]` 是有符号 24-bit 右声道。每个 `TVALID && TREADY` 握手表示一对立体声样本。源端在背压期间必须保持 `TDATA` 和 `TVALID` 稳定。默认采样率为 48 kHz。

GBA 的内部音源是 16-bit PCM。消费端把每个声道符号扩展到 24 bit，I²S codec 路径保持原样。HDMI 发射端按 HDMI 1.4b LPCM 子帧传送 24-bit 样本，并用实际像素时钟计算 ACR CTS。

## 输出模式和 scaler 几何

PL 提供三种逐行模式。VIC 4 和 VIC 34 共用 HD clock profile，但使用不同的 H/V totals、同步位置和 AVI VIC 字段。

| 模式码 | CTA VIC | 活动区 | 标称像素时钟 | 实现像素时钟 |
|---|---:|---:|---:|---:|
| 0 | 1 | 640×480 | 25.175 MHz | 25.178571 MHz |
| 1 | 4 | 1280×720 | 74.250 MHz | 74.218750 MHz |
| 2 | 34 | 1920×1080 | 74.250 MHz | 74.218750 MHz |

HD profile 的像素时钟实际值比 CTA 标称值低约 421 ppm。音频 ACR 计算使用实际频率。显示器兼容性仍需在目标板上验证。

Scaler 几何中的 OFFSET 表示输出画布位置。SOURCE_ORIGIN 表示输入裁剪起点。X_RATIO 和 Y_RATIO 使用 11-bit step/remainder，支持 1280×720 输入缩放到 1920×1080。软件在 aclk 域先写入所有几何字段，再用 CTRL bit 8 提交。切换输出模式时，消费端在同一 CTRL 写入中同时置 bit 8 和 bit 16，保证模式与几何作为一个事务进入 PL。
