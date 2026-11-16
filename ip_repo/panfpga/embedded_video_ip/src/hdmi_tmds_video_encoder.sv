`timescale 1ns/1ps
// 三通道视频/控制编码复用Digilent 7-series TMDS_Encoder。
module hdmi_tmds_video_encoder (
  input  logic       pixel_clk,
  input  logic       serial_clk,
  input  logic       aresetn,
  input  logic [23:0] video_rgb_rbg,
  input  logic       video_de,
  input  logic       hsync,
  input  logic       vsync,
  output logic [9:0] lane0_blue_symbol,
  output logic [9:0] lane1_green_symbol,
  output logic [9:0] lane2_red_symbol
);
  // Digilent 的 rgb2dvi 将打包像素按 RBG 顺序解释：B 在[15:8]，G在[7:0]，R在[23:16]。
  TMDS_Encoder u_blue_encoder (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~aresetn),
    .pDataOutRaw(lane0_blue_symbol), .pDataOut(video_rgb_rbg[15:8]),
    .pC0(hsync), .pC1(vsync), .pVde(video_de)
  );

  TMDS_Encoder u_green_encoder (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~aresetn),
    .pDataOutRaw(lane1_green_symbol), .pDataOut(video_rgb_rbg[7:0]),
    .pC0(1'b0), .pC1(1'b0), .pVde(video_de)
  );

  TMDS_Encoder u_red_encoder (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~aresetn),
    .pDataOutRaw(lane2_red_symbol), .pDataOut(video_rgb_rbg[23:16]),
    .pC0(1'b0), .pC1(1'b0), .pVde(video_de)
  );
endmodule
