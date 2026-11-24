`timescale 1ns/1ps
module tb_video_pipeline_output_mode #(parameter bit TEST_ENABLE_1080P60 = 1'b0);
  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #5 clk = ~clk;

  logic [5:0] awaddr = 0, araddr = 0;
  logic awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
  logic [31:0] wdata = 0;
  logic [3:0] wstrb = 4'hf;
  wire awready, wready, bvalid, arready, rvalid;
  wire [1:0] bresp, rresp;
  wire [31:0] rdata;

  logic mode_busy = 0;
  logic mode_pixel_reset_hold = 0;
  logic [1:0] mode_active = 0;
  logic mode_error = 0;
  wire [1:0] mode_request;
  wire mode_commit, mode_error_clear, mode_config_ready;
  logic [2:0] mode_debug_state = 3'd0;
  logic [2:0] mode_failure_stage = 3'd0;
  logic mode_debug_vsync_level = 1'b0;
  wire [23:0] video_tdata;
  wire video_tvalid, video_tuser, video_tlast;
  wire hls_ready, vdma_ready;
  wire bram_en, bram_busy, bram_frame_done;
  wire [17:0] bram_addr;
  wire hdmi_audio_enable, hdmi_link_mode, audio_mute;
  wire [16:0] audio_gain_q15;
  wire [31:0] audio_bresp_unused;
  wire [31:0] error_flags = dut.cfg_error_flags;

  video_pipeline_v1_0 #(
    .MAX_INPUT_WIDTH(1280), .MAX_INPUT_HEIGHT(720),
    .OUTPUT_WIDTH(1920), .OUTPUT_HEIGHT(1080),
    .BRAM_ADDR_WIDTH(18), .AXI_ADDR_WIDTH(6),
    .ENABLE_BRAM_SOURCE(0), .ENABLE_HLS_SOURCE(0), .ENABLE_VDMA_SOURCE(1),
    .SOURCE_SELECT_MODE(1), .FIXED_SOURCE(2),
    .FORMAT_SELECT_MODE(1), .FIXED_FORMAT(2),
    .MAX_SCALER_INPUT_WIDTH(1280), .MAX_SCALER_INPUT_HEIGHT(720),
    .ENABLE_SCALER(1), .ENABLE_1080P60(TEST_ENABLE_1080P60), .ENABLE_OUTPUT_MODE(1)
  ) dut (
    .aclk(clk), .aresetn(resetn),
    .bram_en(bram_en), .bram_addr(bram_addr), .bram_dout(32'd0),
    .bram_busy(bram_busy), .bram_frame_done(bram_frame_done),
    .s_axis_hls_tdata(32'd0), .s_axis_hls_tvalid(1'b0), .s_axis_hls_tready(hls_ready),
    .s_axis_hls_tuser(1'b0), .s_axis_hls_tlast(1'b0),
    .s_axis_vdma_tdata(32'd0), .s_axis_vdma_tvalid(1'b0), .s_axis_vdma_tready(vdma_ready),
    .s_axis_vdma_tuser(1'b0), .s_axis_vdma_tlast(1'b0),
    .m_axis_video_tdata(video_tdata), .m_axis_video_tvalid(video_tvalid),
    .m_axis_video_tready(1'b1), .m_axis_video_tuser(video_tuser), .m_axis_video_tlast(video_tlast),
    .s_axi_awaddr(awaddr), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
    .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
    .s_axi_araddr(araddr), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
    .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
    .hdmi_audio_enable(hdmi_audio_enable), .hdmi_link_mode(hdmi_link_mode),
    .audio_mute(audio_mute), .audio_gain_q15(audio_gain_q15),
    .audio_underflow(1'b0), .audio_overflow(1'b0), .hdmi_diag_status(6'd0), .phy_errors(2'b00),
    .video_mode_request(mode_request), .video_mode_commit(mode_commit),
    .video_mode_error_clear(mode_error_clear), .video_mode_active(mode_active),
    .video_mode_busy(mode_busy), .video_mode_pixel_reset_hold(mode_pixel_reset_hold),
    .video_mode_error(mode_error), .video_mode_config_ready(mode_config_ready),
    .video_mode_debug_state(mode_debug_state),
    .video_mode_failure_stage(mode_failure_stage),
    .video_mode_vsync_level(mode_debug_vsync_level)
  );

  task automatic axi_write(input logic [5:0] address, input logic [31:0] value);
    begin
      @(negedge clk);
      awaddr = address; awvalid = 1'b1;
      wdata = value; wstrb = 4'hf; wvalid = 1'b1;
      do @(posedge clk); while (!(awready && wready));
      @(negedge clk); awvalid = 1'b0; wvalid = 1'b0; bready = 1'b1;
      do @(posedge clk); while (!bvalid);
      @(negedge clk); bready = 1'b0;
    end
  endtask

  task automatic axi_read(input logic [5:0] address, output logic [31:0] value);
    begin
      @(negedge clk); araddr = address; arvalid = 1'b1;
      do @(posedge clk); while (!arready);
      @(negedge clk); arvalid = 1'b0; rready = 1'b1;
      do @(posedge clk); while (!rvalid);
      value = rdata;
      @(negedge clk); rready = 1'b0;
    end
  endtask

  logic [31:0] readback;
  initial begin
    #1ms;
    $fatal(1, "TEST_FAIL: output-mode watchdog timeout");
  end

  initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;

    // 640x480 source, 4:3 fit inside a 1280x720 raster.
    axi_write(6'h04, 32'h01e0_0280);
    axi_write(6'h1c, 32'h02d0_03c0); // 960x720 active area
    axi_write(6'h20, 32'h0000_00a0); // x offset 160
    axi_write(6'h24, 32'd0);
    axi_write(6'h28, 32'h0280_0000); // 640 / 960 DDA
    axi_write(6'h2c, 32'h01e0_0000); // 480 / 720 DDA
    axi_write(6'h00, 32'h0001_614d); // mode=720p, HDMI, cfg commit + mode pulse
    wait (dut.cfg_pending);
    if (mode_request !== 2'd1 || mode_config_ready !== 1'b0 ||
        dut.active_output_width !== 11'd640 || dut.active_output_height !== 11'd480)
      $fatal(1, "TEST_FAIL: mode request did not remain pending on the current frame");

    mode_busy = 1'b1;
    mode_pixel_reset_hold = 1'b1; // Old VSYNC completed; hold pixel domain for reconfiguration.
    wait (!dut.cfg_pending);
    @(posedge clk); #1; // config_ready is a registered acknowledgement of the committed geometry.
    if (dut.active_output_width !== 11'd1280 || dut.active_output_height !== 11'd720 ||
        dut.active_active_width !== 11'd960 || dut.active_active_height !== 11'd720 ||
        dut.active_x_offset !== 11'd160 || mode_config_ready !== 1'b1)
      $fatal(1, "TEST_FAIL: 720p geometry was not atomically committed: output=%0dx%0d active=%0dx%0d offset=%0d ready=%b pending=%b mode_pending=%b invalid=%b", dut.active_output_width, dut.active_output_height, dut.active_active_width, dut.active_active_height, dut.active_x_offset, mode_config_ready, dut.cfg_pending, dut.mode_cfg_pending, dut.invalid_profile_request);

    mode_active = 2'd1;
    mode_pixel_reset_hold = 1'b0;
    mode_busy = 1'b0;
    mode_debug_state = 3'd2; // ST_IDLE
    mode_failure_stage = 3'd0; // ST_BOOT_LOCK: no transition failure yet
    mode_debug_vsync_level = 1'b1;
    axi_read(6'h10, readback);
    if (readback[29:28] !== 2'd1 || readback[30] !== 1'b0 || readback[31] !== 1'b0 ||
        readback[27:25] !== 3'd2 || readback[24:22] !== 3'd0 ||
        readback[21] !== 1'b1 || readback[20] !== 1'b1 || readback[19:14] !== 6'h13) // reserved 01 + native-mode mask 0011 (480p/720p)
      $fatal(1, "TEST_FAIL: output-mode status bits mismatch %h", readback);

    // Native 1280x720 input to VIC34 1080p30; 11-bit DDA remainder must retain 1280.
    axi_write(6'h04, 32'h02d0_0500); // native source 1280x720
    axi_write(6'h1c, 32'h0438_05a0); // 1440x1080 active area
    axi_write(6'h20, 32'h0000_00f0); // x offset 240
    axi_write(6'h24, 32'd0);
    axi_write(6'h28, 32'h0500_0000); // 1280 / 1440 DDA
    axi_write(6'h2c, 32'h02d0_0000); // 720 / 1080 DDA
    mode_busy = 1'b1;
    axi_write(6'h00, 32'h0001_a14d); // mode=1080p30, HDMI, cfg commit + mode pulse
    wait (dut.cfg_pending);
    if (mode_request !== 2'd2 || mode_config_ready !== 1'b0 ||
        dut.active_output_width !== 11'd1280 || dut.active_output_height !== 11'd720)
      $fatal(1, "TEST_FAIL: VIC34 request did not wait on the current frame");
    mode_pixel_reset_hold = 1'b1;
    wait (!dut.cfg_pending);
    @(posedge clk); #1; // config_ready is a registered acknowledgement of the committed geometry.
    if (dut.active_output_width !== 11'd1920 || dut.active_output_height !== 11'd1080 ||
        dut.active_active_width !== 11'd1440 || dut.active_active_height !== 11'd1080 ||
        dut.active_x_offset !== 11'd240 || mode_config_ready !== 1'b1)
      $fatal(1, "TEST_FAIL: 1080p30 geometry was not atomically committed");
    mode_active = 2'd2;
    mode_pixel_reset_hold = 1'b0;
    mode_busy = 1'b0;
    axi_read(6'h10, readback);
    if (readback[29:28] !== 2'd2 || readback[30] !== 1'b0 || readback[31] !== 1'b0)
      $fatal(1, "TEST_FAIL: 1080p30 status bits mismatch %h", readback);
    repeat (2) @(posedge clk);
    if (dut.gen_scaler.u_scaler.cfg_invalid_geometry !== 1'b0)
      $fatal(1, "TEST_FAIL: native 1280x720 input was rejected by scaler geometry");

    // Mode 3 is rejected when the 1080p60 profile is disabled. With the
    // profile enabled, the same VIC16 request commits only while pixel reset is held.
    if (!TEST_ENABLE_1080P60) begin
      axi_write(6'h00, 32'h0001_e14d);
      wait (!dut.cfg_pending);
      mode_error = 1'b1;
      mode_pixel_reset_hold = 1'b1;
      mode_debug_state = 3'd7; // ST_FAILED
      mode_failure_stage = 3'd5; // ST_WAIT_CONFIG
      mode_debug_vsync_level = 1'b0;
      axi_read(6'h10, readback);
      if (readback[31] !== 1'b1 || readback[30] !== 1'b0 ||
          readback[27:25] !== 3'd7 || readback[24:22] !== 3'd5 ||
          readback[21] !== 1'b0 || readback[20] !== 1'b0 || readback[19:14] !== 6'h13)
        $fatal(1, "TEST_FAIL: transition debug/status field packing mismatch %h", readback);
      axi_read(6'h18, readback);
      if (!readback[4] || mode_config_ready !== 1'b0 || dut.active_enable !== 1'b0)
        $fatal(1, "TEST_FAIL: disabled 1080p60 request was accepted or not reported");
    end else begin
      mode_busy = 1'b1;
      axi_write(6'h00, 32'h0001_e14d); // VIC16 1080p60 request
      wait (dut.cfg_pending);
      @(posedge clk); #1;
      if (mode_request !== 2'd3 || mode_config_ready !== 1'b0 ||
          dut.invalid_profile_request !== 1'b0 ||
          dut.active_output_width !== 11'd1920 || dut.active_output_height !== 11'd1080)
        $fatal(1, "TEST_FAIL: enabled VIC16 request was not staged atomically");
      mode_pixel_reset_hold = 1'b1;
      wait (!dut.cfg_pending);
      @(posedge clk); #1;
      if (dut.active_output_width !== 11'd1920 || dut.active_output_height !== 11'd1080 ||
          dut.active_active_width !== 11'd1440 || dut.active_active_height !== 11'd1080 ||
          dut.active_x_offset !== 11'd240 || mode_config_ready !== 1'b1 ||
          dut.invalid_profile_error !== 1'b0)
        $fatal(1, "TEST_FAIL: enabled VIC16 geometry did not commit: %0dx%0d active=%0dx%0d ready=%b invalid=%b",
               dut.active_output_width, dut.active_output_height, dut.active_active_width,
               dut.active_active_height, mode_config_ready, dut.invalid_profile_error);
      mode_active = 2'd3;
      mode_pixel_reset_hold = 1'b0;
      mode_busy = 1'b0;
      axi_read(6'h10, readback);
      if (readback[29:28] !== 2'd3 || readback[31] !== 1'b0 || readback[30] !== 1'b0)
        $fatal(1, "TEST_FAIL: enabled VIC16 status mismatch %h", readback);
    end

    $display("TEST_PASS: tb_video_pipeline_output_mode enable1080p60=%0d", TEST_ENABLE_1080P60);
    $finish;
  end
endmodule


module tb_video_pipeline_output_mode_1080p60;
  tb_video_pipeline_output_mode #(.TEST_ENABLE_1080P60(1'b1)) test();
endmodule
