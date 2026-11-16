# 验证流程与验收记录

本文说明 EmbeddedVideoIP 0.2.0-dev.1 的自动验证范围和结果归档位置。自动检查通过只证明该检查覆盖的部分，不代表 HDMI 音频已经通过整板或消费工程验收。V1 音频尚未完成完整 HDMI 认证或正式板级音频验收。

## 自动验证

在 Vivado 2025.2.1 主机上运行：

~~~sh
python3 tools/video_flow.py doctor
python3 tools/video_flow.py sim
python3 tools/video_flow.py package
python3 tools/video_flow.py validate
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile composite_audio_off
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile composite_audio_on
~~~

sim 阶段运行 scaler、BRAM、视频控制、音频包和 PCM FIFO 的 HDL 仿真，以及 PS C API 和安装器主机回归。所有 XSim 工程放在 out/tests/。

package 阶段生成内部 video_pipeline 和唯一的 EmbeddedVideoIP 顶层 IP-XACT 包。validate 阶段从 IP Catalog 实例化该顶层，检查 AXI、PCM、BRAM、TMDS 端口和 HDMI 音频静态参数。

两个 composite synthesis profile 使用相同的视频配置。composite_audio_off 将 ENABLE_HDMI_AUDIO 设为 0；composite_audio_on 将 ENABLE_HDMI_AUDIO 设为 1。Flow 分别记录 LUT、FF、LUTRAM、BRAM、DSP、WNS、TNS、WHS 和 THS，报告与 OOC DCP 位于 out/synth/。这组时序数据属于预布线 OOC 综合，只用于比较两个静态 profile，不作为板级时序通过或失败结论。最终时序以消费工程的完整实现和 post-route STA 为准。

## 结果归档

out/manifest.json 保存每个阶段的工具版本、输入哈希、输出哈希、命令、日志路径和 QoR 数据。改变 RTL、第三方源文件、打包脚本、Vivado 版本或综合 profile 后，对应阶段会重新运行。

最终发布包位于 ip_repo/panfpga/embedded_video_ip/。该目录由 package 阶段生成，应作为发布内容纳入版本控制。out/ 只保存工作目录、日志和中间产物。

## 板级验收

Zybo Z7-20 上的验证应分别记录视频与音频状态。视频路径已有历史板测；本轮新增音频仍需正式板级验收。视频检查包括 640×480p60 稳定输出、源切换、缩放 profile、HDMI TMDS 时钟和 VDMA 错误。音频检查包括 HDMI 音频开关、静音、Q15 增益、PCM 背压、长时间欠载/溢出计数，以及与视频同步播放。

板级结果必须注明日期、板卡器件、Vivado 版本、IP 参数、消费工程版本和测量方法。没有记录的功能保持“未验证”，不能从 RTL 仿真或 IP Catalog 验证推断板级通过。
