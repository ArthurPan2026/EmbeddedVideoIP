`timescale 1ns/1ps
module tb_hdmi_line_slot_scheduler;
  localparam logic [15:0] H_TOTAL=16'd4400, H_SYNC_START=16'd4100;
  logic [15:0] active_size=16'd3840;
  localparam logic [2:0] MODE_CONTROL=3'd0, MODE_VIDEO=3'd1,
                         MODE_VIDEO_PREAMBLE=3'd2, MODE_DATA_PREAMBLE=3'd3,
                         MODE_VIDEO_GUARD=3'd4, MODE_DATA_GUARD=3'd5,
                         MODE_DATA_PAYLOAD=3'd6;
  logic pixel_clk=0, aresetn=0;
  logic hdmi_mode_request=0, hdmi_mode_active_high, hdmi_mode_active_low;
  logic packet_active=0;
  logic [15:0] test_x=0;
  logic [3:0] line_index=0;
  logic hsync_high, hsync_low;
  logic raw_de, delayed_de;
  logic packet_loaded=0, packet_offer=0, packet_cancel=0;
  logic prep_high, prep_low, start_high, start_low;
  logic [2:0] mode_high, mode_low;
  integer prepare_events=0, packet_starts=0;
  integer prepare_events_before_reset=0;
  integer control_run_length=0;
  logic extended_control_seen=0;
  integer cycles;
  logic current_line_active, next_line_active;

  always #5 pixel_clk=~pixel_clk;
  always_comb begin
    hsync_high=(test_x>=H_SYNC_START && test_x<H_SYNC_START+12);
    hsync_low=~hsync_high;
    current_line_active=(line_index==4'd2 || line_index==4'd3 || line_index==4'd6);
    next_line_active=(line_index==4'd1 || line_index==4'd2 || line_index==4'd5);
    delayed_de=current_line_active && (test_x<active_size);
    raw_de=(current_line_active && test_x<30) || (next_line_active && test_x>=H_TOTAL-10);
  end

  always_ff @(posedge pixel_clk or negedge aresetn) begin
    if (!aresetn) begin
      test_x<=0;
      line_index<=0;
    end else if (test_x==H_TOTAL-1) begin
      test_x<=0;
      line_index<=line_index+1'b1;
    end else begin
      test_x<=test_x+1'b1;
    end
  end

  hdmi_line_slot_scheduler #(.VIDEO_LOOKAHEAD_CYCLES(10), .H_COUNT_WIDTH(16)) dut_high (
    .pixel_clk(pixel_clk), .aresetn(aresetn),
    .h_total(H_TOTAL), .h_active_size(active_size), .h_sync_start(H_SYNC_START),
    .hsync_active_level(1'b1),
    .hdmi_mode_request(hdmi_mode_request), .video_profile_valid(1'b1), .hdmi_mode_active(hdmi_mode_active_high),
    .packet_active(packet_active),
    .video_de_lookahead(raw_de), .video_de_delayed(delayed_de),
    .hsync_delayed(hsync_high), .packet_loaded(packet_loaded),
    .packet_offer(packet_offer), .packet_cancel(packet_cancel),
    .line_prepare(prep_high), .symbol_mode(mode_high), .packet_start(start_high)
  );

  hdmi_line_slot_scheduler #(.VIDEO_LOOKAHEAD_CYCLES(10), .H_COUNT_WIDTH(16)) dut_low (
    .pixel_clk(pixel_clk), .aresetn(aresetn),
    .h_total(H_TOTAL), .h_active_size(active_size), .h_sync_start(H_SYNC_START),
    .hsync_active_level(1'b0),
    .hdmi_mode_request(hdmi_mode_request), .video_profile_valid(1'b1),
    .hdmi_mode_active(hdmi_mode_active_low),
    .packet_active(packet_active),
    .video_de_lookahead(raw_de), .video_de_delayed(delayed_de),
    .hsync_delayed(hsync_low), .packet_loaded(packet_loaded),
    .packet_offer(packet_offer), .packet_cancel(packet_cancel),
    .line_prepare(prep_low), .symbol_mode(mode_low), .packet_start(start_low)
  );

  always @(posedge pixel_clk) begin
    if (aresetn) begin
      #1;
      if (dut_high.x_count !== dut_low.x_count || prep_high !== prep_low ||
          mode_high !== mode_low || start_high !== start_low ||
          hdmi_mode_active_high !== hdmi_mode_active_low)
        $fatal(1,"HSYNC正/负极性同步结果不一致");
      if (prep_high) begin
        prepare_events=prepare_events+1;
        if (dut_high.x_count!==active_size-16'd20)
          $fatal(1,"line_prepare不在每行准备点触发");
      end
      if (hdmi_mode_active_high && !delayed_de && mode_high===MODE_CONTROL) begin
        if (control_run_length < 32)
          control_run_length=control_run_length+1;
        if (control_run_length >= 32)
          extended_control_seen=1;
      end else begin
        control_run_length=0;
      end
      if (start_high) begin
        packet_starts=packet_starts+1;
        if (dut_high.x_count!==H_SYNC_START+12+8+2-1)
          $fatal(1,"数据包未在前保护带最后一拍启动");
      end
      if (dut_high.timing_locked && hdmi_mode_active_high && (packet_loaded || packet_offer) && !delayed_de && !raw_de) begin
        if (dut_high.x_count>=H_SYNC_START+12 && dut_high.x_count<H_SYNC_START+20 &&
            mode_high!==MODE_DATA_PREAMBLE)
          $fatal(1,"VBlank扫描行缺少数据岛前导");
        if (dut_high.x_count>=H_SYNC_START+20 && dut_high.x_count<H_SYNC_START+22 &&
            mode_high!==MODE_DATA_GUARD)
          $fatal(1,"数据岛前保护带拍数错误");
        if (dut_high.x_count>=H_SYNC_START+22 && dut_high.x_count<H_SYNC_START+54 &&
            mode_high!==MODE_DATA_PAYLOAD)
          $fatal(1,"数据岛未连续输出32拍负载");
        if (dut_high.x_count>=H_SYNC_START+54 && dut_high.x_count<H_SYNC_START+56 &&
            mode_high!==MODE_DATA_GUARD)
          $fatal(1,"数据岛尾保护带拍数错误");
      end
    end
  end

  initial begin
    repeat(3) @(posedge pixel_clk);
    @(negedge pixel_clk); aresetn=1; hdmi_mode_request=1;
    wait (hdmi_mode_active_high && hdmi_mode_active_low);
    @(negedge pixel_clk); packet_loaded=1;
    // HDMI mode: 运行活动行和垂直消隐行，VDE低时仍应逐行提供 packet slot。
    repeat(H_TOTAL*7+30) @(posedge pixel_clk);
    if (prepare_events<5)
      $fatal(1,"活动区与VBlank行的line_prepare数量不足：%0d",prepare_events);
    if (packet_starts<5)
      $fatal(1,"VBlank期间没有持续插入数据包：%0d",packet_starts);
    if (!extended_control_seen)
      $fatal(1,"HDMI blanking did not provide a 32-character extended control period");

    // DVI mode must pass only TMDS video/control and never schedule HDMI guard bands or islands.
    @(negedge pixel_clk); packet_loaded=0; hdmi_mode_request=0;
    wait (!hdmi_mode_active_high && !hdmi_mode_active_low);
    repeat(H_TOTAL*2) begin
      @(posedge pixel_clk); #1;
      if (delayed_de && mode_high!==MODE_VIDEO)
        $fatal(1,"DVI活动区必须只输出TMDS视频编码");
      if (!delayed_de && mode_high!==MODE_CONTROL)
        $fatal(1,"DVI消隐区不得插入HDMI前导、保护带或数据岛");
    end
    @(negedge pixel_clk); hdmi_mode_request=1; packet_loaded=0;
    wait (hdmi_mode_active_high && hdmi_mode_active_low);
    @(negedge pixel_clk); packet_loaded=1;

    // 异步复位后应重新等待HSYNC边沿以建立行相位。
    prepare_events_before_reset=prepare_events;
    @(negedge pixel_clk); packet_loaded=0; aresetn=0; active_size=16'd1280;
    repeat(2) @(posedge pixel_clk);
    @(negedge pixel_clk); aresetn=1;
    wait (hdmi_mode_active_high && hdmi_mode_active_low);
    @(negedge pixel_clk); packet_loaded=1;
    repeat(H_TOTAL+80) @(posedge pixel_clk);
    if (!dut_high.timing_locked || !dut_low.timing_locked)
      $fatal(1,"复位后未重新锁定HSYNC边沿");
    if (prepare_events <= prepare_events_before_reset)
      $fatal(1,"reset后未根据新的profile宽度更新line_prepare坐标");
    $display("TEST_PASS: hdmi_line_slot_scheduler, prepare=%0d packets=%0d",prepare_events,packet_starts);
    $finish;
  end
endmodule
