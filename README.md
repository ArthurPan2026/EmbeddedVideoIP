# Embedded Video IP

A reusable PL+PS embedded-video subsystem for Vivado PS-based projects. The supported V1 deliverable is the matched PL IP plus PS C library and board adapter; PL-only use is not a supported release configuration.

The reusable datapath uses plain SystemVerilog and AXI4-Stream Video. It does not depend on a GBA core, XPM, or a specific AMD primitive. The first turnkey board profile is Zybo Z7-20 / Zynq-7000; the core is kept separate from the AMD memory, timing, clock, and HDMI-transmitter adapters.

## Block-level path

BRAM frame reader, HLS AXI4-Stream, and AXI VDMA MM2S each feed a source mux. The selected stream passes through format conversion and a nearest-neighbor scaler/bypass, then AXI4-Stream Video feeds the platform video-out/VTC and Digilent rgb2dvi.

The library provides source adapters, the portable stream core, a matching PS C API, a Zybo Z7-20/Zynq-7000 BSP adapter, a Vivado IP-packaging script, reference block-design/build recipes, simulation tests, and deployment integration with the GBA project.

## V1 behavior

- 640x480p60 output profile.
- RGB565 BRAM input and RGB888/XRGB/BGRX 32-bit AXI4-Stream inputs.
- Runtime source selection, input geometry, scale bypass/nearest-neighbor, and fit/stretch settings.
- Nearest-neighbor fit preserves aspect ratio and adds black bars; stretch fills the output canvas. Bypass is centered 1:1 with black padding.
- A common AXI video-stream clock is used. Use an AXIS clock converter in the block design when a source runs in another clock domain.
- Geometry changes take effect at the next frame boundary. Invalid geometry is rejected and reported.
- DDR frame reads use AMD AXI VDMA in the platform block design; the library does not implement another DDR DMA.

## Compatibility

The RTL core is device-primitive independent. The included HDMI endpoint is specific to the 7-series Digilent rgb2dvi transmitter. Other Vivado families can use the same stream core but need a compatible output-clock/TMDS adapter; see docs/compatibility.md. "Out of the box" support is reported per tested device family and board, not inferred from RTL portability alone.

## Quick start

The V1 product is a paired PL+PS library. The Chinese installation guide covers the Vivado catalog, matching Vitis C library, API call, and validated board scope: [docs/quickstart-zh.md](docs/quickstart-zh.md).

## Build and test

See docs/build-and-use.md. All Vivado commands use the tool version selected by the consuming project. The library does not silently upgrade a project toolchain.

## Integration notes

- Keep upstream Digilent and AMD IP under their own licenses and versions.
- The GBA project is an example consumer. GBA register maps, frame capture descriptors, ROM timing, and PS application code do not belong in this library.
- The library source has no blanket redistribution license yet; check NOTICE.md before copying third-party content.
