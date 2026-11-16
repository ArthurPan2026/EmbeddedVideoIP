`timescale 1ns/1ps
module tb_video_pipeline_v1_0;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;

  logic [31:0] bram_dout=0;
  logic [31:0] bram_mem[0:3];
  wire bram_en;
  wire [3:0] bram_addr;
  wire bram_busy, bram_done;

  logic [31:0] hls_data=0;
  logic hls_valid=0, hls_user=0, hls_last=0;
  wire hls_ready;
  logic [31:0] vdma_data=0;
  logic vdma_valid=0, vdma_user=0, vdma_last=0;
  wire vdma_ready;
  wire [23:0] video_data;
  wire video_valid, video_user, video_last;
  logic video_ready=1;
  wire hdmi_audio_enable, audio_mute;
  wire [16:0] audio_gain_q15;
  logic audio_underflow=0, audio_overflow=0;

  logic [5:0] awaddr=0, araddr=0;
  logic awvalid=0, wvalid=0, bready=0, arvalid=0, rready=0;
  logic [31:0] wdata=0;
  logic [3:0] wstrb=4'hf;
  wire awready, wready, bvalid, arready, rvalid;
  wire [1:0] bresp, rresp;
  wire [31:0] rdata;

  logic [23:0] expected[0:15];
  integer output_index=0;
  integer cycles=0;
  logic stalled=0;
  logic bram_done_seen=0;
  logic [23:0] held_data;
  logic held_user, held_last;

  video_pipeline_v1_0 #(
    .MAX_INPUT_WIDTH(4),.MAX_INPUT_HEIGHT(4),
    .OUTPUT_WIDTH(4),.OUTPUT_HEIGHT(4),
    .BRAM_ADDR_WIDTH(4),.AXI_ADDR_WIDTH(6),.ENABLE_HDMI_AUDIO(1)
  ) dut (
    .aclk(clk),.aresetn(rst_n),
    .bram_en(bram_en),.bram_addr(bram_addr),.bram_dout(bram_dout),
    .bram_busy(bram_busy),.bram_frame_done(bram_done),
    .s_axis_hls_tdata(hls_data),.s_axis_hls_tvalid(hls_valid),
    .s_axis_hls_tready(hls_ready),.s_axis_hls_tuser(hls_user),.s_axis_hls_tlast(hls_last),
    .s_axis_vdma_tdata(vdma_data),.s_axis_vdma_tvalid(vdma_valid),
    .s_axis_vdma_tready(vdma_ready),.s_axis_vdma_tuser(vdma_user),.s_axis_vdma_tlast(vdma_last),
    .m_axis_video_tdata(video_data),.m_axis_video_tvalid(video_valid),
    .m_axis_video_tready(video_ready),.m_axis_video_tuser(video_user),.m_axis_video_tlast(video_last),
    .s_axi_awaddr(awaddr),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
    .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
    .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
    .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
    .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
    .hdmi_audio_enable(hdmi_audio_enable),.audio_mute(audio_mute),
    .audio_gain_q15(audio_gain_q15),.audio_underflow(audio_underflow),.audio_overflow(audio_overflow)
  );

  always @(posedge clk) begin
    cycles <= cycles+1;
    video_ready <= (cycles%5 != 1);
    if (bram_en)
      bram_dout <= bram_mem[bram_addr];
    if (bram_done)
      bram_done_seen <= 1'b1;
    if(video_valid && !video_ready) begin
      if(stalled && ((video_data!==held_data)||(video_user!==held_user)||(video_last!==held_last)))
        $fatal(1,"TEST_FAIL: top output changed under 下游背压");
      stalled<=1;
      held_data<=video_data; held_user<=video_user; held_last<=video_last;
    end else if(video_valid && video_ready) begin
      stalled<=0;
      if(output_index>=16) $fatal(1,"TEST_FAIL: 顶层输出了多余像素");
      if(video_data!==expected[output_index])
        $fatal(1,"TEST_FAIL: 顶层像素%0d为%h，预期为%h",output_index,video_data,expected[output_index]);
      if(video_user!==(output_index==0)) $fatal(1,"TEST_FAIL: 顶层帧首标记不匹配");
      if(video_last!==((output_index%4)==3)) $fatal(1,"TEST_FAIL: 顶层行尾标记不匹配");
      output_index<=output_index+1;
    end
  end

  task automatic axi_write(input logic [5:0] address,
                           input logic [31:0] value,
                           input logic aw_first);
    begin
      if(aw_first) begin
        @(negedge clk); awaddr=address; awvalid=1;
        do @(posedge clk); while(!awready);
        @(negedge clk); awvalid=0;
        repeat(2) @(negedge clk);
        wdata=value; wvalid=1;
        do @(posedge clk); while(!wready);
        @(negedge clk); wvalid=0; bready=1;
      end else begin
        @(negedge clk); wdata=value; wvalid=1;
        do @(posedge clk); while(!wready);
        @(negedge clk); wvalid=0;
        repeat(2) @(negedge clk);
        awaddr=address; awvalid=1;
        do @(posedge clk); while(!awready);
        @(negedge clk); awvalid=0; bready=1;
      end
      do @(posedge clk); while(!bvalid);
      @(negedge clk); bready=0;
    end
  endtask

  task automatic axi_read(input logic [5:0] address, output logic [31:0] value);
    begin
      @(negedge clk); araddr=address; arvalid=1;
      do @(posedge clk); while(!arready);
      @(negedge clk); arvalid=0; rready=1;
      do @(posedge clk); while(!rvalid);
      value=rdata;
      @(negedge clk); rready=0;
    end
  endtask

  task automatic send_pixel(input logic [23:0] pixel,input logic sof,input logic eol);
    begin
      @(negedge clk); vdma_data={8'd0,pixel}; vdma_user=sof; vdma_last=eol; vdma_valid=1;
      do @(posedge clk); while(!vdma_ready);
      @(negedge clk); vdma_valid=0; vdma_user=0; vdma_last=0;
    end
  endtask


  task automatic send_hls_pixel(input logic [23:0] pixel,input logic sof,input logic eol);
    begin
      @(negedge clk); hls_data={8'd0,pixel}; hls_user=sof; hls_last=eol; hls_valid=1;
      do @(posedge clk); while(!hls_ready);
      @(negedge clk); hls_valid=0; hls_user=0; hls_last=0;
    end
  endtask

  task automatic send_hls_frame;
    begin
      send_hls_pixel(24'hFF0000,1,0); // red in RBG stream order
      send_hls_pixel(24'h0000FF,0,1); // green in RBG stream order
      send_hls_pixel(24'h00FF00,0,0); // blue in RBG stream order
      send_hls_pixel(24'hFFFFFF,0,1);
    end
  endtask

  task automatic send_xrgb_vdma_frame;
    begin
      // XRGB内存像素按0x00RRGGBB表示；AXI视频输出按RBG顺序打包。
      send_pixel(24'h112233,1,0);
      send_pixel(24'h445566,0,1);
      send_pixel(24'h778899,0,0);
      send_pixel(24'hAABBCC,0,1);
    end
  endtask

  task automatic send_frame;
    begin
      send_pixel(24'hFF0000,1,0); // red in RBG stream order
      send_pixel(24'h0000FF,0,1); // green in RBG stream order
      send_pixel(24'h00FF00,0,0); // blue in RBG stream order
      send_pixel(24'hFFFFFF,0,1);
    end
  endtask

  logic [31:0] readback;
  initial begin
    #1ms;
    $fatal(1,"TEST_FAIL: 顶层看门狗超时");
  end

  initial begin
    bram_mem[0]=32'h07E0F800;
    bram_mem[1]=32'hFFFF001F;
    bram_mem[2]=32'd0;
    bram_mem[3]=32'd0;
    expected[0]=24'hFF0000; expected[1]=24'hFF0000; expected[2]=24'h0000FF; expected[3]=24'h0000FF;
    expected[4]=24'hFF0000; expected[5]=24'hFF0000; expected[6]=24'h0000FF; expected[7]=24'h0000FF;
    expected[8]=24'h00FF00; expected[9]=24'h00FF00; expected[10]=24'hFFFFFF; expected[11]=24'hFFFFFF;
    expected[12]=24'h00FF00; expected[13]=24'h00FF00; expected[14]=24'hFFFFFF; expected[15]=24'hFFFFFF;

    repeat(4) @(negedge clk);
    rst_n=1;
    // 先写W再写AW，验证AXI-Lite写通道可独立握手。
    axi_write(6'h04,32'h0002_0002,0);
    axi_write(6'h1c,32'h0004_0004,1);
    axi_write(6'h20,32'h0000_0000,0);
    axi_write(6'h24,32'h0000_0000,1);
    axi_write(6'h28,32'h0002_0000,0);
    axi_write(6'h2c,32'h0002_0000,1);
    // 先写AW再写W，并提交源、格式、缩放和使能配置。
    axi_write(6'h00,32'h0000_013d,1);
    axi_read(6'h04,readback);
    if(readback!==32'h0002_0002) $fatal(1,"TEST_FAIL: AXI-Lite尺寸读回值不匹配：%h",readback);
    repeat(4) @(negedge clk);
    send_frame();
    wait(dut.cfg_frame_count==1);
    if(output_index!=16) $fatal(1,"TEST_FAIL: 顶层输出像素数为%0d",output_index);
    axi_read(6'h10,readback);
    if(readback[7:6]!==2'd2) $fatal(1,"TEST_FAIL: 活动视频源不是VDMA：%h",readback);

    // HLS视频源通过相同的AXI4-Stream Video源选择器输入。
    @(negedge clk); output_index=0;
    axi_write(6'h00,32'h0000_013b,0); // HLS源、RGB888、最近邻/拉伸、提交并使能
    repeat(4) @(negedge clk);
    send_hls_frame();
    wait(dut.cfg_frame_count==2);
    if(output_index!=16) $fatal(1,"TEST_FAIL: HLS源输出像素数为%0d",output_index);
    axi_read(6'h10,readback);
    if(readback[7:6]!==2'd1) $fatal(1,"TEST_FAIL: 活动视频源不是HLS：%h",readback);

    // XRGB memory containers are RGB internally; the public stream output is RBG.
    expected[0]=24'h113322; expected[1]=24'h113322; expected[2]=24'h446655; expected[3]=24'h446655;
    expected[4]=24'h113322; expected[5]=24'h113322; expected[6]=24'h446655; expected[7]=24'h446655;
    expected[8]=24'h779988; expected[9]=24'h779988; expected[10]=24'hAACCBB; expected[11]=24'hAACCBB;
    expected[12]=24'h779988; expected[13]=24'h779988; expected[14]=24'hAACCBB; expected[15]=24'hAACCBB;
    @(negedge clk); output_index=0;
    axi_write(6'h00,32'h0000_014d,1); // VDMA源使用XRGB8888内存格式
    repeat(4) @(negedge clk);
    send_xrgb_vdma_frame();
    wait(dut.cfg_frame_count==3);
    if(output_index!=16) $fatal(1,"TEST_FAIL: XRGB VDMA源输出像素数为%0d",output_index);
    axi_read(6'h10,readback);
    if(readback[7:6]!==2'd2) $fatal(1,"TEST_FAIL: 活动视频源不是XRGB VDMA：%h",readback);

    // BRAM读取器从一个同步32-bit字中拆出两个RGB565像素。
    expected[0]=24'hFF0000; expected[1]=24'hFF0000; expected[2]=24'h0000FF; expected[3]=24'h0000FF;
    expected[4]=24'hFF0000; expected[5]=24'hFF0000; expected[6]=24'h0000FF; expected[7]=24'h0000FF;
    expected[8]=24'h00FF00; expected[9]=24'h00FF00; expected[10]=24'hFFFFFF; expected[11]=24'hFFFFFF;
    expected[12]=24'h00FF00; expected[13]=24'h00FF00; expected[14]=24'hFFFFFF; expected[15]=24'hFFFFFF;
    @(negedge clk); output_index=0;
    axi_write(6'h08,32'd4,1);
    axi_write(6'h0c,32'd0,0);
    axi_write(6'h00,32'h0000_0339,1); // BRAM源、单帧读取请求并提交
    repeat(4) @(negedge clk);
    wait(dut.cfg_frame_count==4);
    if(output_index!=16 || !bram_done_seen) $fatal(1,"TEST_FAIL: BRAM源输出或状态不匹配");
    axi_read(6'h10,readback);
    if(readback[7:6]!==2'd0) $fatal(1,"TEST_FAIL: 活动视频源不是BRAM：%h",readback);
    axi_read(6'h18,readback);
    if(readback!==0) $fatal(1,"TEST_FAIL: 顶层出现意外错误：%h",readback);

    // HDMI音频控制与视频核共用AXI-Lite地址空间。
    axi_read(6'h38, readback);
    if (readback !== 32'd32768 || audio_gain_q15 !== 17'd32768)
      $fatal(1, "TEST_FAIL: HDMI音频增益复位值不匹配");
    axi_write(6'h34, 32'd3, 1); // 使能HDMI音频并静音
    if (hdmi_audio_enable !== 1'b1 || audio_mute !== 1'b1)
      $fatal(1, "TEST_FAIL: HDMI音频使能/静音控制不匹配");
    axi_write(6'h34, 32'd1, 0);
    if (hdmi_audio_enable !== 1'b1 || audio_mute !== 1'b0)
      $fatal(1, "TEST_FAIL: 修改静音时改变了HDMI音频使能");
    axi_write(6'h38, 32'd40000, 1);
    axi_read(6'h38, readback);
    if (readback !== 32'd32768 || audio_gain_q15 !== 17'd32768)
      $fatal(1, "TEST_FAIL: HDMI音频增益未饱和到unity");
    @(negedge clk); audio_underflow = 1'b1; audio_overflow = 1'b1;
    @(negedge clk); audio_underflow = 1'b0; audio_overflow = 1'b0;
    axi_read(6'h3c, readback);
    if (readback[2:0] !== 3'b111)
      $fatal(1, "TEST_FAIL: HDMI音频状态未锁存使能/欠载/溢出");
    axi_write(6'h00, 32'h0000_0400, 1); // 通过CTRL bit10清除音频sticky状态
    axi_read(6'h3c, readback);
    if (readback[2:0] !== 3'b001)
      $fatal(1, "TEST_FAIL: CTRL清错未清除音频FIFO状态");

    $display("TEST_PASS: tb_video_pipeline_v1_0");
    $finish;
  end
endmodule
