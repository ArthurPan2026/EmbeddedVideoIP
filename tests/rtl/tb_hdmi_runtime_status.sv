`timescale 1ns/1ps
module tb_hdmi_runtime_status;
  logic aclk=0, aresetn=0;
  logic serial_clk=0, serial_clock_enable=0;
  logic pixel_clk=0, pixel_clock_enable=0;
  logic mmcm_locked_async=0, pixel_resetn_async=0, pixel_reset_ext_asserted_async=0, video_vsync_async=0;
  logic [5:0] status;

  always #5 aclk=~aclk;
  always begin
    #4;
    if (serial_clock_enable)
      serial_clk=~serial_clk;
    else
      serial_clk=0;
  end
  always begin
    #6;
    if (pixel_clock_enable)
      pixel_clk=~pixel_clk;
    else
      pixel_clk=0;
  end

  hdmi_runtime_status dut (
    .aclk(aclk), .aresetn(aresetn),
    .pixel_clk(pixel_clk), .mmcm_locked_async(mmcm_locked_async),
    .pixel_resetn_async(pixel_resetn_async),
    .pixel_reset_ext_asserted_async(pixel_reset_ext_asserted_async),
    .serial_clk(serial_clk), .video_vsync_async(video_vsync_async),
    .status(status)
  );

  initial begin
    #12 aresetn=1;
    repeat(4) @(posedge aclk);
    mmcm_locked_async=1;
    pixel_resetn_async=1;
    repeat(4) @(posedge aclk);
    if (status[0] !== 1'b1 || status[3] !== 1'b1)
      $fatal(1,"MMCM锁定/像素复位状态未同步到aclk");
    if (status[1] !== 1'b0 || status[4] !== 1'b0 || status[5] !== 1'b0)
      $fatal(1,"时钟静止时错误报告为活动");

    video_vsync_async=1;
    repeat(4) @(posedge aclk);
    video_vsync_async=0;
    repeat(4) @(posedge aclk);
    if (status[2] !== 1'b1)
      $fatal(1,"未检测到VSYNC变化");

    serial_clock_enable=1;
    pixel_clock_enable=1;
    wait(status[1] === 1'b1 && status[4] === 1'b1);
    pixel_reset_ext_asserted_async=1;
    repeat(4) @(posedge aclk);
    if (status !== 6'b111111)
      $fatal(1,"遥测状态位不匹配：%b",status);
    $display("TEST_PASS: tb_hdmi_runtime_status");
    $finish;
  end

  initial begin
    #100us;
    $fatal(1,"TEST_FAIL: HDMI遥测看门狗超时");
  end
endmodule
