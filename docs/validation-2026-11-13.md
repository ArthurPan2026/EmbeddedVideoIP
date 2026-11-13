# V1 验证记录

日期：2026-11-13。

## 交付范围

V1 是配套的 PL IP 与 PS C 库，PL-only 不属于支持配置。当前唯一完成实板验证的组合是 Zybo Z7-20、XC7Z020、Zynq-7000、Vivado/Vitis 2025.2.1。PS 适配器为 Xilinx standalone/FreeRTOS VDMA 与 MMIO 实现。

本轮板测走 VDMA MM2S 输入。HLS AXI4-Stream 和 BRAM RGB565 路径通过 RTL 仿真，尚未在板上做源切换验收。其他 Vivado 器件尚未有配套 PS 适配器和板级输出配置，不标记为开箱即用。

## 库级验证

- `tb_axis_video_nn_scaler`、`tb_video_bram_rgb565_reader`、`tb_video_pipeline_v1_0` 通过。顶层仿真覆盖 VDMA、HLS、BRAM 三种源。
- `test_video_out` 通过。测试确认驱动先等待当前帧结束，之后才改视频寄存器和 VDMA 几何。
- PS 安装器的 4 个单元测试通过，覆盖重复安装、文件冲突、完整手工配置和部分配置冲突。
- Vivado 2025.2.1 将 IP 打包为 `panfpga.org:video:video_pipeline:1.0`。IP Catalog 验证通过。临时验证 BD 没有 PS AXI master，因此将无主机的 AXI-Lite 地址段排除；Zybo 消费工程接入 PS master 并分配真实地址。
- 独立 Vivado 工程注册脚本通过临时工程测试，Vivado 能在 IP Catalog 中找到该 VLNV。
- Zynq-7020 OOC 综合通过：LUT 6,551（12.31%）、FF 16,377（15.39%）、BRAM 0、DSP 0；WNS +1.654 ns、TNS 0。

## GBA 消费工程实现

使用 `out/video-ip-candidate` 单独输出目录构建，保留原有 `out/vivado`。完整实现生成 bitstream 与 XSA。最终 post-route WNS 为 +0.026 ns，TNS 为 0，DRC 0 error。资源为 LUT 36,148（67.95%）、FF 48,627（45.70%）、BRAM 131.5 / 140（93.93%）、DSP 12 / 220（5.45%）。

实现报告有 ULMTCS-2 控制集警告，placed report 为 2,888 个控制集。DRC 有 9 条 REQP-1839，涉及 HDMI VDMA XPM FIFO RAMB36 异步控制；其余 DPIP/DPOP 等警告仍在 routed report 中。HDMI TMDS 输出在现有 XDC 中有 false-path 约束，因此该结果不等于外部 HDMI IO 时序已完整签核。

改动时发现一次 UART 加载的黑屏竞态。UI 过早进入 GAME 后停止 LVGL 刷新，视频层仍保留菜单模式。随后修正为加载画面保持到首个完整游戏帧停放后再切换。另一个切换失败由 PS 驱动先关闭活动 AXI-Stream 源再等待 busy 造成，scaler 会停在半帧并一直 busy。驱动现在保持旧源运行到帧边界，再重配 VDMA。最后，MM2S 重启后显式停放首个游戏帧，确认 PARKPTR 为 frame 2。

## 实板运行

通过 XSCT 对开发板执行系统复位、bitstream 编程、PS 初始化和 ELF 下载。`APP_RUNNING` 后 PC 持续有效。ROM 通过 UART 直接路径加载。

- MechPlatoon：`0:/games/MechPlatoon.gba`，8,388,608 bytes，title `MECH PLATOON`，code `AKGE`。模式切换日志显示输入 240×160、stride 960，初始 park frame 2，VDMA 错误 0。
- Skyland：`0:/games/Skyland.gba`，24,693,968 bytes，title `SKYLAND.....`，code `SKLD`。ROM 切换后能进入 Skyland 场景。UART 状态显示 VDMA 错误 0。
- `fps 5 100`：capture 59.40 FPS、blit 59.20 FPS、blit/capture 99.7%、CyclesMissing 增量 0。
- 画面只从 OBS Virtual Camera 观察。Skyland 稳定片段连续采样 12 秒，能看到游戏场景和帧变化，没有持续全黑。

实板验证只覆盖了 VDMA 输入。HLS/BRAM 板测、其他器件适配和长时间运行仍待后续验证。

## 颜色状态

PS UI 源码主题设为米白与绿色，但 OBS 截图呈粉紫色。按当前指示，本轮没有改 Digilent `rgb2dvi` 通道顺序，也没有再次实现 PL。这个颜色问题尚未确认根因，后续应先用已知红、绿、蓝色条比较 PS framebuffer 字值、视频核输出和 OBS capture，再决定是否需要更换通道顺序或修正采集颜色矩阵。
