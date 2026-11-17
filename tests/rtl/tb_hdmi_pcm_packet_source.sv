`timescale 1ns/1ps
module tb_hdmi_pcm_packet_source;
  logic pixel_clk=0, audio_pcm_clk=0, resetn=0;
  logic line_prepare=0, packet_active=0, packet_ready=1, hdmi_mode_active=1, vsync=0;
  logic [31:0] audio_pcm_tdata=0;
  logic audio_pcm_tvalid=0;
  logic audio_pcm_tready, hdmi_audio_enable=0, audio_mute=0;
  logic [16:0] audio_gain_q15=17'd32768;
  logic packet_valid, packet_cancel, packet_cancel_link, audio_underflow_event, audio_overflow_event;
  logic [23:0] packet_header;
  logic [55:0] packet_sub0,packet_sub1,packet_sub2,packet_sub3;
  logic static_disabled_ready, static_disabled_valid, static_disabled_cancel;
  logic static_disabled_underflow, static_disabled_overflow;
  logic [23:0] static_disabled_header;
  logic [55:0] static_disabled_sub0,static_disabled_sub1,static_disabled_sub2,static_disabled_sub3;
  integer sample_id;
  integer packet_count=0;
  integer samples_sent=0;
  integer next_sample_expected=1;
  integer samples_in_packet;
  integer sub_index;
  logic mask_done;
  integer underflow_count=0;
  integer avi_packet_count=0, acr_count=0, line_count=0;
  integer last_acr_line=-1, acr_interval_sum=0;
  integer wait_cycles;
  integer generated_lines=0;

  always #5 pixel_clk=~pixel_clk;
  always #1 audio_pcm_clk=~audio_pcm_clk;

  hdmi_pcm_packet_source #(
    .ENABLE_HDMI_AUDIO(1'b1), .PIXEL_CLOCK_HZ(100),
    .AUDIO_SAMPLE_RATE_HZ(4), .FIFO_ADDR_WIDTH(3), .ACR_N(512),
    .H_TOTAL(25)
  ) dut (
    .pixel_clk(pixel_clk), .audio_pcm_clk(audio_pcm_clk),
    .pixel_aresetn(resetn), .audio_pcm_aresetn(resetn),
    .hdmi_mode_active(hdmi_mode_active), .vsync(vsync), .line_prepare(line_prepare), .packet_active(packet_active),
    .audio_pcm_tdata(audio_pcm_tdata), .audio_pcm_tvalid(audio_pcm_tvalid),
    .audio_pcm_tready(audio_pcm_tready), .hdmi_audio_enable(hdmi_audio_enable),
    .audio_mute(audio_mute), .audio_gain_q15(audio_gain_q15),
    .packet_ready(packet_ready), .packet_valid(packet_valid), .packet_cancel(packet_cancel), .packet_cancel_link(packet_cancel_link),
    .packet_header(packet_header),
    .packet_sub0(packet_sub0), .packet_sub1(packet_sub1), .packet_sub2(packet_sub2),
    .packet_sub3(packet_sub3), .audio_underflow_event(audio_underflow_event),
    .audio_overflow_event(audio_overflow_event)
  );

  hdmi_pcm_packet_source #(
    .ENABLE_HDMI_AUDIO(1'b0), .PIXEL_CLOCK_HZ(100),
    .AUDIO_SAMPLE_RATE_HZ(4), .FIFO_ADDR_WIDTH(3), .ACR_N(512),
    .H_TOTAL(25)
  ) static_disabled (
    .pixel_clk(pixel_clk), .audio_pcm_clk(audio_pcm_clk),
    .pixel_aresetn(resetn), .audio_pcm_aresetn(resetn),
    .hdmi_mode_active(hdmi_mode_active), .vsync(vsync), .line_prepare(line_prepare), .packet_active(packet_active),
    .audio_pcm_tdata(audio_pcm_tdata), .audio_pcm_tvalid(audio_pcm_tvalid),
    .audio_pcm_tready(static_disabled_ready), .hdmi_audio_enable(hdmi_audio_enable),
    .audio_mute(audio_mute), .audio_gain_q15(audio_gain_q15),
    .packet_ready(packet_ready), .packet_valid(static_disabled_valid), .packet_cancel(static_disabled_cancel),
    .packet_cancel_link(), .packet_header(static_disabled_header), .packet_sub0(static_disabled_sub0),
    .packet_sub1(static_disabled_sub1), .packet_sub2(static_disabled_sub2),
    .packet_sub3(static_disabled_sub3),
    .audio_underflow_event(static_disabled_underflow),
    .audio_overflow_event(static_disabled_overflow)
  );

  always_ff @(posedge pixel_clk or negedge resetn) begin
    if (!resetn) packet_active <= 1'b0;
    else packet_active <= packet_valid || static_disabled_valid;
  end

  // 按固定行节拍触发音频包源。
  initial begin
    forever begin
      @(negedge pixel_clk);
      line_prepare=1;
      vsync=((generated_lines % 5)==0);
      generated_lines=generated_lines+1;
      @(negedge pixel_clk); line_prepare=0; vsync=0;
      repeat(23) @(negedge pixel_clk);
    end
  end

  always @(posedge pixel_clk) begin
    if (resetn && line_prepare) line_count = line_count + 1;
    if (packet_valid && packet_ready && packet_header[7:0]==8'h01) begin
      if (last_acr_line >= 0) begin
        if ((line_count - last_acr_line) != 4)
          $fatal(1,"ACR packet did not start on its target line: interval=%0d",
                 line_count - last_acr_line);
        acr_interval_sum = acr_interval_sum + line_count - last_acr_line;
      end
      last_acr_line = line_count;
      acr_count = acr_count + 1;
    end
    if (packet_valid && packet_ready && packet_header[7:0]==8'h82) begin
      if (packet_header[15:8] !== 8'h02 || packet_header[23:16] !== 8'h0D ||
          packet_sub0 !== 56'h0000010818202E ||
          {packet_sub3,packet_sub2,packet_sub1} !== 168'd0)
        $fatal(1,"AVI InfoFrame does not match the fixed VIC 1/full-range profile");
      avi_packet_count = avi_packet_count + 1;
    end
    if (static_disabled_valid && static_disabled_header[7:0] == 8'h82 &&
        (static_disabled_header[15:8] !== 8'h02 ||
         static_disabled_header[23:16] !== 8'h0D ||
         static_disabled_sub0 !== 56'h0000010818202E ||
         {static_disabled_sub3,static_disabled_sub2,static_disabled_sub1} !== 168'd0))
      $fatal(1,"audio-off profile must still send the AVI InfoFrame");
    if (packet_valid && packet_ready && packet_header[7:0]==8'h02) begin
      packet_count <= packet_count + 1;
      samples_in_packet=0;
      mask_done=0;
      for (sub_index=0;sub_index<4;sub_index=sub_index+1) begin
        if (packet_header[8+sub_index]) begin
          if (mask_done) $fatal(1,"sample_present位必须从低位连续置位");
          samples_in_packet=samples_in_packet+1;
          case (sub_index)
            0: if (packet_sub0[23:0] !== {next_sample_expected[15:0],8'h00} ||
                  packet_sub0[47:24] !== 24'h006500) $fatal(1,"PCM子包0数据错误");
            1: if (packet_sub1[23:0] !== {next_sample_expected[15:0],8'h00} ||
                  packet_sub1[47:24] !== 24'h006500) $fatal(1,"PCM子包1数据错误");
            2: if (packet_sub2[23:0] !== {next_sample_expected[15:0],8'h00} ||
                  packet_sub2[47:24] !== 24'h006500) $fatal(1,"PCM子包2数据错误");
            3: if (packet_sub3[23:0] !== {next_sample_expected[15:0],8'h00} ||
                  packet_sub3[47:24] !== 24'h006500) $fatal(1,"PCM子包3数据错误");
          endcase
          next_sample_expected=next_sample_expected+1;
        end else begin
          mask_done=1;
        end
      end
      samples_sent=samples_sent+samples_in_packet;
    end
    if (audio_underflow_event)
      underflow_count <= underflow_count + 1;
    if (audio_overflow_event)
      $fatal(1,"AXI正常背压不应触发内部overflow");
    if (static_disabled_cancel || static_disabled_underflow || static_disabled_overflow)
      $fatal(1,"静态禁用音频profile不应生成音频取消或错误事件");
  end

  task automatic send_one_sample(input integer id);
    begin
      repeat(125) @(negedge audio_pcm_clk);
      audio_pcm_tdata = {16'd101,16'(id)};
      audio_pcm_tvalid = 1'b1;
      do @(posedge audio_pcm_clk); while (!audio_pcm_tready);
      @(negedge audio_pcm_clk); audio_pcm_tvalid=1'b0;
    end
  endtask

  initial begin
    repeat(4) @(posedge pixel_clk);
    @(negedge pixel_clk); resetn=1; audio_pcm_tvalid=1; audio_pcm_tdata=32'h0001_0001;
    repeat(6) begin
      @(posedge audio_pcm_clk);
      if (!audio_pcm_tready || !static_disabled_ready)
        $fatal(1,"HDMI禁用时TREADY必须保持为1并丢弃输入");
    end
    @(negedge audio_pcm_clk); audio_pcm_tvalid=0; hdmi_audio_enable=1;
    send_one_sample(1);
    send_one_sample(2);
    send_one_sample(3);
    send_one_sample(4);

    wait_cycles=0;
    while (samples_sent<4 && wait_cycles<1000) begin
      @(posedge pixel_clk); wait_cycles=wait_cycles+1;
    end
    if (samples_sent!=4 || packet_count<1)
      $fatal(1,"sample节拍器未按48kHz累计发送4个帧：packets=%0d samples=%0d",packet_count,samples_sent);

    // 音频稳定启动后停止数据源，连续缺少样本应触发欠载事件。
    wait_cycles=0;
    while (underflow_count==0 && wait_cycles<400) begin
      @(posedge pixel_clk); wait_cycles=wait_cycles+1;
    end
    if (underflow_count==0)
      $fatal(1,"启动稳定音频后，sample-debt欠载检测未触发");

    @(negedge audio_pcm_clk); hdmi_audio_enable=0; audio_pcm_tvalid=1;
    repeat(8) begin
      @(posedge audio_pcm_clk);
      if (!audio_pcm_tready)
        $fatal(1,"运行时关闭HDMI音频后TREADY必须为1");
    end
    if (avi_packet_count == 0 || acr_count < 2 ||
        acr_interval_sum / (acr_count - 1) != 4)
      $fatal(1,"AVI cadence or fractional ACR cadence missing: avi=%0d acr=%0d avg_lines=%0d",
             avi_packet_count, acr_count,
             acr_interval_sum / ((acr_count > 1) ? (acr_count - 1) : 1));
    $display("TEST_PASS: hdmi_pcm_packet_source, packets=%0d samples=%0d underflow=%0d acr=%0d",packet_count,samples_sent,underflow_count,acr_count);
    $finish;
  end
endmodule
