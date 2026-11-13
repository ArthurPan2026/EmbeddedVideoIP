# AMD 7-series board adapter

The V1 board-tested integration profile is Zybo Z7-20 (XC7Z020). The portable video pipeline IP and PS C library are paired with the AMD AXI VDMA, VTC, AXI4-Stream video-out, clock wizard, and Digilent rgb2dvi 1.4.

The full HDL block-design assembly lives with the first consuming GBA project so its existing PS clock/reset, EDID/HPD, VDMA frame buffers, and Digilent source lock remain authoritative. The GBA build flow imports this repository's ip_repo and deploys the generated PL+PS artifacts over JTAG.

The Digilent rgb2dvi 1.4 PHY uses 7-series OSERDES/MMCM primitives. Other Vivado families may use the portable AXI4-Stream core and the matched PS API, but require a family-appropriate HDMI PHY/clock adapter. This is a platform boundary, not a project-specific change to the video core.
