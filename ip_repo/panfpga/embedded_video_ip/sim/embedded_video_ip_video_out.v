//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2.1 (lin64) Build 6403652 Thu Mar 19 13:47:00 MDT 2026
//Date        : Mon Nov 16 09:35:32 2026
//Host        : pzy-fpga running 64-bit Ubuntu 22.04.5 LTS
//Command     : generate_target embedded_video_ip_video_out.bd
//Design      : embedded_video_ip_video_out
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CORE_GENERATION_INFO = "embedded_video_ip_video_out,IP_Integrator,{x_ipVendor=xilinx.com,x_ipLibrary=BlockDiagram,x_ipName=embedded_video_ip_video_out,x_ipVersion=1.00.a,x_ipLanguage=VERILOG,numBlks=6,numReposBlks=6,numNonXlnxBlks=0,numHierBlks=0,maxHierDepth=0,numSysgenBlks=0,numHlsBlks=0,numHdlrefBlks=0,numPkgbdBlks=0,bdsource=USER,synth_mode=Hierarchical}" *) (* HW_HANDOFF = "embedded_video_ip_video_out.hwdef" *) 
module embedded_video_ip_video_out
   (aclk,
    aresetn,
    hdmi_ref_clk,
    pixel_aresetn,
    pixel_clk,
    s_axis_video_tdata,
    s_axis_video_tlast,
    s_axis_video_tready,
    s_axis_video_tuser,
    s_axis_video_tvalid,
    serial_clk,
    video_de,
    video_hsync,
    video_rgb,
    video_vsync);
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.ACLK CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.ACLK, ASSOCIATED_BUSIF s_axis_video, CLK_DOMAIN embedded_video_ip_video_out_aclk, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input aclk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.ARESETN RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.ARESETN, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) input aresetn;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.HDMI_REF_CLK CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.HDMI_REF_CLK, CLK_DOMAIN embedded_video_ip_video_out_hdmi_ref_clk, FREQ_HZ 50000000, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) input hdmi_ref_clk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 RST.PIXEL_ARESETN RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME RST.PIXEL_ARESETN, INSERT_VIP 0, POLARITY ACTIVE_LOW" *) output [0:0]pixel_aresetn;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.PIXEL_CLK CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.PIXEL_CLK, CLK_DOMAIN /clk_wiz_clk_out1, FREQ_HZ 25178571, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) output pixel_clk;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_video TDATA" *) (* X_INTERFACE_MODE = "Slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axis_video, CLK_DOMAIN embedded_video_ip_video_out_aclk, FREQ_HZ 100000000, HAS_TKEEP 0, HAS_TLAST 1, HAS_TREADY 1, HAS_TSTRB 0, INSERT_VIP 0, LAYERED_METADATA undef, PHASE 0.0, TDATA_NUM_BYTES 3, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 1" *) input [23:0]s_axis_video_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_video TLAST" *) input s_axis_video_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_video TREADY" *) output s_axis_video_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_video TUSER" *) input s_axis_video_tuser;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis_video TVALID" *) input s_axis_video_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 CLK.SERIAL_CLK CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME CLK.SERIAL_CLK, CLK_DOMAIN /clk_wiz_clk_out1, FREQ_HZ 125892857, FREQ_TOLERANCE_HZ 0, INSERT_VIP 0, PHASE 0.0" *) output serial_clk;
  output video_de;
  output video_hsync;
  output [23:0]video_rgb;
  output video_vsync;

  wire aclk;
  wire aresetn;
  wire clk_wiz_locked;
  wire hdmi_ref_clk;
  wire [0:0]pixel_aresetn;
  wire pixel_clk;
  wire [0:0]pixel_reset_peripheral_reset;
  wire [0:0]reset_invert_Res;
  wire [0:0]reset_zero_dout;
  wire [23:0]s_axis_video_tdata;
  wire s_axis_video_tlast;
  wire s_axis_video_tready;
  wire s_axis_video_tuser;
  wire s_axis_video_tvalid;
  wire serial_clk;
  wire video_de;
  wire video_hsync;
  wire video_out_vtg_ce;
  wire [23:0]video_rgb;
  wire video_vsync;
  wire vtc_vtiming_out_ACTIVE_VIDEO;
  wire vtc_vtiming_out_HBLANK;
  wire vtc_vtiming_out_HSYNC;
  wire vtc_vtiming_out_VBLANK;
  wire vtc_vtiming_out_VSYNC;

  embedded_video_ip_video_out_clk_wiz_0 clk_wiz
       (.clk_in1(hdmi_ref_clk),
        .clk_out1(pixel_clk),
        .clk_out2(serial_clk),
        .locked(clk_wiz_locked),
        .resetn(aresetn));
  embedded_video_ip_video_out_pixel_reset_0 pixel_reset
       (.aux_reset_in(reset_zero_dout),
        .dcm_locked(clk_wiz_locked),
        .ext_reset_in(reset_invert_Res),
        .mb_debug_sys_rst(reset_zero_dout),
        .peripheral_aresetn(pixel_aresetn),
        .peripheral_reset(pixel_reset_peripheral_reset),
        .slowest_sync_clk(pixel_clk));
  embedded_video_ip_video_out_reset_invert_0 reset_invert
       (.Op1(aresetn),
        .Res(reset_invert_Res));
  embedded_video_ip_video_out_reset_zero_0 reset_zero
       (.dout(reset_zero_dout));
  embedded_video_ip_video_out_video_out_0 video_out
       (.aclk(aclk),
        .aclken(clk_wiz_locked),
        .aresetn(aresetn),
        .fid(reset_zero_dout),
        .s_axis_video_tdata(s_axis_video_tdata),
        .s_axis_video_tlast(s_axis_video_tlast),
        .s_axis_video_tready(s_axis_video_tready),
        .s_axis_video_tuser(s_axis_video_tuser),
        .s_axis_video_tvalid(s_axis_video_tvalid),
        .vid_active_video(video_de),
        .vid_data(video_rgb),
        .vid_hsync(video_hsync),
        .vid_io_out_ce(clk_wiz_locked),
        .vid_io_out_clk(pixel_clk),
        .vid_io_out_reset(pixel_reset_peripheral_reset),
        .vid_vsync(video_vsync),
        .vtg_active_video(vtc_vtiming_out_ACTIVE_VIDEO),
        .vtg_ce(video_out_vtg_ce),
        .vtg_field_id(1'b0),
        .vtg_hblank(vtc_vtiming_out_HBLANK),
        .vtg_hsync(vtc_vtiming_out_HSYNC),
        .vtg_vblank(vtc_vtiming_out_VBLANK),
        .vtg_vsync(vtc_vtiming_out_VSYNC));
  embedded_video_ip_video_out_vtc_0 vtc
       (.active_video_out(vtc_vtiming_out_ACTIVE_VIDEO),
        .clk(pixel_clk),
        .clken(clk_wiz_locked),
        .gen_clken(video_out_vtg_ce),
        .hblank_out(vtc_vtiming_out_HBLANK),
        .hsync_out(vtc_vtiming_out_HSYNC),
        .resetn(pixel_aresetn),
        .sof_state(1'b0),
        .vblank_out(vtc_vtiming_out_VBLANK),
        .vsync_out(vtc_vtiming_out_VSYNC));
endmodule
