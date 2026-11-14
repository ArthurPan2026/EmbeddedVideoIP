# AXI-Lite register map (V1)

All registers are 32-bit, byte addressed, little-endian. Writes are accepted with independent AXI-Lite AW and W handshakes. Control bit 8 is a commit pulse, bit 9 requests one BRAM frame read, bit 10 clears sticky errors, bit 11 aborts and holds the current stream for reconfiguration, and bit 12 releases an aborted stream if a platform callback fails. A valid configuration commit releases the hold after the active configuration is updated.

| Offset | Name | Access | Fields |
|---|---|---|---|
| 0x00 | CTRL | RW/W1P | bit 0 enable; bits 2:1 source (0 BRAM, 1 HLS, 2 VDMA); bit 3 nearest-neighbor enable; bit 4 stretch mode; bits 6:5 pixel format; bit 8 commit; bit 9 start BRAM frame; bit 10 clear errors |
| 0x04 | INPUT_SIZE | RW | width[15:0], height[31:16] |
| 0x08 | STRIDE_BYTES | RW | source memory line stride in bytes |
| 0x0C | BRAM_BASE_WORD | RW | BRAM reader base address in 32-bit words |
| 0x10 | STATUS | RO | bits 7:6 active source, bit 5 BRAM busy, bit 4 pipeline busy, bit 2 configuration pending, bit 1 stream held, bit 0 enabled |
| 0x14 | FRAME_COUNT | RO | completed output frames |
| 0x18 | ERROR_FLAGS | RO | low half scaler/profile errors; bit 4 rejects disabled source, fixed-format mismatch, or non-1:1 geometry when the scaler is disabled; high half BRAM reader errors. Clear with CTRL bit 10. |
| 0x1C | ACTIVE_SIZE_CFG | RW | active width[9:0], height[25:16] |
| 0x20 | OFFSETS | RW | x offset[9:0], y offset[25:16] |
| 0x24 | SOURCE_ORIGIN | RW | source x[9:0], source y[25:16] |
| 0x28 | X_RATIO | RW | source step[9:0], remainder[25:16] |
| 0x2C | Y_RATIO | RW | source step[9:0], remainder[25:16] |
| 0x30 | ACTIVE_SIZE | RO | actual active width/height after frame start |

RGB888 AXI4-Stream Video uses AMD component packing: R in TDATA[23:16], B in [15:8], G in [7:0]. The core converts to internal RGB for scaling and emits the same RBG order. XRGB8888 memory input is a distinct format whose low 24-bit word is RGB.

The PS library computes ACTIVE_SIZE_CFG, OFFSETS, SOURCE_ORIGIN, and X/Y_RATIO from the requested input geometry, scale mode, aspect policy, and fixed output timing. The RTL core does not implement a variable divider. The supported V1 product uses the paired PS library to write these derived registers before setting CTRL.commit. If a continuous stream never presents a software-observable idle cycle, the library aborts the partial frame, holds input ready low, reconfigures the source, then commits and releases the hold on a valid configuration. Direct register writes are reserved for diagnostics; PL-only integration is not a supported V1 configuration.
