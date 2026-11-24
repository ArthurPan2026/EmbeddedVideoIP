# 2026-11-24 dev.6 变更与验证

## 源码与产物身份

版本为 `0.3.0-dev.6`，VLNV 为 `panfpga.org:video:embedded_video_ip:1.0`，`coreRevision=7`，工具为 Vivado 2025.2.1。canonical 源码树 SHA-256 为 `5256d1268ff90b1a77b089404b683987cd558c7a8b8a4a201481bc06d216153d`。

| 产物 | SHA-256 |
|---|---|
| 硬件 IP ZIP | `dcf43eb433a6daf7ae95c4099575474f7626a7c152b17d755ccc620fdeb70d40` |
| Zynq-7000 PS ZIP | `a62c647e30c4cf40f8ed52892788459b3ec410a282a602d226c6da783e180b38` |

生产 package run 为 `20261123T204357Z-c4e33de76c`。包在工作树开发期间生成，历史 `source_commit=cda0758be7c01c13e00a6519bf505d2fe84fa512` 表示当时 HEAD。实际 RTL/XDC 身份由 canonical 文件哈希固定。本轮提交保留该源码树和原发布 ZIP，更新仓库内快照至同一生产包。

## 修复内容

四模式加入 VIC 16，模式 3 对应 1080p60。serializer PLL 双输出直驱触发 REQP-1975 后，改用固定反馈倍率的 MMCM 与 BUFIO/BUFR。运行时音频和行调度改用 profile 常量，缩短从模式参数到 packet CE 的组合路径。

模式切换期间复位 scaler。旁路输入等待 SOF 后启动，解决消费系统 VDMA 从帧中途恢复导致的 framing 错误。相关 testbench 更新覆盖模式、packet、采样节奏、复位与帧同步。

## 自动测试

2026-11-24 的 canonical host 回归 40 项通过，覆盖契约、C API、package release、回归执行器和构建输入。此前强制重跑 `tb_video_pipeline_static_profile` 通过，覆盖旁路 SOF 恢复。本轮包快照按注册源码和 metadata 逐文件校验。

## GBA 消费工程结果

硬件 run `20261123T215815Z-8d4e4fd8d5` 的最终 setup WNS 为 `+0.003 ns`，hold WHS 为 `+0.050 ns`，TNS/THS 为 0，实际 DRC Error 为 0。1080p60 的 OSERDESE2 pulse-width 为 `−0.320 ns`，按本项目超频实验配置单列。

2026-11-24 的板端与 C1-1 采集记录覆盖 640×480@60、1280×720@60 和 1920×1080@60。1080p60 录得 48 kHz 双声道音频，mean 为 −29.0 dBFS，peak 为 −19.2 dBFS。GBA 菜单与首帧交接的后续 PS 修复及人工验收记录在消费工程文档。
