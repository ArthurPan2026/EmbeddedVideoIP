`timescale 1ns/1ps
module tb_hdmi_tmds_mode_mux;
  localparam logic [2:0] MODE_CONTROL=3'd0, MODE_VIDEO=3'd1,
                         MODE_VIDEO_PREAMBLE=3'd2, MODE_DATA_PREAMBLE=3'd3,
                         MODE_VIDEO_GUARD=3'd4, MODE_DATA_GUARD=3'd5,
                         MODE_DATA_PAYLOAD=3'd6;
  logic pixel_clk=0, aresetn=0;
  logic [2:0] symbol_mode=MODE_CONTROL;
  logic hsync=0, vsync=0;
  logic [8:0] packet_data=0;
  logic [9:0] video_lane0=10'h155, video_lane1=10'h266, video_lane2=10'h0AA;
  logic [9:0] tmds_lane0, tmds_lane1, tmds_lane2;
  integer h, v;
  logic [9:0] expected_lane0;

  always #5 pixel_clk=~pixel_clk;
  hdmi_tmds_mode_mux #(.ENCODER_LATENCY(3)) dut (
    .pixel_clk(pixel_clk), .aresetn(aresetn), .symbol_mode(symbol_mode),
    .hsync(hsync), .vsync(vsync), .packet_data(packet_data),
    .video_lane0(video_lane0), .video_lane1(video_lane1), .video_lane2(video_lane2),
    .tmds_lane0(tmds_lane0), .tmds_lane1(tmds_lane1), .tmds_lane2(tmds_lane2)
  );

  task automatic wait_pipeline;
    repeat(3) @(posedge pixel_clk);
    #1;
  endtask
  task automatic expect_symbols(input logic [9:0] e0, input logic [9:0] e1,
                                input logic [9:0] e2, input string label_text);
    begin
      if (tmds_lane0!==e0 || tmds_lane1!==e1 || tmds_lane2!==e2)
        $fatal(1,"%s符号不匹配：%03h/%03h/%03h",label_text,tmds_lane0,tmds_lane1,tmds_lane2);
    end
  endtask

  initial begin
    repeat(3) @(posedge pixel_clk);
    @(negedge pixel_clk); aresetn=1;
    repeat(4) @(posedge pixel_clk);
    #1;
    expect_symbols(video_lane0,video_lane1,video_lane2,"复位控制默认值");

    // HDMI 1.3数据岛保护带：蓝通道半字节C..F携带D1:0=VS:HS。
    symbol_mode=MODE_DATA_GUARD;
    for (v=0;v<2;v=v+1) begin
      for (h=0;h<2;h=h+1) begin
        @(negedge pixel_clk); hsync=h[0]; vsync=v[0];
        wait_pipeline();
        case ({v[0],h[0]})
          2'b00: expected_lane0=10'b1010001110;
          2'b01: expected_lane0=10'b1001110001;
          2'b10: expected_lane0=10'b0101100011;
          default: expected_lane0=10'b1011000011;
        endcase
        expect_symbols(expected_lane0,10'b0100110011,10'b0100110011,"数据岛保护带");
      end
    end

    // 负载中蓝通道D2传header位、D0/D1仍传HS/VS；绿/红通道取相邻子包位。
    @(negedge pixel_clk); symbol_mode=MODE_DATA_PAYLOAD;
    hsync=1; vsync=0; packet_data={1'b0,4'hA,4'h5};
    wait_pipeline();
    expect_symbols(10'b1001100011,10'b0100011110,10'b0110011100,"数据岛负载");

    @(negedge pixel_clk); packet_data={1'b1,4'h3,4'hC}; hsync=0; vsync=1;
    wait_pipeline();
    expect_symbols(10'b0110001110,10'b1010001110,10'b1011100010,"header位与子包位序");

    @(negedge pixel_clk); symbol_mode=MODE_VIDEO_PREAMBLE; hsync=1; vsync=1;
    wait_pipeline();
    expect_symbols(video_lane0,10'b0010101011,10'b1101010100,"视频前导");

    @(negedge pixel_clk); symbol_mode=MODE_DATA_PREAMBLE;
    wait_pipeline();
    expect_symbols(video_lane0,10'b0010101011,10'b0010101011,"数据岛前导");

    @(negedge pixel_clk); symbol_mode=MODE_VIDEO_GUARD;
    wait_pipeline();
    expect_symbols(10'b1011001100,10'b0100110011,10'b1011001100,"视频保护带");

    $display("TEST_PASS: hdmi_tmds_mode_mux");
    $finish;
  end
endmodule
