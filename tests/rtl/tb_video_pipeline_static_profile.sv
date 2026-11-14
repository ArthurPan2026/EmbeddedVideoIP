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
    .ENABLE_SCALER(0)
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
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready)
  );

  always @(posedge aclk) begin
    if (!aresetn) begin
      output_count <= 0;
    end else if (m_axis_video_tvalid && m_axis_video_tready) begin
      if (m_axis_video_tdata !== TEST_RBG_WORD)
        $fatal(1, "unexpected passthrough color: %06x", m_axis_video_tdata);
      if (m_axis_video_tuser !== (output_count == 0))
        $fatal(1, "SOF mismatch at output pixel %0d", output_count);
      if (m_axis_video_tlast !== ((output_count % 640) == 639))
        $fatal(1, "EOL mismatch at output pixel %0d", output_count);
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

    // A fixed-source profile reports VDMA in STATUS even before the first frame.
    axi_read(6'h10, status_word);
    if (status_word[7:6] !== 2'd2)
      $fatal(1, "fixed source status did not report VDMA: %08x", status_word);
    if (bram_en !== 1'b0 || bram_addr !== 18'd0 || bram_busy !== 1'b0 || bram_frame_done !== 1'b0)
      $fatal(1, "disabled BRAM source outputs were not tied inactive");
    if (s_axis_hls_tready !== 1'b0)
      $fatal(1, "disabled HLS source asserted TREADY");

    // Configure an exact 640x480 pass-through frame. No scaler is instantiated.
    axi_write(6'h04, 32'h01e0_0280); // 640 x 480
    axi_write(6'h08, 32'd2560);
    axi_write(6'h1c, 32'h01e0_0280); // active size 640 x 480
    axi_write(6'h20, 32'd0);
    axi_write(6'h24, 32'd0);
    axi_write(6'h28, 32'd1); // x step 1, remainder 0
    axi_write(6'h2c, 32'd1); // y step 1, remainder 0
    axi_write(6'h00, CTRL_VDMA_XRGB_COMMIT);
    repeat (3) @(posedge aclk);

    // Hold the first output beat under backpressure and check it remains stable.
    @(negedge aclk);
    m_axis_video_tready = 1'b0;
    s_axis_vdma_tdata = TEST_XRGB_WORD;
    s_axis_vdma_tvalid = 1'b1;
    s_axis_vdma_tuser = 1'b1;
    s_axis_vdma_tlast = 1'b0;
    #1;
    if (m_axis_video_tvalid !== 1'b1 || m_axis_video_tdata !== TEST_RBG_WORD ||
        m_axis_video_tuser !== 1'b1 || s_axis_vdma_tready !== 1'b0)
      $fatal(1, "first beat did not honor output backpressure");
    repeat (3) begin
      @(posedge aclk);
      #1;
      if (m_axis_video_tvalid !== 1'b1 || m_axis_video_tdata !== TEST_RBG_WORD ||
          m_axis_video_tuser !== 1'b1 || s_axis_vdma_tready !== 1'b0)
        $fatal(1, "AXI-Stream beat changed while stalled");
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
      $fatal(1, "frame monitor did not expose busy/fixed-source status: %08x", status_word);

    // Leave a partial frame active, request an abort, and hold new input until
    // a valid configuration commit restores the pass-through profile.
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
      $fatal(1, "partial frame did not assert busy before stream abort");
    axi_write(6'h00, CTRL_VDMA_XRGB_ABORT);
    repeat (3) @(posedge aclk);
    axi_read(6'h10, status_word);
    if (status_word[4] !== 1'b0 || status_word[1] !== 1'b1 ||
        status_word[0] !== 1'b1 || s_axis_vdma_tready !== 1'b0 ||
        m_axis_video_tvalid !== 1'b0)
      $fatal(1, "abort did not clear busy and hold pass-through input: %08x", status_word);
    axi_write(6'h00, CTRL_VDMA_XRGB_COMMIT);
    repeat (3) @(posedge aclk);
    axi_read(6'h10, status_word);
    if (status_word[4] !== 1'b0 || status_word[2] !== 1'b0 ||
        status_word[1] !== 1'b0 || status_word[0] !== 1'b1 ||
        s_axis_vdma_tready !== 1'b1)
      $fatal(1, "valid commit did not release the held input: %08x", status_word);
    @(negedge aclk);
    output_count = 0;

    // Send a complete 640x480 frame after recovery. TUSER/TLAST and color pass through.
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
      $fatal(1, "pass-through pixel count %0d, expected %0d", output_count, FRAME_PIXELS);
    axi_read(6'h10, status_word);
    axi_read(6'h14, readback);
    if (status_word[4] !== 1'b0 || status_word[7:6] !== 2'd2 || readback !== 32'd1)
      $fatal(1, "frame completion status/count mismatch: status=%08x count=%08x", status_word, readback);
    axi_read(6'h18, readback);
    if (readback !== 32'd0)
      $fatal(1, "unexpected error flags after valid frame: %08x", readback);

    // A request for the compiled-out BRAM source must fail closed and set bit 4.
    axi_write(6'h00, 32'h0000_0141); // enable + fixed XRGB + commit, source=BRAM
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback[4] !== 1'b1)
      $fatal(1, "disabled source request did not set ERROR_FLAGS[4]: %08x", readback);
    axi_read(6'h10, status_word);
    if (status_word[7:6] !== 2'd2 || status_word[4] !== 1'b0)
      $fatal(1, "fixed source/status changed after rejected request: %08x", status_word);
    @(negedge aclk);
    s_axis_vdma_tdata = TEST_XRGB_WORD;
    s_axis_vdma_tvalid = 1'b1;
    s_axis_vdma_tuser = 1'b1;
    #1;
    if (m_axis_video_tvalid !== 1'b0 || s_axis_vdma_tready !== 1'b0)
      $fatal(1, "rejected source request did not disable output");
    @(negedge aclk);
    s_axis_vdma_tvalid = 1'b0;
    s_axis_vdma_tuser = 1'b0;

    // Restore the valid profile and clear the sticky error.
    axi_write(6'h00, CTRL_VDMA_XRGB_CLEAR);
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback !== 32'd0)
      $fatal(1, "CTRL clear-errors did not clear profile error: %08x", readback);

    // A fixed-format mismatch also fails closed instead of reinterpreting pixels.
    axi_write(6'h00, 32'h0000_0165); // enable + VDMA + BGRX8888 + commit
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback[4] !== 1'b1)
      $fatal(1, "fixed-format mismatch did not set ERROR_FLAGS[4]: %08x", readback);
    if (m_axis_video_tvalid !== 1'b0)
      $fatal(1, "fixed-format mismatch was not rejected fail-closed");
    axi_write(6'h00, CTRL_VDMA_XRGB_CLEAR);
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback !== 32'd0)
      $fatal(1, "format-profile error did not clear: %08x", readback);

    // A non-1:1 geometry is rejected instead of silently bypassing/scaling.
    axi_write(6'h04, 32'h00f0_0140); // 320 x 240
    axi_write(6'h08, 32'd1280);
    axi_write(6'h1c, 32'h00f0_0140); // active size 320 x 240
    axi_write(6'h20, 32'd0);
    axi_write(6'h24, 32'd0);
    axi_write(6'h28, 32'd1);
    axi_write(6'h2c, 32'd1);
    axi_write(6'h00, CTRL_VDMA_XRGB_COMMIT);
    repeat (3) @(posedge aclk);
    axi_read(6'h18, readback);
    if (readback[4] !== 1'b1)
      $fatal(1, "non-1:1 geometry did not set ERROR_FLAGS[4]: %08x", readback);
    if (m_axis_video_tvalid !== 1'b0)
      $fatal(1, "non-1:1 geometry was not rejected fail-closed");

    $display("TEST_PASS: tb_video_pipeline_static_profile");
    $finish;
  end
endmodule
