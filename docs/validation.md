# 验证流程与验收记录

EmbeddedVideoIP 保存库级测试、包身份与综合结果。消费工程保存应用配置、部署产物、运行日志及人工观察，两者通过版本与文件哈希关联。

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

OOC 综合记录各 profile 的资源和路径。消费工程的 post-route STA 记录最终 setup/hold 与 DRC。通过 FPGAFlow 运行时，输入锁与索引保存在仓库外的状态目录，完整输入、输出哈希和报告路径记录在 `build/fpga-flow/runs/<run-id>/run.json`。直接调用库级辅助脚本的兼容流程使用本地 `build/fpga-flow/manifest.json`。

## 测试与板级记录

RTL 和 IP Catalog 记录功能及接口检查。板级记录包含目标器件、工具版本、IP 参数、采集条件和测量方法。当前源码身份与结果见[dev.6 交付验证](validation-2026-11-24.md)。
