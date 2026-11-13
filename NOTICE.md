# Source and license boundaries

This repository contains original reusable RTL and tooling. No blanket open-source license is assigned to the original library yet.

The HDMI transmitter is not reimplemented here. The AMD 7-series board profile references Digilent rgb2dvi 1.4 from the Digilent Vivado Library, pinned in dependencies.lock.json. Its source and license remain the upstream dependency's responsibility; retain its copyright and MIT license when distributing that dependency.

AMD Vivado IP (AXI VDMA, VTC, video-out, clock wizard, and interconnect IP) is generated/used from the installed Vivado catalog and is not copied into this repository. The license terms of each AMD IP remain applicable.
