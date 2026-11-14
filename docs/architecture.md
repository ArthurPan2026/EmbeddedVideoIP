# Architecture and contracts

## Stream contract

Every stream beat is one pixel. TUSER[0] marks the first pixel of a frame; TLAST marks the last pixel of a line. The producer must hold TDATA and sideband signals stable while TVALID is high and TREADY is low. The processing core preserves frame and line boundaries and reasserts them after scaling.

The scaler uses internal RGB888 values. The AXI4-Stream Video source format `RGB888` follows AMD packing: TDATA[23:16]=R, [15:8]=B, [7:0]=G. The source adapter converts that to internal RGB. XRGB8888 and BGRX8888 are 32-bit containers; X/padding bytes are ignored. The output converts internal RGB back to standard AXI4-Stream Video RBG packing.

## Sources

- BRAM reader: single synchronous 32-bit word read port, one-cycle read latency. RGB565 pixels are packed low-halfword first; width and stride describe the logical image. The caller holds the selected frame bank stable until frame_done.
- HLS source: AXI4-Stream Video; SOF/EOL are carried on TUSER/TLAST.
- DDR source: AMD AXI VDMA MM2S AXI4-Stream output in the V1 32-bit pixel container (4 bytes per pixel, RGB888 in the low 24 bits or XRGB/BGRX). RGB565 is used by the BRAM reader; unpack it before a VDMA source. The VDMA remains a standard block-design IP with its own AXI-Lite register interface.

The source mux only asserts TREADY to the selected source. Change the selected source between frames; the core drains the current frame before accepting a newly selected source.

## Scaling

Output timing is fixed at 640x480p60 in V1. With bypass selected, the source is mapped 1:1 and centered. With scaling selected, nearest-neighbor mapping is used. Fit mode preserves aspect ratio and centers the image with black bars; stretch mode uses the complete 640x480 canvas.

The maximum input dimensions are synthesis parameters. The default is 640x480; increase them only when the target device resource and timing reports support the new configuration.

## Runtime configuration

Vivado IP parameters provide safe defaults and the maximum line-buffer width. AXI-Lite configures source, input width/height, stride, format, scale/aspect mode, and enable. The paired PS library computes active dimensions, padding, source origin, and integer DDA step/remainder, then writes those derived registers before committing at a frame boundary. This keeps variable division out of the high-rate RTL path. Invalid zero/oversize geometry or ratios are rejected and set sticky status bits; clear them through AXI-Lite. A malformed frame is discarded until the next SOF.

The supported product is the paired PL+PS package. Its PS C library configures both the core and the native VDMA register map; the VDMA adapter programs frame addresses/HSIZE/VSIZE/STRIDE and the library commits the derived core settings. The V1 board adapter targets Zynq-7000/FreeRTOS. PL-only integration is not part of V1. HSIZE is bytes per line, VSIZE is the line count, and STRIDE is the byte distance between line starts.
