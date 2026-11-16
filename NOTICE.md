# 版权与许可边界

本仓库自有 RTL、PS 库和构建工具目前没有统一的开源许可证。未经作者许可，不应将自有代码作为开源库再分发。

HDMI 发送适配器由本项目自主实现。7-series TMDS 编码与串行输出部分复用 Digilent 的 TMDS_Encoder.vhd、DVI_Constants.vhd 和 OutputSERDES.vhd。上游提交、文件哈希和 BSD 3-Clause 许可见 third_party/digilent-rgb2dvi/NOTICE.md。分发生成的 IP 包时，必须保留随包提供的第三方声明和许可证。

AXI VDMA、VTC、AXI4-Stream 视频输出桥和 Clock Wizard 等 AMD IP 由安装的 Vivado IP Catalog 生成或引用。本仓库不复制这些 AMD IP。使用这些 IP 时仍须遵守对应 Vivado 版本的许可条款。

输入系统的 VDMA、DDR、PS/CIPS、GPIO 和 IIC 由消费工程提供，不属于 EmbeddedVideoIP 的许可或实现边界。
