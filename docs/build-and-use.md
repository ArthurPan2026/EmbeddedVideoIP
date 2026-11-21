# 构建和使用

## 在独立工程中使用 Vivado IP

1. 从 [GitHub Releases](https://github.com/ArthurPan2026/EmbeddedVideoIP/releases) 下载对应 Vivado 版本的 IP ZIP。
2. 解压后，在工程的 **Settings → IP → Repository** 添加包中的 `ip_repo/`。
3. 刷新 Catalog，实例化 VLNV `panfpga.org:video:embedded_video_ip:1.0`。
4. 参考 [组合式 IP 接口](composite-ip-api.md)、[寄存器映射](register-map.md) 与 [架构](architecture.md) 配置 AXI、视频时序、音频和 HDMI 输出。

Vivado 工程只需 IP ZIP。修改 IP 源码、重新打包或运行完整回归时，使用完整源码仓库。

## Vitis PS library

若 PS 应用需要视频输出 API，从 Releases 下载 `EmbeddedVideoIP-PS-Zynq7000-<version>.zip`，并将包内 `Video/Lib/` 放入应用源码树。加入头文件目录：

- `Video/Lib/Inc`
- `Video/Lib/XilinxZynq7000`

将以下源文件加入 Vitis 应用：

- `Video/Lib/Src/video_out.c`
- `Video/Lib/XilinxZynq7000/video_out_xilinx.c`

该软件包使用 Apache-2.0。GBA-Zynq7020 将此库作为项目源码的一部分，并在 `config/dependencies.lock.json` 锁定其版本与包哈希。

## 源码构建

源码开发基线为 Vivado 2025.2.1。工具版本锁定于 `tools/video_flow.py`。常用维护流程：

```sh
python tools/video_flow.py build --vivado /path/to/vivado
python tools/package_release.py --vivado-version 2025.2.1
```

构建输出位于 `out/`，发布包位于 `out/releases/`。源文件与发布资产版本通过 `VERSION`、Git tag 和 `RELEASE-METADATA.json` 关联。
