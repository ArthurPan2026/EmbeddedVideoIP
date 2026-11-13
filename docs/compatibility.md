# Compatibility and support matrix

## Supported PL+PS package

V1 is delivered as a matched PL IP plus PS C library/BSP adapter. A PL-only design is not a supported V1 configuration. The current board-tested profile is Zybo Z7-20 / XC7Z020 / Zynq-7000 with the project's pinned Vivado/Vitis 2025.2.1.

## Separate portable core from board output

The stream processor contains no XPM or device-specific primitive. Its companion PS API computes fit/stretch geometry and programs both the custom AXI-Lite registers and the native VDMA. It uses synchronous RTL, AXI4-Stream Video, and a configurable BRAM source interface. Its source can be packaged for Vivado IP Integrator across device families that support the selected SystemVerilog and AXI interfaces.

The turnkey HDMI endpoint is a separate platform wrapper. The current Digilent rgb2dvi 1.4 sources instantiate 7-series resources such as OSERDESE2 and MMCME2_ADV; that endpoint is therefore not claimed as a drop-in UltraScale/Versal transmitter. A family-specific TMDS adapter or external HDMI transmitter is required on those targets.

AMD AXI VDMA is itself available on a broad range of AMD families; its exact family support and feature set are taken from the installed Vivado IP catalog. The reference recipe checks that the selected part supports each required IP before generating a block design.

| Layer | V1 support claim | Validation |
|---|---|---|
| Portable RTL stream core | No vendor primitives; intended for Vivado-supported FPGA families | Simulation plus synthesis on the documented matrix |
| AMD AXI VDMA adapter | Only parts where the installed AXI VDMA IP is available | IP catalog lookup and BD validation |
| VDMA MM2S source on Zybo Z7-20 | Zynq-7000 / XC7Z020 | GBA PL+PS board run with MechPlatoon and Skyland |
| HLS AXI4-Stream and BRAM reader on board | Not yet validated | RTL simulation only |
| Digilent HDMI output | 7-series devices compatible with Digilent rgb2dvi 1.4 | Zybo Z7-20 hardware profile |
| Other HDMI PHY families | Not included in V1 | Requires a separate clock/TMDS adapter |

Do not interpret source portability as hardware validation on every Vivado part. Add a family to the tested matrix only after a clean IP package, synthesis, timing, and board/reference-design check.
