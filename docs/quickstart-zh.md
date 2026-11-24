# PL+PS 快速上手

## 配置概览

在 Vivado IP Integrator 中添加 `panfpga.org:video:embedded_video_ip:1.0`。消费系统配置平台 profile、帧缓冲和应用。

PL 输出 VIC 1、4、34 或 16。外部控制软件读取 EDID 后请求目标模式，并提交输入尺寸、stride 和缩放几何。

## 打包和验证

```sh
python3 tools/video_flow.py doctor
python3 tools/video_flow.py sim
python3 tools/video_flow.py package
python3 tools/video_flow.py validate
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile composite_audio_on
```

## 集成接口

将项目的 `ip_repo/` 加入 Vivado IP Repository，刷新 Catalog 后添加 EmbeddedVideoIP 顶层：

- `s_axi` 接控制系统 AXI master。
- `aclk` 接 AXI/视频控制时钟。
- `aresetn` 接低有效系统复位。
- `hdmi_ref_clk` 接平台参考时钟。
- `s_axis_vdma` 接 AXI VDMA MM2S 输出。
- `s_axis_audio_pcm` 接 48-bit LPCM AXI4-Stream。
- `tmds_tx` 接平台 HDMI 差分引脚并由平台约束文件约束。

外部系统通过 HPD/DDC 读取 sink 能力，再提交 HDMI link profile、输出模式、音频使能和静音配置。

## PCM 音频格式

每个 AXI4-Stream beat 携带一对有符号 24-bit LPCM 样本。左声道位于 `TDATA[23:0]`，右声道位于 `TDATA[47:24]`。默认采样率为 48 kHz。源端在 `TREADY` 为低时保持 `TVALID` 和 `TDATA`。
