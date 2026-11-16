`timescale 1ns/1ps
module tb_hdmi_digilent_video_encoder;
  localparam logic [2:0] MODE_CONTROL=3'd0, MODE_VIDEO=3'd1;
  logic pixel_clk=0, serial_clk=0, aresetn=0;
  logic [23:0] video_rgb_rbg=0;
  logic video_de=0, hsync=0, vsync=0;
  logic [2:0] mode=MODE_CONTROL;
  logic [9:0] dut_lane0, dut_lane1, dut_lane2;
  logic [9:0] ref_lane0, ref_lane1, ref_lane2;
  logic [9:0] custom_lane0, custom_lane1, custom_lane2;
  logic [9:0] custom_lane0_d0, custom_lane0_d1;
  logic [9:0] custom_lane1_d0, custom_lane1_d1;
  logic [9:0] custom_lane2_d0, custom_lane2_d1;
  integer vector_index;

  always #5 pixel_clk=~pixel_clk;
  always #1 serial_clk=~serial_clk;

  hdmi_tmds_video_encoder dut (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .aresetn(aresetn),
    .video_rgb_rbg(video_rgb_rbg), .video_de(video_de), .hsync(hsync), .vsync(vsync),
    .lane0_blue_symbol(dut_lane0), .lane1_green_symbol(dut_lane1),
    .lane2_red_symbol(dut_lane2)
  );
  TMDS_Encoder ref_blue (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~aresetn),
    .pDataOutRaw(ref_lane0), .pDataOut(video_rgb_rbg[15:8]),
    .pC0(hsync), .pC1(vsync), .pVde(video_de)
  );
  TMDS_Encoder ref_green (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~aresetn),
    .pDataOutRaw(ref_lane1), .pDataOut(video_rgb_rbg[7:0]),
    .pC0(1'b0), .pC1(1'b0), .pVde(video_de)
  );
  TMDS_Encoder ref_red (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~aresetn),
    .pDataOutRaw(ref_lane2), .pDataOut(video_rgb_rbg[23:16]),
    .pC0(1'b0), .pC1(1'b0), .pVde(video_de)
  );
  hdmi_tmds_symbol_encoder custom_reference (
    .pixel_clk(pixel_clk), .resetn(aresetn), .mode(mode),
    .video_rgb(video_rgb_rbg), .hsync(hsync), .vsync(vsync), .ctl_bits(4'b0000),
    .packet_data(9'd0), .lane0_symbol(custom_lane0),
    .lane1_symbol(custom_lane1), .lane2_symbol(custom_lane2)
  );

  always_ff @(posedge pixel_clk or negedge aresetn) begin
    if (!aresetn) begin
      custom_lane0_d0<=10'd0; custom_lane0_d1<=10'd0;
      custom_lane1_d0<=10'd0; custom_lane1_d1<=10'd0;
      custom_lane2_d0<=10'd0; custom_lane2_d1<=10'd0;
    end else begin
      custom_lane0_d0<=custom_lane0; custom_lane0_d1<=custom_lane0_d0;
      custom_lane1_d0<=custom_lane1; custom_lane1_d1<=custom_lane1_d0;
      custom_lane2_d0<=custom_lane2; custom_lane2_d1<=custom_lane2_d0;
    end
  end

  task automatic check_outputs(input integer index);
    begin
      if (dut_lane0!==ref_lane0 || dut_lane1!==ref_lane1 || dut_lane2!==ref_lane2)
        $fatal(1,"RBG lane映射错误，向量%d",index);
      if (dut_lane0!==custom_lane0_d1 || dut_lane1!==custom_lane1_d1 ||
          dut_lane2!==custom_lane2_d1)
        $fatal(1,"Digilent与自研TMDS视频编码不一致，向量%d",index);
    end
  endtask

  initial begin
    repeat(3) @(posedge pixel_clk);
    @(negedge pixel_clk); aresetn=1;
    // 复位释放后等待空白控制符稳定，跳过VHDL流水线尚未填满的前三拍。
    for (vector_index=0;vector_index<100;vector_index=vector_index+1) begin
      @(negedge pixel_clk);
      if (vector_index%6==0) begin
        mode=MODE_CONTROL; video_de=1'b0;
        hsync=vector_index[0]; vsync=vector_index[1];
        video_rgb_rbg=24'h000000;
      end else begin
        mode=MODE_VIDEO; video_de=1'b1; hsync=1'b0; vsync=1'b0;
        case (vector_index%6)
          1: video_rgb_rbg=24'hFF0000; // 红色通道为FF，绿色和蓝色通道为0
          2: video_rgb_rbg=24'h0000FF; // 绿色通道为FF，红色和蓝色通道为0
          3: video_rgb_rbg=24'h00FF00; // 蓝色通道为FF，红色和绿色通道为0
          default: video_rgb_rbg=$urandom;
        endcase
      end
      @(posedge pixel_clk); #1;
      if (vector_index>=2)
        check_outputs(vector_index);
    end
    $display("TEST_PASS: hdmi_digilent_video_encoder");
    $finish;
  end
endmodule
