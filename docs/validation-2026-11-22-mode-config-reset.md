# 2026-11-22 模式切换 scaler 复位

## 故障表现

GBA（Game Boy Advance）consumer 实板在 `720p60 → 1080p30` 时曾停在 VGA 回退，并报告固件错误 `13`。EVIP 状态寄存器保留 `WAIT_CONFIG` 失败阶段，`config_ready=0`。

配置确认依赖 scaler busy 清零。模式请求会暂停 AXI 输入，但 scaler 原先只在 `abort_stream` 时复位。若暂停时 scaler 仍在处理帧，它会保持 busy，配置确认无法完成。

## 代码修改

`ip/video_pipeline_1_0/hdl/video_pipeline_v1_0.sv` 现在在 `video_mode_pixel_reset_hold` 期间也拉低 `stream_resetn`。scaler 和输入帧状态会清空，恢复时从 `WAIT_SOF` 接收新帧。

本轮同时把既有失败阶段诊断从 packaged RTL 同步到 canonical RTL（Register-Transfer Level，寄存器传输级）。canonical、IP（Intellectual Property，知识产权核）package 和 GBA vendored RTL 的四个相关文件逐字节一致。EVIP `PACKAGE_METADATA.json` 通过生成器校验；GBA vendored package 与 release manifest 的文件哈希也已核验。

## Consumer 验证

GBA FPGAFlow hardware run `20261122T050637Z-27a9a27168` 通过。WNS（Worst Negative Slack，最差负裕量）为 `+0.057 ns`，TNS（Total Negative Slack，总负裕量）为 `0`；WHS（Worst Hold Slack，最差保持裕量）为 `+0.011 ns`，THS（Total Hold Slack，总保持裕量）为 `0`。DRC（Design Rule Check，设计规则检查）errors 和 critical warnings 均为 `0`。

GBA 实板的 `720p60 → 1080p30`、`1080p30 → 720p60` 和再次切回 `1080p30` 均成功。HDMI（High-Definition Multimedia Interface，高清多媒体接口）采集卡分别录到 1280×720、约 60 帧/秒和 1920×1080、约 30 帧/秒。稳定画面正常；模式切换采集中观测到约 1.1～1.27 s 黑帧，记录在 GBA consumer 的验证报告中。

该修改通过 Vivado 实现与时序门禁，并在 GBA consumer 实板完成双向切换验证。
