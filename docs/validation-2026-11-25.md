# 2026-11-25 dev.15 仿真与发布记录

## 发布身份

| 项目 | 身份 |
|---|---|
| IP | `panfpga.org:video:embedded_video_ip:1.0` |
| 版本 | `0.3.0-dev.15 / coreRevision 16` |
| Vivado | 2025.2.1 |
| 打包时 Git HEAD | `3e6885f46c289955763d38caba4270e79cf7f2f8` |
| canonical 源码交付 commit | `92c1302992498f76d73abfc3942d12879cfb8c90` |
| canonical 源码树 SHA-256 | `063e4de78d03da8b587cb2c4a6f5d4ea13d3bdcc88ec8226918acbe574488e00` |
| IP ZIP SHA-256 | `b5e8dc1e0a81493be76fe8faae5ae72c2f16b2b7afc6715348dd8a1b3fd59117` |
| PS ZIP SHA-256 | `73b27f13543c164eedbcf37ba1e30233d4d5dbe553024ec249f82a42943f33ba` |
| SHA256SUMS SHA-256 | `4d7359930a4ee1e72234403bfa53c88469c35b4f61e0bdbf11636db00711905e` |

包版本保留为 dev.15。打包时记录的 `source_commit` 是当时仓库 HEAD，canonical 源码树 SHA-256 固定此次打包的实际源码文件。

## 验证结果

| 阶段 | FPGAFlow run ID | 结果 |
|---|---|---|
| 全量 XSim | `20261125T010521Z-f3bdb37322` | 30 个 RTL bench 全部通过，采用 XSim `-a -R` |
| 主机测试 | `20261125T010521Z-f3bdb37322` | 41 项通过 |
| IP package | `20261125T010906Z-62381b7960` | Catalog 与生成包完成校验，47 个注册文件 |
| Release ZIP | `20261125T010946Z-b2ae97a8b1` | IP、PS 库与 SHA256SUMS 生成完成 |

XSim 覆盖四模式时钟、1080p60 输出、同步 BRAM scaler、视频帧与行边界、最近邻缩放、输入错误恢复、音频 packet、PCM FIFO、采样率节奏、ACR 和 HDMI 数据岛调度。

GBA 消费工程导入相同 dev.15 包。依赖锁记录 canonical 源码树哈希 `063e4de7...488e00`、IP ZIP SHA-256、PS ZIP SHA-256 和两个安装目录树哈希。GBA 的时序、资源、四模式采集和 QSPI 记录见[2026-11-25 GBA 交付验证](https://github.com/ArthurPan2026/GBA-Zynq7020/blob/main/docs/validation-2026-11-25-delivery.md)。

## 双行 BRAM scaler 实现

`video_pipeline_v1_0` 在 `LINE_BUFFER_IMPLEMENTATION=1` 时实例化 `axis_video_nn_scaler_prefetch`。两组 24-bit BRAM bank 保存输入行。完整行尾到达后，bank 的 `line_y` 和 `line_valid` 标记对输出侧生效。垂直 DDA 生成 `source_y`，水平 DDA 生成 `source_x`，逐行活动窗口限定有效区的 BRAM 读请求。

同步 BRAM 在地址请求后的一个时钟沿输出 `read_data` 并置位 `read_valid`。AXI 输出仅在 `TVALID ∧ TREADY` 握手后推进像素位置与活动窗口计数。输入可向空闲 bank 采集下一行，输出读取当前行。精确 1:1 profile 走直通路径。详细结构见[架构说明](architecture.md#双行-bram-预取缩放器)。
