# PL+PS 快速上手

## 配置概览

消费者在 Vivado IP Integrator 中添加 `panfpga.org:video:embedded_video_ip:1.0`。板级 profile 为 Zybo Z7-20、XC7Z020、Zynq-7000、Vivado/Vitis 2025.2.1。

PL 输出 VIC 1、VIC 4 或 VIC 34。GBA PS 默认构建 LVGL 原生 1280×720 输入。消费端读取 EDID 后请求 720p60；sink 支持 VIC 34 时也可选择 1080p30。

## 打包和验证

    python3 tools/video_flow.py doctor
    python3 tools/video_flow.py sim
    python3 tools/video_flow.py package
    python3 tools/video_flow.py validate
    python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile composite_audio_on

`sim` 运行 SystemVerilog RTL bench、PS C API host tests 和 Python 流程测试。`package` 生成内部视频处理核和组合式 IP。`validate` 检查 Vivado IP Catalog 中的端口、AXI-Lite 地址段和参数。

## 消费工程连接

在 Vivado 中将项目的 `ip_repo/` 加入 IP Repository，刷新 Catalog 后添加 EmbeddedVideoIP 顶层。

- `s_axi` 接 PS AXI master。
- `aclk` 接 100 MHz AXI/视频控制时钟。
- `aresetn` 接低有效系统复位。
- `hdmi_ref_clk` 接 Zybo Z7-20 的 50 MHz 参考时钟。
- `s_axis_vdma` 接 AMD AXI VDMA MM2S 输出。
- `s_axis_audio_pcm` 接 48-bit LPCM AXI4-Stream。
- `tmds_tx` 接板级 HDMI 差分引脚，并由消费工程 XDC 约束。

PS 通过 GPIO/IIC 管理 HPD 和 DDC。EDID 能力写入 HDMI link profile 和输出模式请求。HDMI音频使能和静音由 AXI-Lite 控制。

## GBA 原生 720p 输入

`PS_APP_NATIVE_720P_INPUT` 默认为 ON。该 profile 设置 LVGL display 为 1280×720、XRGB8888 和 5120 B 行 stride。VDMA 使用三个 4 MiB frame slot，基址为 0x18000000。linker 为 framebuffer 保留 0x18000000～0x18C00000。

要切换为 640×480 输入，在 CMake 配置中设置 `PS_APP_NATIVE_720P_INPUT=OFF`。PL 根据 EDID 选择输出时序，并由 scaler 计算 fit geometry。

## PCM 音频格式

每个 AXI4-Stream beat 携带一对有符号 24-bit LPCM 样本。左声道位于 TDATA[23:0]，右声道位于 TDATA[47:24]。默认采样率为 48 kHz。音源在 TREADY 为低时保持 TVALID 和 TDATA。
