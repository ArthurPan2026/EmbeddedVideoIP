`timescale 1ns/1ps

module tb_video_pipeline_static_profile;
  logic aclk = 1'b0;
  logic aresetn = 1'b0;

  logic [5:0] s_axi_awaddr = '0;
  logic s_axi_awvalid = 1'b0;
  logic s_axi_awready;
  logic [31:0] s_axi_wdata = '0;
  logic [3:0] s_axi_wstrb = 4'hf;
  logic s_axi_wvalid = 1'b0;
  logic s_axi_wready;
  logic [1:0] s_axi_bresp;
  logic s_axi_bvalid;
  logic s_axi_bready = 1'b1;
  logic [5:0] s_axi_araddr = '0;
  logic s_axi_arvalid = 1'b0;
  logic s_axi_arready;
  logic [31:0] s_axi_rdata;
  logic [1:0] s_axi_rresp;
  logic s_axi_rvalid;
  logic s_axi_rready = 1'b1;

  logic [31:0] s_axis_hls_tdata = '0;
  logic s_axis_hls_tvalid = 1'b0;
  logic s_axis_hls_tready;
  logic s_axis_hls_tuser = 1'b0;
  logic s_axis_hls_tlast = 1'b0;
  logic [31:0] s_axis_vdma_tdata = '0;
  logic s_axis_vdma_tvalid = 1'b0;
  logic s_axis_vdma_tready;
  logic s_axis_vdma_tuser = 1'b0;
  logic s_axis_vdma_tlast = 1'b0;
  logic m_axis_video_tready = 1'b1;
  logic [23:0] m_axis_video_tdata;
  logic m_axis_video_tvalid;
  logic m_axis_video_tuser;
  logic m_axis_video_tlast;
  logic bram_en;
  logic [17:0] bram_addr;
  logic [31:0] bram_dout = '0;
  logic bram_busy;
  logic bram_frame_done;
  logic hdmi_audio_enable, audio_mute;
  logic [16:0] audio_gain_q15;
  logic audio_underflow = 1'b0, audio_overflow = 1'b0;

  integer output_count = 0;
  integer x;
  integer y;
  integer first_x;
  logic [31:0] readback;
  logic [31:0] status_word;

  localparam logic [31:0] CTRL_VDMA_XRGB_COMMIT = 32'h0000_0145;
  localparam logic [31:0] CTRL_VDMA_XRGB_CLEAR = 32'h0000_0545;
  localparam logic [31:0] CTRL_VDMA_XRGB_ABORT = 32'h0000_0845;
  localparam logic [31:0] TEST_XRGB_WORD = 32'h0012_3456;
  localparam logic [23:0] TEST_RBG_WORD = 24'h12_56_34;
  localparam integer FRAME_PIXELS = 640 * 480;

  always #5 aclk = ~aclk;

  video_pipeline_v1_0 #(
    .MAX_INPUT_WIDTH(640),
    .MAX_INPUT_HEIGHT(480),
    .MAX_SCALER_INPUT_WIDTH(240),
    .MAX_SCALER_INPUT_HEIGHT(160),
    .OUTPUT_WIDTH(640),
    .OUTPUT_HEIGHT(480),
    .BRAM_ADDR_WIDTH(18),
    .AXI_ADDR_WIDTH(6),
    .ENABLE_BRAM_SOURCE(0),
    .ENABLE_HLS_SOURCE(0),
    .ENABLE_VDMA_SOURCE(1),
    .SOURCE_SELECT_MODE(1),
    .FIXED_SOURCE(2),
    .FORMAT_SELECT_MODE(1),
    .FIXED_FORMAT(2),
    .ENABLE_SCALER(0),
    .ENABLE_HDMI_AUDIO(0)
  ) dut (
    .aclk(aclk), .aresetn(aresetn),
    .bram_en(bram_en), .bram_addr(bram_addr), .bram_dout(bram_dout),
    .bram_busy(bram_busy), .bram_frame_done(bram_frame_done),
    .s_axis_hls_tdata(s_axis_hls_tdata), .s_axis_hls_tvalid(s_axis_hls_tvalid),
    .s_axis_hls_tready(s_axis_hls_tready), .s_axis_hls_tuser(s_axis_hls_tuser),
    .s_axis_hls_tlast(s_axis_hls_tlast),
    .s_axis_vdma_tdata(s_axis_vdma_tdata), .s_axis_vdma_tvalid(s_axis_vdma_tvalid),
    .s_axis_vdma_tready(s_axis_vdma_tready), .s_axis_vdma_tuser(s_axis_vdma_tuser),
    .s_axis_vdma_tlast(s_axis_vdma_tlast),
    .m_axis_video_tdata(m_axis_video_tdata), .m_axis_video_tvalid(m_axis_video_tvalid),
    .m_axis_video_tready(m_axis_video_tready), .m_axis_video_tuser(m_axis_video_tuser),
    .m_axis_video_tlast(m_axis_video_tlast),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .hdmi_audio_enable(hdmi_audio_enable), .audio_mute(audio_mute),
    .audio_gain_q15(audio_gain_q15), .audio_underflow(audio_underflow),
    .audio_overflow(audio_overflow), .hdmi_diag_status(6'b000000)
  );

  always @(posedge aclk) begin
    if (!aresetn) begin
      output_count <= 0;
    end else if (m_axis_video_tvalid && m_axis_video_tready) begin
      if (m_axis_video_tdata !== TEST_RBG_WORD)
        $fatal(1, "直通像素颜色错误：%06x", m_axis_video_tdata);
      if (m_axis_video_tuser !== (output_count == 0))
        $fatal(1, "输出像素%0d的帧首标记不匹配", output_count);
      if (m_axis_video_tlast !== ((output_count % 640) == 639))
        $fatal(1, "输出像素%0d的行尾标记不匹配", output_count);
      output_count <= output_count + 1;
    end
  end

  task automatic axi_write(input logic [5:0] address, input logic [31:0] value);
    begin
      @(negedge aclk);
      s_axi_awaddr = address;
      s_axi_awvalid = 1'b1;
      s_axi_wdata = value;
      s_axi_wstrb = 4'hf;
      s_axi_wvalid = 1'b1;
      do @(posedge aclk); while (!(s_axi_awready && s_axi_wready));
      @(negedge aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      wait (s_axi_bvalid);
      @(negedge aclk);
    end
  endtask

  task automatic axi_read(input logic [5:0] address, output logic [31:0] value);
    begin
      @(negedge aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      do @(posedge aclk); while (!s_axi_arready);
      @(negedge aclk);
      s_axi_arvalid = 1'b0;
      wait (s_axi_rvalid);
      value = s_axi_rdata;
      @(negedge aclk);
    end
  endtask

  initial begin
    repeat (4) @(posedge aclk);
    @(negedge aclk);
    aresetn = 1'b1;
    repeat (3) @(posedge aclk);

    // 固定关闭 HDMI 音频时，AXI-Lite 写入不能重新引入音频逻辑。
    axi_read(6'h34, readback);
    if (readback !== 32'd0 || hdmi_audio_enable !== 1'b0)
      $fatal(1, "TEST_FAIL: 关闭HDMI音频profile的复位状态不匹配");
    axi_write(6'h34, 32'd3);
    axi_read(6'h34, readback);
    if (readback !== 32'd2 || hdmi_audio_enable !== 1'b0 || audio_mute !== 1'b1)
      $fatal(1, "TEST_FAIL: 关闭HDMI音频profile未将使能强制为低");
    axi_write(6'h38, 32'd40000);
    axi_read(6'h38, readback);
    if (readback !== 32'd32768 || audio_gain_q15 !== 17'd32768)
      $fatal(1, "TEST_FAIL: 音频关闭profile的增益饱和值不匹配");

    // 固定源profile在首帧前的STATUS中也应报告VDMA。
    axi_read(6'h10, status_word);
    if (status_word[7:6] !== 2'd2)
      $fatal(1, "fixed source status did not report VDMA: %08x", status_word);
    if (bram_en !== 1'b0 || bram_addr !== 18'd0 || bram_busy !== 1'b0 || bram_frame_done !== 1'b0)
      $fatal(1, "disabled BRAM source outputs were not tied inactive");
    if (s_axis_hls_tready !== 1'b0)
      $fatal(1, "disabled HLS source asserted TREADY");

    // 配置精确的640x480直通帧；该profile不实例化scaler。
    axi_write(6'h04, 32'h01e0_0280); // 640 x 480
    axi_write(6'h08, 32'd2560);
    axi_write(6'h1c, 32'h01e0_0280); // 活动区域640x480
    axi_write(6'h20, 32'd0);
    axi_write(6'h24, 32'd0);
    axi_write(6'h28, 32'd1); // x步长为1、余数为0
    axi_write(6'h2c, 32'd1); // y步长为1、余数为0
    axi_write(6'h00, CTRL_VDMA_XRGB_COMMIT);
    repeat (3) @(posedge aclk);

    // Hold the first output beat under 下游背压 and check it remains stable.
    @(negedge aclk);
    m_axis_video_tready = 1'b0;
    s_axis_vdma_tdata = TEST_XRGB_WORD;
    s_axis_vdma_tvalid = 1'b1;
    s_axis_vdma_tuser = 1'b1;
    s_axis_vdma_tlast = 1'b0;
    #1;
    if (m_axis_video_tvalid !== 1'b1 || m_axis_video_tdata !== TEST_RBG_WORD ||
        m_axis_video_tuser !== 1'b1 || s_axis_vdma_tready !== 1'b0)
      $fatal(1, "first beat did not honor output 下游背压");
    repeat (3) begin
      @(posedge aclk);
      #1;
      if (m_axis_video_tvalid !== 1'b1 || m_axis_video_tdata !== TEST_RBG_WORD ||
          m_axis_video_tuser !== 1'b1 || s_axis_vdma_tready !== 1'b0)
        $fatal(1, "AXI-Stream停顿期间数据拍发生变化");
    end
    @(negedge aclk);
    m_axis_video_tready = 1'b1;
    do @(posedge aclk); while (!s_axis_vdma_tready);
    @(negedge aclk);
    s_axis_vdma_tvalid = 1'b0;
    s_axis_vdma_tuser = 1'b0;
    s_axis_vdma_tlast = 1'b0;

    axi_read(6'h10, status_word);
    if (status_word[4] !== 1'b1 || status_word[7:6] !== 2'd2)
      $fatal(1, "帧监视器未报告busy/固定源状态：%08x", status_word);

    // 保留一个未完成帧，发出中止请求并保持新输入，直到
    // 有效配置提交后恢复直通profile。
    @(negedge aclk);
    s_axis_vdma_tdata = TEST_XRGB_WORD;
    s_axis_vdma_tvalid = 1'b1;
    s_axis_vdma_tuser = 1'b0;
    s_axis_vdma_tlast = 1'b0;
    do @(posedge aclk); while (!s_axis_vdma_tready);
    @(negedge aclk);
    s_axis_vdma_tvalid = 1'b0;
    axi_read(6'h10, status_word);
    if (status_word[4] !== 1'b1)
      $fatal(1, "流中止前未报告部分帧busy");
    axi_write(6'h00, CTRL_VDMA_XRGB_ABORT);
    repeat (3) @(posedge aclk);
    axi_read(6'h10, status_word);
    if (status_word[4] !== 1'b0 || status_word[1] !== 1'b1 ||
        status_word[0] !== 1'b1 || s_axis_vdma_tready !== 1'b0 ||
        m_axis_video_tvalid !== 1'b0)
      $fatal(1, "中止后未清除busy或保持直通输入：%08x", status_word);
    axi_write(6'h00, CTRL_VDMA_XRGB_COMMIT);
    repeat (3) @(posedge aclk);
    axi_read(6'h10, status_word);
    if (status_word[4] !== 1'b0 || status_word[2] !== 1'b0 ||
        status_word[1] !== 1'b0 || status_word[0] !== 1'b1 ||
        s_axis_vdma_tready !== 1'b1)
      $fatal(1, "有效提交未释放被保持的输入：%08x", status_word);
    @(negedge aclk);
    output_count = 0;

    // 恢复后发送完整640x480帧，并检查TUSER/TLAST与颜色直通。
    for (y = 0; y < 480; y = y + 1) begin
      first_x = 0;
      for (x = first_x; x < 640; x = x + 1) begin
        @(negedge aclk);
        s_axis_vdma_tdata = TEST_XRGB_WORD;
        s_axis_vdma_tvalid = 1'b1;
        s_axis_vdma_tuser = ((x == 0) && (y == 0));
        s_axis_vdma_tlast = (x == 639);
        do @(posedge aclk); while (!s_axis_vdma_tready);
      end
    end
    @(negedge aclk);
    s_axis_vdma_tvalid = 1'b0;
    s_axis_vdma_tuser = 1'b0;
    s_axis_vdma_tlast = 1'b0;
    repeat (2) @(posedge aclk);
    if (output_count != FRAME_PIXELS)
      $fatal(1, "直通像素数为%0d，预期为%0d", output_count, FRAME_PIXELS);
    axi_read(6'h10, status_word);
    axi_read(6'h14, readback);
    if (status_word[4] !== 1'b0 || status_word[7:6] !== 2'd2 || readback !== 32'd1)
      $fatal(1, "帧完成状态/计数不匹配：status=%08x count=%08x", status_word, readback);
    axi_read(6'h18, readback);
    if (readback !== 32'd0)
      $fatal(1, "有效帧后出现意外错误标志：%08x", readback);

    // 请求已裁剪的BRAM源必须安全失败并设置bit4。
    axi_write(6'h00, 32'h0000_0141); // 使能、固定XRGB并提交，源选择为BRAM
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback[4] !== 1'b1)
      $fatal(1, "禁用源请求未设置ERROR_FLAGS[4]：%08x", readback);
    axi_read(6'h10, status_word);
    if (status_word[7:6] !== 2'd2 || status_word[4] !== 1'b0)
      $fatal(1, "请求被拒绝后固定源/状态发生变化：%08x", status_word);
    @(negedge aclk);
    s_axis_vdma_tdata = TEST_XRGB_WORD;
    s_axis_vdma_tvalid = 1'b1;
    s_axis_vdma_tuser = 1'b1;
    #1;
    if (m_axis_video_tvalid !== 1'b0 || s_axis_vdma_tready !== 1'b0)
      $fatal(1, "拒绝源请求后仍有视频输出");
    @(negedge aclk);
    s_axis_vdma_tvalid = 1'b0;
    s_axis_vdma_tuser = 1'b0;

    // 恢复有效profile并清除sticky错误。
    axi_write(6'h00, CTRL_VDMA_XRGB_CLEAR);
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback !== 32'd0)
      $fatal(1, "CTRL清错未清除profile错误：%08x", readback);

    // 固定格式不匹配时安全拒绝，不重新解释像素。
    axi_write(6'h00, 32'h0000_0165); // 使能VDMA并配置BGRX8888后提交
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback[4] !== 1'b1)
      $fatal(1, "固定格式不匹配未设置ERROR_FLAGS[4]：%08x", readback);
    if (m_axis_video_tvalid !== 1'b0)
      $fatal(1, "固定格式不匹配未安全拒绝");
    axi_write(6'h00, CTRL_VDMA_XRGB_CLEAR);
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback !== 32'd0)
      $fatal(1, "格式profile错误未清除：%08x", readback);

    // 非1:1几何配置应被拒绝，不能静默直通或缩放。
    axi_write(6'h04, 32'h00f0_0140); // 320x240
    axi_write(6'h08, 32'd1280);
    axi_write(6'h1c, 32'h00f0_0140); // 活动区域320x240
    axi_write(6'h20, 32'd0);
    axi_write(6'h24, 32'd0);
    axi_write(6'h28, 32'd1);
    axi_write(6'h2c, 32'd1);
    axi_write(6'h00, CTRL_VDMA_XRGB_COMMIT);
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback[4] !== 1'b1)
      $fatal(1, "非1:1几何配置未设置ERROR_FLAGS[4]：%08x", readback);
    if (m_axis_video_tvalid !== 1'b0)
      $fatal(1, "非1:1几何配置未安全拒绝");

    $display("TEST_PASS: tb_video_pipeline_static_profile");
    $finish;
  end
endmodule
