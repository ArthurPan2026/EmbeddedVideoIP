# Build and use

For first use, follow [PL+PS quick start](quickstart-zh.md). V1 is a paired Vivado IP and PS C library; the only turnkey board profile currently validated on hardware is Zybo Z7-20.

## Requirements

- Vivado 2025.2.1 for the current Zybo reference profile (or the exact Vivado version pinned by the consumer).
- Digilent Vivado Library at the revision in dependencies.lock.json.
- For GBA integration: the matching Vitis/BSP version already pinned by that project.

## Build, validate, and package

    python3 tools/video_flow.py doctor
    python3 tools/video_flow.py build --part xc7z020clg400-1

The build command runs XSim regressions and host API tests, packages the IP-XACT core into the versioned ip_repo/ directory, instantiates it in a Vivado IP Integrator validation design, and synthesizes it for the requested device. Reports and temporary projects are stored under out/ with input/output hashes in out/manifest.json.

Run the stages separately with video_flow.py sim, package, validate, and synth. Use status to check whether a previous output still matches the current source fingerprint. The GBA consumer adds its board-specific VTC, AXI VDMA, clock and Digilent rgb2dvi recipe and has its own board deployment command.

## Configure from PS

Install the matching API and Zynq-7000 adapter with `python3 tools/install_ps_library.py --app-src /path/to/vitis_app/src --platform zynq7000`. The installer copies the versioned sources and registers them in `UserConfig.cmake`.

The paired PS C library is in software/video_out.c and software/video_out.h. Its geometry calculator is host-testable and its Xilinx Zynq-7000 adapter supplies MMIO and AXI VDMA setup. The API computes fit/stretch active dimensions and DDA ratios, then programs the core and VDMA. Use the driver sequence:

1. configure the selected source geometry/format and scale mode;
2. configure the native VDMA frame buffer addresses, HSIZE, VSIZE, and STRIDE when using DDR;
3. commit at a frame boundary and enable the stream;
4. poll status/error counters during bring-up.

The GBA project consumes the pinned library version and its build flow verifies the library source hash before building and deploying. Use the GBA build flow's deploy action to run the existing JTAG system-reset/PL/PS/ELF sequence.
