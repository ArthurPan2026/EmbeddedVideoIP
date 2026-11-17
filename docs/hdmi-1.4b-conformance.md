# HDMI 1.4b 合规映射（EmbeddedVideoIP 0.3.0-dev.1）

本文以用户提供的 HDMI Specification 1.4b 为强制基线。规范 §1.2 要求遵守 HDMI 1.4b 所列的规范性引用；视频格式遵循 CEA-861-D，EDID/DDC 使用 EDID 1.3、E-EDID A.1 与 E-DDC v1，音频按适用的 IEC 60958/61937 要求。只有 §6.3 明确允许详细时序参考后续版本；本实现不以 HDMI 2.x/FRL 或较新 CTA 版本扩展范围。

## 固定声明能力

| 能力 | EmbeddedVideoIP 本次声明 |
|---|---|
| 输出时序 | CEA-861-D VIC 1，640×480p59.94/60，固定像素时钟 profile |
| 视频编码 | RGB 4:4:4、8 bpc（24 bit/pixel）、全范围 RGB |
| HDMI packet | AVI InfoFrame 和可选音频包；每个 HDMI Data Island 使用 packet BCH |
| 音频 | 可选双声道 LPCM，16-bit、48 kHz、Layout 0；无 HDMI audio 时仍发送 AVI InfoFrame |
| 接收端识别 | 消费端读取 EDID/CEA 扩展；只在校验通过且识别 HDMI VSDB 后请求 HDMI framing |
| 不声明 | YCbCr、Deep Color、3D、4K、HDCP、CEC 协议、ARC/eARC、其他视频时序 |

消费项目仍须按其实际软硬件能力填写 HDMI CDF。GBA 的 scaler 能输出 fit/stretch 画面，因此须按 HDMI CTS CDF 声明 AVI 信息可用并通过 Test 7-27。

## 规范要求到实现/验证

| 要求 | 规范依据 | 本实现 | 证据/限制 |
|---|---|---|---|
| 最低视频模式、像素格式与颜色范围 | HDMI 1.4b §§6.2.1、6.2.3–6.2.4、6.6；CEA-861-D | 固定 VIC 1、RGB 24 bpp、Full Range | RTL profile 与 AVI payload 仿真；电气/时序 tolerance 仍须 CTS 测量 |
| DVI 与 HDMI 传输区别 | HDMI 1.4b §§4.2、5.2；DVI 1.0 | 无 HDMI VSDB 或复位时输出 DVI 视频/控制符号，不插入 HDMI 前导、保护带或 Data Island；确认 HDMI 后才在HSync 边沿消隐期切换 | scheduler 与链路切换 RTL 测试；未做 DVI/HDMI 显示器兼容测试 |
| HDMI 视频信息 | HDMI 1.4b §8.2.1；CEA-861-D AVI InfoFrame；CTS 7-27 | 每场调度版本 2、13 字节 AVI InfoFrame：PB1=A valid/RGB/no bar flags；PB2=C=00（VGA 默认 sRGB）、M=4:3、R=8；PB3=Q full-range；PB4=VIC 1；PR=0；checksum 由固定 payload 计算，BCH 由统一 packet assembler 生成 | RTL 检查 header、payload、checksum 与 audio-off 发包；真实 CTS 7-27 未执行 |
| Data Island 最低频度与编码 | HDMI 1.4b §§5.2.1、5.2.3.2、5.3；CTS 7-17/7-19 | HDMI 模式每场调度 AVI island；VSYNC 每场重置发送标志，并在下一可用行槽发送 AVI；packet 由 BCH 编码 | scheduler/packet source/assembler RTL 测试；CTS 仪器测试未执行 |
| Extended Control Period | HDMI 1.4b §5.2.1.2；CTS 7-18 | 水平消隐在岛尾与视频前导/活动区之间保留控制字符；VIC 1 profile 连续控制段超过 32 字符 | scheduler RTL 检查 32 字符控制段；CTS 7-18 仪器测试未执行 |
| LPCM 与 IEC 60958 状态 | HDMI 1.4b §7.3、§7.6；IEC 60958；CTS 7-30/7-32 | 保留 2ch 16-bit/48 kHz Layout 0 路径与通道状态、奇偶校验 | 既有 PCM/packet RTL 测试；分析仪音频 CTS 未执行 |
| ACR 更新速率 | HDMI 1.4b §§7.2.3、7.8.2；CTS 7-29 | N=6144；按 128×Fs/N 做分数行累加，并从实际 ACR 包发送行计起；不再固定每 31 行 | RTL 仿真检查平均 line cadence；CTS 7-29 未执行 |
| EDID 与 sink 判别 | HDMI 1.4b §§8.1、8.3–8.5；E-EDID 1.3、E-DDC v1；CTS 7-1/7-33 | GBA PS 侧按 100 kHz 读取扩展块、校验 checksum/CEA v3/HDMI VSDB；失效时请求 DVI-safe | GBA host parser tests；板级 DDC/HPD 测试未执行 |
| CDC 与复位 | AMD 7-series CDC/时序设计规则 | link-mode、音频使能和静音分别同步到目标域；Q15 增益用稳定数据与请求/应答握手；Gray FIFO 指针加 ASYNC_REG、8 ns 最大延迟和 3 ns 位间偏斜约束；像素/串行状态复位同步释放 | RTL 回归与 OOC report_cdc：无 Critical 项；音频开启时有 1 条 CDC-6 握手提示和 128 条 CDC-15 FIFO 存储器提示；GBA 消费构建提供集成时序/CDC 证据，不代表 HDMI CTS/ATC 认证 |

## 变更边界

本版本不增加视频模式、像素格式、采样率或音频布局。新增 AVI 内容是固定现有 VGA 输出所需的协议元数据；DVI-safe framing 与 HDMI VSDB 判别使同一输出能按接收端类型遵守 1.4b 的传输边界。实现抽象保持静态、可综合：PS 负责 HPD/DDC/EDID，AXI-Lite 只传 link-mode 请求，TX 内部统一调度 HDMI packet 和行槽位。

本版本的自动仿真、主机测试、IP Catalog 检查和 OOC 综合均不等价于正式 HDMI 合规认证。HDMI 电气测量、CTS/ATC、显示器兼容性及消费工程 post-route 时序尚须另行完成。
