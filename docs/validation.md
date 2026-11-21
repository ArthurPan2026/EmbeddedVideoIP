# 验证流程与验收记录

本文只记录 EmbeddedVideoIP 库级验证。外部系统的应用配置、部署产物、运行日志和扬声器听感由外部仓库单独记录。

## 自动验证

```sh
python3 tools/video_flow.py doctor
python3 tools/video_flow.py sim
python3 tools/video_flow.py package
python3 tools/video_flow.py validate
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile composite_audio_off
python3 tools/video_flow.py synth --part xc7z020clg400-1 --profile composite_audio_on
```

`sim` 运行 scaler、BRAM、视频控制、音频 packet、PCM FIFO、Host C API 和安装器测试。`package` 生成内部 video_pipeline 和组合式 IP-XACT 包。`validate` 在 Vivado IP Catalog 中实例化顶层，检查 AXI、PCM、BRAM、TMDS 端口和静态音频参数。`synth` 运行库级 OOC 综合。

OOC 时序只用于 profile 比较，不替代外部系统的完整器件 post-route STA。通过 FPGAFlow 运行时，输入锁与索引保存在仓库外的状态目录；完整输入、输出哈希和报告路径记录在 `build/fpga-flow/runs/<run-id>/run.json`。直接调用库级辅助脚本的兼容流程使用本地 `build/fpga-flow/manifest.json`。

## 验证边界

RTL 和 IP Catalog 结果不能替代目标板上的 TMDS 电气检查、时钟容差、EDID 兼容性、音视频同步和 HDMI 认证。板级结果必须注明目标器件、工具版本、IP 参数和测量方法。
