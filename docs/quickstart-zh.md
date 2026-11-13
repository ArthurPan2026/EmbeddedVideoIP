# PL+PS 快速上手

## 当前支持范围

EmbeddedVideoIP 按一套 PL+PS 产品交付。PL 侧提供 Vivado IP，PS 侧提供匹配版本的 C API 和平台适配器。V1 不支持只放入 PL 的独立配置。

当前完成实板验证的组合是 Zybo Z7-20、XC7Z020、Zynq-7000、Vivado/Vitis 2025.2.1。其他器件可以复用不含厂商原语的视频流 RTL，但目前没有对应的 PS 适配器和完整板级参考设计，不能视为开箱即用。
本轮板测覆盖 VDMA MM2S 输入、PS 配置、缩放和 HDMI 输出。HLS 与 BRAM 输入通过 RTL 仿真，尚未完成板上源切换验收。

视频核心接收 BRAM RGB565、HLS AXI4-Stream 或 VDMA MM2S 输入。它输出 RGB888 AXI4-Stream。V1 HDMI 参考输出使用 AMD VDMA、VTC、`v_axi4s_vid_out` 和 Digilent `rgb2dvi`。`rgb2dvi` 依赖 7-series 原语。

## 构建和验证库

在安装了 Vivado 2025.2.1 的 Linux 主机上运行：

```sh
python3 tools/video_flow.py doctor
python3 tools/video_flow.py build --part xc7z020clg400-1
```

`build` 会运行 RTL 与 C 回归，打包 Vivado IP，验证 IP Catalog 设计，并综合视频核心。构建输入和产物哈希写入 `out/manifest.json`。

## 安装到 Vivado

先在 Vivado Tcl Console 中打开消费工程，再执行：

```tcl
source /path/to/EmbeddedVideoIP/tools/add_to_vivado_project.tcl
```

脚本会把库的 `ip_repo/` 加入当前工程并刷新 IP Catalog。之后在 IP Integrator 中添加 `panfpga.org:video:video_pipeline:1.0`。

基础连接如下：

- 将 `s_axi` 接到 PS 的 AXI 主端口，用于访问视频核心寄存器。
- 将 VDMA 的 MM2S AXI4-Stream 接到 `s_axis_vdma`。
- 将 HLS 视频流接到 `s_axis_hls`。
- 将 BRAM 双口存储器的读数据接到 `bram_dout`，并连接 `bram_en` 和 `bram_addr`。
- 将 `m_axis_video` 接到 `v_axi4s_vid_out`，再连接 VTC、像素时钟和板级 HDMI 发射器。
- 所有核心 AXI-Stream 源使用同一个 `aclk`。跨时钟源先接 AXI4-Stream Clock Converter。
- 将 `aresetn` 接到同一时钟域的低有效复位。

工程必须使用 IP 配置的最大输入宽度。DDR 输入按 32 bit 像素容器传输；`STRIDE_BYTES` 表示相邻行首地址的字节间隔。视频核心配置寄存器的完整定义见 [寄存器表](register-map.md)。

## 安装匹配的 PS 库

把库的 C API 和 Zynq-7000 适配器安装到 Vitis 应用源码目录。目录中必须有 `UserConfig.cmake`：

```sh
python3 tools/install_ps_library.py \
  --app-src /path/to/vitis_app/src \
  --platform zynq7000
```

安装器会复制 `video_out.h`、`video_out.c` 和 Xilinx VDMA 适配器，并把源文件与头文件目录登记到 `UserConfig.cmake`。重复运行不会重复添加配置。目标目录已有不同内容时，安装器会停止，不覆盖文件。

## PS 端调用示例

先按 Vitis BSP 初始化 `XAxiVdma`，再绑定视频核心寄存器地址和帧缓冲区：

```c
#include "video_out_xilinx.h"
#include "xparameters.h"

static VideoOutXilinx video;
static VideoOutIo video_io;
static VideoOutConfig config = {
    .source = VIDEO_OUT_SOURCE_VDMA,
    .format = VIDEO_OUT_PIX_XRGB8888,
    .width = 240U,
    .height = 160U,
    .stride_bytes = 240U * 4U,
    .scale = VIDEO_OUT_SCALE_NEAREST,
    .aspect = VIDEO_OUT_ASPECT_FIT,
    .enabled = 0U,
    .initial_frame_index = 0U,
};

int start_video(XAxiVdma *vdma, UINTPTR frame0, uint32_t frame_slot_bytes)
{
    if (VideoOutXilinx_Bind(&video, vdma,
            XPAR_VIDEO_PIPELINE_0_S_AXI_BASEADDR,
            frame0, frame_slot_bytes, 3U) != 0) {
        return -1;
    }
    if (VideoOutXilinx_Configure(&video, &config, 4U) != 0) {
        return -1;
    }
    video_io = VideoOutXilinx_GetIo(&video);
    return VideoOut_Start(&video_io);
}
```

应用需要先为 VDMA 配置并分配至少 3 个帧缓冲。每个帧缓冲的 `frame_slot_bytes` 必须覆盖 `stride_bytes × height`。`VideoOutXilinx_Configure()` 会设置 MM2S 的 HSIZE、VSIZE、STRIDE 和帧地址，也会写入核心的输入格式与缩放参数。

运行时可用 `VideoOut_GetStatus()` 读取活动源、活动尺寸、帧计数和错误标志。使用 HLS 或 BRAM 源时，PS API 仍负责配置视频核心；源数据由对应的 PL 接口提供。

## 打包内容

- `ip_repo/`：可加入 Vivado IP Catalog 的 PL IP。
- `software/`：通用 PS API 与平台无关的配置计算。
- `software/platforms/xilinx_zynq7000/`：Zynq-7000、Vitis standalone/FreeRTOS 的 VDMA 和 MMIO 适配器。
- `platforms/amd_7series/`：Zybo Z7-20 板级能力和依赖说明。
- `tools/`：回归、IP 打包、Vivado 工程注册和 Vitis 库安装工具。

HDMI 时钟、VTC、物理发射器、PS 地址映射和帧缓冲分配仍由板级工程配置。当前只有 Zybo Z7-20 配套了可复现的整板构建与部署流程。
