# EmbeddedVideoIP AXI-Lite 寄存器表

所有寄存器为 32-bit、按字节寻址、小端。AXI-Lite AW 与 W 通道独立握手，寄存器接口支持 byte strobe。唯一外部 `S_AXI` 控制口的地址窗口至少为 `0x40` 字节。

`CTRL` bit 8 是视频配置提交脉冲，bit 9 请求读取一帧 BRAM，bit 10 清除视频/音频 sticky 错误，bit 11 暂停输入并中止当前部分帧，bit 12 在异常恢复路径中释放输入，bit 13 请求 HDMI packet framing（复位默认 0 为 DVI-safe）。

| 偏移 | 名称 | 访问 | 字段 |
|---|---|---|---|
| `0x00` | `CTRL` | RW/W1P | bit 0 视频使能；bits `[2:1]` 视频源（0=BRAM、1=HLS、2=VDMA）；bit 3 最近邻 scaler 使能；bit 4 stretch；bits `[6:5]` 像素格式；bit 8 commit；bit 9 BRAM frame start；bit 10 clear errors；bit 11 abort/hold stream；bit 12 resume stream；bit 13 link mode（0=DVI，1=HDMI；由消费端 HPD/EDID 管理器在确认 HDMI VSDB 后设置） |
| `0x04` | `INPUT_SIZE` | RW | bits `[15:0]` width，`[31:16]` height |
| `0x08` | `STRIDE_BYTES` | RW | 源图像相邻行首地址的字节间距 |
| `0x0C` | `BRAM_BASE_WORD` | RW | BRAM reader 起始地址，单位为 32-bit word |
| `0x10` | `STATUS` | RO | bits [13:8] HDMI运行态遥测：bit 13 像素复位外部复位仍有效；bit 12 像素时钟已检测到运行；bit 11 MMCM 已锁定；bit 10 VSYNC 已发生变化；bit 9 串行时钟已检测到运行；bit 8 像素复位已释放；bits `[7:6]` 活动视频源；bit 5 BRAM busy；bit 4 pipeline busy；bit 2 配置待提交；bit 1 stream held；bit 0 video enabled |
| `0x14` | `FRAME_COUNT` | RO | 已完成输出帧数 |
| `0x18` | `ERROR_FLAGS` | RO | 视频 scaler/profile/BRAM sticky error 标志；`CTRL` bit 10 清除 |
| `0x1C` | `ACTIVE_SIZE_CFG` | RW | bits `[9:0]` active width，`[25:16]` active height |
| `0x20` | `OFFSETS` | RW | bits `[9:0]` x offset，`[25:16]` y offset |
| `0x24` | `SOURCE_ORIGIN` | RW | bits `[9:0]` source x，`[25:16]` source y |
| `0x28` | `X_RATIO` | RW | bits `[9:0]` source step，`[25:16]` remainder |
| `0x2C` | `Y_RATIO` | RW | bits `[9:0]` source step，`[25:16]` remainder |
| `0x30` | `ACTIVE_SIZE` | RO | 当前活动画面的 width/height |
| `0x34` | `AUDIO_CTRL` | RW | bit 0 `HDMI_AUDIO_ENABLED`；bit 1 `AUDIO_MUTE`；其他位保留为 0 |
| `0x38` | `AUDIO_GAIN_Q15` | RW | bits `[16:0]` Q15 增益，`0..32768`，其中 32768 为 unity gain；大于 32768 的值饱和到 32768 |
| `0x3C` | `AUDIO_STATUS` | RO | bit 0：`HDMI_AUDIO_ENABLED` 配置状态；bit 1：音频欠载 sticky 状态；bit 2：保留，V1 恒为 0；其他位为 0 |

`AUDIO_CTRL.bit0` 在 `ENABLE_HDMI_AUDIO=0` 的静态 profile 中会被强制为 0。`AUDIO_CTRL.bit1` 可在运行时静音 HDMI 音频；`AUDIO_GAIN_Q15` 调整 PCM 输出幅度。`CTRL.bit10` 清除音频欠载状态。V1 通过 AXI4-Stream 背压处理 FIFO 满状态，不产生溢出事件；因此 AUDIO_STATUS bit 2 保留并恒为 0。配套 C 结构体中的 fifo_overflow 字段保留，当前也返回 0。

## PCM AXI4-Stream 格式

Composite 顶层提供 `audio_pcm_clk` 和一组 AXI4-Stream PCM 输入。`TDATA[15:0]` 为有符号 16-bit 左声道，`TDATA[31:16]` 为有符号 16-bit 右声道。每次 `TVALID && TREADY` 表示一个立体声样本对；源端由消费工程的音频适配器按 48 kHz 提供样本，并在背压期间保持数据和 `TVALID` 稳定。

## 视频参数计算

PS C 库根据输入尺寸、scale 模式和 aspect policy 计算 `ACTIVE_SIZE_CFG`、`OFFSETS`、`SOURCE_ORIGIN`、`X_RATIO` 和 `Y_RATIO`，再通过 `CTRL.commit` 提交。RTL 不包含运行时可变除法器。固定输出 VTC timing 和像素时钟由 Vivado composite BD profile 配置。
