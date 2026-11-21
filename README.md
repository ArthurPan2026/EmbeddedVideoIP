# EmbeddedVideoIP

EmbeddedVideoIP 是面向 Vivado 的 HDMI 视频输出 IP 与配套 Zynq-7000 PS C 库。源代码仓库用于开发与维护；集成到其他 FPGA 工程时，可以只下载对应的精简发布包。

## 发布包

| 需求 | 下载内容 | 用途 |
|---|---|---|
| 在 Vivado 工程使用视频硬件 IP | `EmbeddedVideoIP-<version>-vivado-<version>.zip` | Vivado IP Catalog repository，包含 Composite IP、所需接口定义、版本元数据、快速开始文档和 CERN-OHL-W-2.0 |
| 在 Zynq-7000 Vitis 应用使用 PS 库 | `EmbeddedVideoIP-PS-Zynq7000-<version>.zip` | 包含四个 C 源/头文件、集成说明和 Apache-2.0 |
| 修改、仿真或重新发布 IP | 克隆完整源代码仓库 | 包含 RTL、软件、合同、文档、工具和回归 |

发布文件位于 [GitHub Releases](https://github.com/ArthurPan2026/EmbeddedVideoIP/releases)。每个发布同时提供 `SHA256SUMS` 和 `RELEASE-METADATA.json`。

## 使用 Vivado IP 包

1. 下载对应 Vivado 版本的硬件 IP ZIP 并解压。
2. 在 Vivado 工程选择 **Settings → IP → Repository**，添加解压目录中的 `ip_repo/`。
3. 刷新 IP Catalog，并加入 VLNV `panfpga.org:video:embedded_video_ip:1.0`。
4. 按 [IP 包快速开始](docs/ip-package-quickstart.md) 连接时钟、复位、AXI、视频和 TMDS 接口。

包内元数据记录版本、Vivado 版本、来源提交及每个文件的 SHA-256。完整接口说明见 [组合式 IP 接口](docs/composite-ip-api.md)、[寄存器映射](docs/register-map.md) 和 [架构](docs/architecture.md)。

## 源码开发

项目使用 Vivado 2025.2.1。维护者工作流、仿真与综合命令见 [构建和使用](docs/build-and-use.md)。标签发布流程运行于配置了 Vivado 2025.2.1 的自托管 runner，并由仓库变量 `VIVADO_RELEASE_RUNNER_ENABLED=true` 启用。版本锁定于 `VERSION`；发布标签使用 `v<version>`。

## 许可

许可范围按目录记录于 [LICENSES/README.md](LICENSES/README.md)。IP RTL 与硬件接口文件使用 CERN-OHL-W-2.0；PS C 库使用 Apache-2.0；项目文档使用 CC-BY-4.0。第三方目录内的组件继续使用其附带许可。
