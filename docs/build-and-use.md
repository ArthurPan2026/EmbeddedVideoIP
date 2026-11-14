# Build and use

For first use, follow [PL+PS quick start](quickstart-zh.md). V1 is a paired Vivado IP and PS C library. The only turnkey board profile currently validated on hardware is Zybo Z7-20.

## Requirements

- Vivado 2025.2.1 for the current Zybo reference profile (or the exact Vivado version pinned by the consumer).
- Digilent Vivado Library at the revision in dependencies.lock.json.
- The consumer's matching Vitis/BSP version and target-device definition.

## Build, validate, and package

    python3 tools/video_flow.py doctor
    python3 tools/video_flow.py build --part xc7z020clg400-1

The build command runs XSim regressions and host API tests, packages the IP-XACT core into the versioned ip_repo/ directory, instantiates it in a Vivado IP Integrator validation design, and synthesizes it for the requested device. Reports and temporary projects are stored under out/ with input/output hashes in out/manifest.json.

Run the stages separately with `video_flow.py sim`, `package`, `validate`, and `synth`. Use `status` to check whether a previous output still matches the current source fingerprint. A consumer project connects the core to its VTC, AXI VDMA, clock, and output-transmitter IP, then supplies its own board deployment flow.

The synthesis profiles `vdma_scaler_lutram` and `vdma_scaler_bram` use the same source path and dimensions. They differ only in the scaler line-buffer implementation. Select the profile that matches the target device's LUTRAM and BRAM budget. The consumer can set its own IP parameters in its Vivado block design.

## Configure from PS

Install the matching API and Zynq-7000 adapter with `python3 tools/install_ps_library.py --app-src /path/to/vitis_app/src --platform zynq7000`. The installer copies the versioned sources and registers them in `UserConfig.cmake`.

The paired PS C library is in software/video_out.c and software/video_out.h. Its geometry calculator is host-testable and its Xilinx Zynq-7000 adapter supplies MMIO and AXI VDMA setup. The API computes fit/stretch active dimensions and DDA ratios, then programs the core and VDMA. Use the driver sequence:

1. configure the selected source geometry/format and scale mode;
2. configure the native VDMA frame buffer addresses, HSIZE, VSIZE, and STRIDE when using DDR;
3. commit at a frame boundary and enable the stream;
4. poll status/error counters during bring-up.

The consumer project selects a library release, sets the IP parameters in its block design, and configures the PS API for its input format and memory layout. Keep consumer-specific build, bitstream, and deployment commands in that project.
