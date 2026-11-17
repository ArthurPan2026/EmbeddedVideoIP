//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2025.2.1 (lin64) Build 6403652 Thu Mar 19 13:47:00 MDT 2026
//Date        : Tue Nov 17 15:41:27 2026
//Host        : pzy-fpga running 64-bit Ubuntu 22.04.5 LTS
//Command     : generate_target embedded_video_ip_video_out_wrapper.bd
//Design      : embedded_video_ip_video_out_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module embedded_video_ip_video_out_wrapper
   (aclk,
    aresetn,
    hdmi_mmcm_locked,
    hdmi_ref_clk,
    pixel_aresetn,
    pixel_clk,
    pixel_reset_ext_asserted,
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
  input aclk;
  input aresetn;
  output hdmi_mmcm_locked;
  input hdmi_ref_clk;
  output [0:0]pixel_aresetn;
  output pixel_clk;
  output [0:0]pixel_reset_ext_asserted;
  input [23:0]s_axis_video_tdata;
  input s_axis_video_tlast;
  output s_axis_video_tready;
  input s_axis_video_tuser;
  input s_axis_video_tvalid;
  output serial_clk;
  output video_de;
  output video_hsync;
  output [23:0]video_rgb;
  output video_vsync;

  wire aclk;
  wire aresetn;
  wire hdmi_mmcm_locked;
  wire hdmi_ref_clk;
  wire [0:0]pixel_aresetn;
  wire pixel_clk;
  wire [0:0]pixel_reset_ext_asserted;
  wire [23:0]s_axis_video_tdata;
  wire s_axis_video_tlast;
  wire s_axis_video_tready;
  wire s_axis_video_tuser;
  wire s_axis_video_tvalid;
  wire serial_clk;
  wire video_de;
  wire video_hsync;
  wire [23:0]video_rgb;
  wire video_vsync;

  embedded_video_ip_video_out embedded_video_ip_video_out_i
       (.aclk(aclk),
        .aresetn(aresetn),
        .hdmi_mmcm_locked(hdmi_mmcm_locked),
        .hdmi_ref_clk(hdmi_ref_clk),
        .pixel_aresetn(pixel_aresetn),
        .pixel_clk(pixel_clk),
        .pixel_reset_ext_asserted(pixel_reset_ext_asserted),
        .s_axis_video_tdata(s_axis_video_tdata),
        .s_axis_video_tlast(s_axis_video_tlast),
        .s_axis_video_tready(s_axis_video_tready),
        .s_axis_video_tuser(s_axis_video_tuser),
        .s_axis_video_tvalid(s_axis_video_tvalid),
        .serial_clk(serial_clk),
        .video_de(video_de),
        .video_hsync(video_hsync),
        .video_rgb(video_rgb),
        .video_vsync(video_vsync));
endmodule
