`timescale 1ns/1ps
module tb_embedded_video_ip_7series_tx;
  localparam integer PIXEL_CLOCK_HZ=1000;
  localparam integer AUDIO_SAMPLE_RATE_HZ=4;
  localparam integer AUDIO_CLOCK_HZ=4*PIXEL_CLOCK_HZ;
  localparam integer H_TOTAL=180, H_ACTIVE_SIZE=80, H_SYNC_START=96;
  localparam integer HBLANK_PIXELS=H_TOTAL-H_ACTIVE_SIZE;
  localparam integer V_TOTAL=53, V_ACTIVE_SIZE=48;
  localparam integer FRAME_PIXELS=H_TOTAL*V_TOTAL;
  localparam integer EXPECTED_SAMPLES=(AUDIO_SAMPLE_RATE_HZ*FRAME_PIXELS+PIXEL_CLOCK_HZ/2)/PIXEL_CLOCK_HZ;
  localparam logic [2:0] MODE_CONTROL=3'd0, MODE_VIDEO=3'd1,
                         MODE_VIDEO_PREAMBLE=3'd2, MODE_VIDEO_GUARD=3'd4;

  logic pixel_clk=0, serial_clk=0, audio_pcm_clk=0, aresetn=0;
  logic [7:0] test_x=0;
  logic [9:0] line_index=0;
  integer frame_counter=0;
  logic [23:0] video_rgb;
  logic video_de, hsync, vsync;
  logic [31:0] audio_pcm_tdata=0;
  logic audio_pcm_tvalid=0, audio_pcm_tready;
  logic hdmi_mode_request=1, hdmi_audio_enable=0, audio_mute=0;
  logic [16:0] audio_gain_q15=17'd32768;
  logic tmds_tx_clk_p,tmds_tx_clk_n;
  logic [2:0] tmds_tx_data_p,tmds_tx_data_n;
  logic audio_underflow_event,audio_overflow_event;
  logic [31:0] audio_phase=0, audio_phase_sum;
  logic audio_sample_due;
  integer next_left_sample=1;
  integer accepted_samples_total=0;
  integer packet_start_total=0;
  integer color_seen=0;
  integer color_checks=0;
  integer frame_samples_out=0;
  integer frame_samples_in_start=0, frame_samples_in=0;
  integer measured_underflow=0, measured_overflow=0;
  integer vblank_line_prepares=0, vblank_packet_starts=0;
  logic measure_active=0;
  logic [9:0] ref_lane0,ref_lane1,ref_lane2;
  integer wait_cycles;
  integer audio_packet_starts_after_cancel=0;
  logic [9:0] expected_samples_word;
  integer video_boundary_state=0; // 0=等待前导，1=前导，2=保护带，3=活动视频
  integer video_preamble_symbols=0, video_guard_symbols=0;
  integer video_boundaries_checked=0;
  integer video_first_pixel_index=0;
  integer video_first_pixel_checks=0;
  integer video_first_pixel_error=0;
  logic [23:0] expected_video_rgb;
  logic [23:0] encoder_rgb_d1=24'd0, encoder_rgb_d2=24'd0, encoder_rgb_d3=24'd0;
  logic encoder_de_d1=1'b0, encoder_de_d2=1'b0, encoder_de_d3=1'b0;
  logic [23:0] bmp_frame [0:V_ACTIVE_SIZE-1][0:H_ACTIVE_SIZE-1];
  integer bmp_capture_enable=0;
  integer bmp_rows_captured=0;
  integer bmp_pixel_index=0;
  integer bmp_fd=0;

  always #10 pixel_clk=~pixel_clk;
  always #2 serial_clk=~serial_clk;
  always #2.5 audio_pcm_clk=~audio_pcm_clk;

  always_comb begin
    video_de=(line_index<V_ACTIVE_SIZE) && (test_x<H_ACTIVE_SIZE);
    hsync=(test_x>=H_SYNC_START && test_x<H_SYNC_START+16);
    vsync=(line_index>=49 && line_index<52);
    case (test_x)
      0: video_rgb=24'hFF0000; // 行首标记：红色
      1: video_rgb=24'h0000FF; // 行首标记：绿色（RBG打包）
      2: video_rgb=24'h00FF00; // 行首标记：蓝色（RBG打包）
      3: video_rgb=24'hFFFFFF; // 行首标记：白色
      default: video_rgb=24'h808080; // 其余像素固定灰色，便于观察行首过渡
    endcase
    audio_phase_sum=audio_phase+AUDIO_SAMPLE_RATE_HZ;
    audio_sample_due=(audio_phase_sum>=AUDIO_CLOCK_HZ);
  end

  always_ff @(posedge pixel_clk or negedge aresetn) begin
    if (!aresetn) begin
      test_x<=0;
      line_index<=0;
      frame_counter<=0;
    end else if (test_x==H_TOTAL-1) begin
      test_x<=0;
      if (line_index==V_TOTAL-1) begin
        line_index<=0;
        frame_counter<=frame_counter+1;
      end else begin
        line_index<=line_index+1'b1;
      end
    end else begin
      test_x<=test_x+1'b1;
    end
  end


  task automatic write_bmp_byte(input integer value);
    begin
      $fwrite(bmp_fd,"%c",value & 8'hFF);
    end
  endtask

  task automatic write_bmp_u16(input integer value);
    begin
      write_bmp_byte(value & 8'hFF);
      write_bmp_byte((value >> 8) & 8'hFF);
    end
  endtask

  task automatic write_bmp_u32(input integer value);
    begin
      write_bmp_byte(value & 8'hFF);
      write_bmp_byte((value >> 8) & 8'hFF);
      write_bmp_byte((value >> 16) & 8'hFF);
      write_bmp_byte((value >> 24) & 8'hFF);
    end
  endtask

  task automatic write_line_start_bmp;
    integer row, col, pad, image_bytes;
    logic [23:0] pixel;
    begin
      image_bytes = H_ACTIVE_SIZE * V_ACTIVE_SIZE * 3;
      pad = (4 - ((H_ACTIVE_SIZE * 3) % 4)) % 4;
      bmp_fd = $fopen("hdmi_tx_line_start.bmp","wb");
      if (bmp_fd == 0)
        $fatal(1,"无法创建 hdmi_tx_line_start.bmp");
      write_bmp_byte(8'h42); write_bmp_byte(8'h4D);
      write_bmp_u32(54 + image_bytes + pad * V_ACTIVE_SIZE);
      write_bmp_u16(0); write_bmp_u16(0); write_bmp_u32(54);
      write_bmp_u32(40); write_bmp_u32(H_ACTIVE_SIZE); write_bmp_u32(V_ACTIVE_SIZE);
      write_bmp_u16(1); write_bmp_u16(24); write_bmp_u32(0);
      write_bmp_u32(image_bytes + pad * V_ACTIVE_SIZE);
      write_bmp_u32(2835); write_bmp_u32(2835); write_bmp_u32(0); write_bmp_u32(0);
      for (row = V_ACTIVE_SIZE-1; row >= 0; row = row-1) begin
        for (col = 0; col < H_ACTIVE_SIZE; col = col+1) begin
          pixel = bmp_frame[row][col]; // TX输入为RBG；BMP要求B,G,R字节序
          write_bmp_byte(pixel[15:8]);
          write_bmp_byte(pixel[7:0]);
          write_bmp_byte(pixel[23:16]);
        end
        for (col = 0; col < pad; col = col+1)
          write_bmp_byte(0);
      end
      $fclose(bmp_fd);
      bmp_fd = 0;
      $display("BMP_PASS: hdmi_tx_line_start.bmp (%0dx%0d)",H_ACTIVE_SIZE,V_ACTIVE_SIZE);
    end
  endtask

  // AXI4-Stream源按48 kHz平均速率送出PCM立体声样本。
  always_ff @(posedge audio_pcm_clk or negedge aresetn) begin
    if (!aresetn) begin
      audio_phase<=0;
      audio_pcm_tvalid<=1'b0;
      audio_pcm_tdata<=0;
      next_left_sample<=1;
    end else begin
      if (audio_sample_due)
        audio_phase<=audio_phase_sum-AUDIO_CLOCK_HZ;
      else
        audio_phase<=audio_phase_sum;

      if (audio_sample_due && (!audio_pcm_tvalid || audio_pcm_tready)) begin
        audio_pcm_tvalid<=1'b1;
        audio_pcm_tdata<={16'h3456,16'(next_left_sample)};
        next_left_sample<=next_left_sample+1;
      end else if (audio_pcm_tvalid && audio_pcm_tready) begin
        audio_pcm_tvalid<=1'b0;
      end
    end
  end

  embedded_video_ip_7series_tx #(
    .ENABLE_HDMI_AUDIO(1'b1), .PIXEL_CLOCK_HZ(PIXEL_CLOCK_HZ),
    .AUDIO_SAMPLE_RATE_HZ(AUDIO_SAMPLE_RATE_HZ),
    .H_ACTIVE_SIZE(H_ACTIVE_SIZE), .HBLANK_PIXELS(HBLANK_PIXELS),
    .H_TOTAL(H_TOTAL), .H_SYNC_START(H_SYNC_START), .HSYNC_ACTIVE_LEVEL(1'b1),
    .ACR_N(512)
  ) dut (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .audio_pcm_clk(audio_pcm_clk),
    .aresetn(aresetn), .hdmi_mode_request(hdmi_mode_request),
    .video_rgb(video_rgb), .video_de(video_de),
    .hsync(hsync), .vsync(vsync), .audio_pcm_tdata(audio_pcm_tdata),
    .audio_pcm_tvalid(audio_pcm_tvalid), .audio_pcm_tready(audio_pcm_tready),
    .hdmi_audio_enable(hdmi_audio_enable), .audio_mute(audio_mute),
    .audio_gain_q15(audio_gain_q15), .tmds_tx_clk_p(tmds_tx_clk_p),
    .tmds_tx_clk_n(tmds_tx_clk_n), .tmds_tx_data_p(tmds_tx_data_p),
    .tmds_tx_data_n(tmds_tx_data_n), .audio_underflow_event(audio_underflow_event),
    .audio_overflow_event(audio_overflow_event)
  );

  // 直接实例化Digilent编码器，作为R/B/G通道重排和视频符号的参考。
  TMDS_Encoder ref_blue (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~dut.pixel_aresetn),
    .pDataOutRaw(ref_lane0), .pDataOut(dut.rgb_pipe[10][15:8]),
    .pC0(dut.hsync_pipe[10]), .pC1(dut.vsync_pipe[10]), .pVde(dut.de_pipe[10])
  );
  TMDS_Encoder ref_green (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~dut.pixel_aresetn),
    .pDataOutRaw(ref_lane1), .pDataOut(dut.rgb_pipe[10][7:0]),
    .pC0(1'b0), .pC1(1'b0), .pVde(dut.de_pipe[10])
  );
  TMDS_Encoder ref_red (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .aRst(~dut.pixel_aresetn),
    .pDataOutRaw(ref_lane2), .pDataOut(dut.rgb_pipe[10][23:16]),
    .pC0(1'b0), .pC1(1'b0), .pVde(dut.de_pipe[10])
  );

  always @(posedge audio_pcm_clk) begin
    if (aresetn && audio_pcm_tvalid && audio_pcm_tready)
      accepted_samples_total=accepted_samples_total+1;
    if (aresetn && audio_overflow_event)
      $fatal(1,"HDMI PCM通路不应把正常AXIS背压报告成overflow");
  end

  always @(posedge pixel_clk) begin
    // Track the RGB/DE values sampled by TMDS Encoder Stage 1. The 3-stage
    // mode pipe and Digilent's 3 registered encoder stages are observed after
    // the same edge; this history aligns the displayed symbol with its pixel.
    encoder_rgb_d1 <= dut.rgb_pipe[10];
    encoder_rgb_d2 <= encoder_rgb_d1;
    encoder_rgb_d3 <= encoder_rgb_d2;
    encoder_de_d1 <= dut.de_pipe[10];
    encoder_de_d2 <= encoder_de_d1;
    encoder_de_d3 <= encoder_de_d2;
    #1;
    if (aresetn && !dut.hdmi_mode_active) begin
      // DVI-safe startup is legal until the synchronized HDMI request takes effect.
      video_boundary_state=0;
    end else if (aresetn) begin
      if (bmp_capture_enable != 0 &&
          dut.u_hdmi_mode_mux.mode_pipe[2] == MODE_VIDEO) begin
        if (video_boundary_state == 2 && bmp_rows_captured < V_ACTIVE_SIZE) begin
          bmp_frame[bmp_rows_captured][0] =
              (encoder_de_d3 === 1'b1) ? encoder_rgb_d3 : 24'hFF00FF;
          bmp_pixel_index = 1;
          bmp_rows_captured = bmp_rows_captured + 1;
        end else if (video_boundary_state == 3 && bmp_rows_captured > 0 &&
                     bmp_pixel_index < H_ACTIVE_SIZE) begin
          bmp_frame[bmp_rows_captured-1][bmp_pixel_index] =
              (encoder_de_d3 === 1'b1) ? encoder_rgb_d3 : 24'hFF00FF;
          bmp_pixel_index = bmp_pixel_index + 1;
        end
      end
      case (dut.u_hdmi_mode_mux.mode_pipe[2])
        MODE_VIDEO_PREAMBLE: begin
          if ((video_boundary_state == 0) || (video_boundary_state == 3)) begin
            video_boundary_state = 1;
            video_preamble_symbols = 0;
            video_guard_symbols = 0;
            video_first_pixel_index = 0;
          end
          if (video_boundary_state != 1)
            $fatal(1,"视频前导未从空闲态开始");
          video_preamble_symbols = video_preamble_symbols + 1;
        end
        MODE_VIDEO_GUARD: begin
          if (video_boundary_state == 1) begin
            if (video_preamble_symbols != 8)
              $fatal(1,"视频前导应为8拍，实际=%0d",video_preamble_symbols);
            video_boundary_state = 2;
            video_guard_symbols = 0;
          end
          if (video_boundary_state != 2)
            $fatal(1,"未配对的视频保护带");
          video_guard_symbols = video_guard_symbols + 1;
        end
        MODE_VIDEO: begin
          if (video_boundary_state == 1)
            $fatal(1,"视频前导后缺少保护带");
          if (video_boundary_state == 2) begin
            if (video_guard_symbols != 2)
              $fatal(1,"视频保护带应为2拍，实际=%0d",video_guard_symbols);
            if (encoder_de_d3 !== 1'b1 || encoder_rgb_d3 !== 24'hFF0000) begin
              video_first_pixel_error = 1;
              $display("LINE_START_MISMATCH: first de=%b rgb=%06h",
                       encoder_de_d3,encoder_rgb_d3);
            end
            video_first_pixel_index = 1;
            video_first_pixel_checks = video_first_pixel_checks + 1;
            video_boundaries_checked = video_boundaries_checked + 1;
            video_boundary_state = 3;
          end else if (video_boundary_state == 3 && video_first_pixel_index < 4) begin
            case (video_first_pixel_index)
              1: expected_video_rgb = 24'h0000FF;
              2: expected_video_rgb = 24'h00FF00;
              default: expected_video_rgb = 24'hFFFFFF;
            endcase
            if (encoder_de_d3 !== 1'b1 || encoder_rgb_d3 !== expected_video_rgb) begin
              video_first_pixel_error = 1;
              $display("LINE_START_MISMATCH: pixel%0d de=%b expected=%06h actual=%06h",
                       video_first_pixel_index,encoder_de_d3,expected_video_rgb,encoder_rgb_d3);
            end
            video_first_pixel_index = video_first_pixel_index + 1;
            video_first_pixel_checks = video_first_pixel_checks + 1;
          end else if (video_boundary_state == 0) begin
            $fatal(1,"活动视频没有对应的视频前导/保护带");
          end
        end
        default: begin
          if (video_boundary_state == 2)
            $fatal(1,"视频保护带与首个活动视频符号之间出现控制/数据岛气泡");
          if (video_boundary_state == 3)
            video_boundary_state = 0;
        end
      endcase
    end
    if (aresetn && dut.packet_start) begin
      packet_start_total=packet_start_total+1;
      if (hdmi_audio_enable===1'b0 && dut.u_packet_assembler.active_header[7:0] == 8'h02)
        audio_packet_starts_after_cancel=audio_packet_starts_after_cancel+1;
      if (measure_active && line_index>=V_ACTIVE_SIZE)
        vblank_packet_starts=vblank_packet_starts+1;
    end
    if (aresetn && measure_active && dut.line_prepare && line_index>=V_ACTIVE_SIZE)
      vblank_line_prepares=vblank_line_prepares+1;

    if (measure_active && dut.packet_valid && dut.packet_ready &&
        dut.packet_header[7:0]==8'h02)
      frame_samples_out=frame_samples_out+$countones(dut.packet_header[11:8]);
    if (measure_active && audio_underflow_event)
      measured_underflow=measured_underflow+1;
    if (measure_active && audio_overflow_event)
      measured_overflow=measured_overflow+1;

    // 活动视频中间区域的三个TMDS通道必须与Digilent R/B/G参考编码一致。
    if (encoder_de_d3 && dut.u_hdmi_mode_mux.mode_pipe[2]==MODE_VIDEO) begin
      if (dut.tmds_lane0!==ref_lane0 || dut.tmds_lane1!==ref_lane1 || dut.tmds_lane2!==ref_lane2)
        $fatal(1,"TX顶层RGB颜色通道或活动视频TMDS符号错误");
      color_checks=color_checks+1;
      if (encoder_rgb_d3===24'hFF0000) color_seen=color_seen|1;
      if (encoder_rgb_d3===24'h0000FF) color_seen=color_seen|2;
      if (encoder_rgb_d3===24'h00FF00) color_seen=color_seen|4;
    end

    if (aresetn && dut.tmds_serializer_aresetn && !$isunknown({tmds_tx_clk_p,tmds_tx_clk_n}) &&
        (tmds_tx_clk_p===tmds_tx_clk_n))
      $fatal(1,"HDMI时钟差分对未互补");
    if (aresetn && dut.tmds_serializer_aresetn && !$isunknown({tmds_tx_data_p,tmds_tx_data_n}) &&
        ((tmds_tx_data_p ^ tmds_tx_data_n)!==3'b111))
      $fatal(1,"HDMI数据差分对未互补");
  end

  initial begin
    repeat(6) @(posedge pixel_clk);
    @(negedge pixel_clk); aresetn=1; hdmi_audio_enable=1;

    // 等待一个尚未启动的数据包，切路由前验证它会被安全取消。
    wait_cycles=0;
    while (!(dut.packet_loaded && dut.u_packet_assembler.active_header[7:0]==8'h02 &&
             !dut.packet_active) && wait_cycles<6000) begin
      @(posedge pixel_clk); wait_cycles=wait_cycles+1;
    end
    if (wait_cycles>=6000)
      $fatal(1,"未观察到待启动的PCM Audio Sample包");
    audio_packet_starts_after_cancel=0;
    @(negedge pixel_clk); hdmi_audio_enable=0;
    repeat(5) @(posedge pixel_clk);
    if (dut.packet_loaded || dut.packet_active || !dut.packet_cancel)
      $fatal(1,"HDMI禁用后未取消未启动的数据包");
    repeat(H_TOTAL*2) @(posedge pixel_clk);
    if (audio_packet_starts_after_cancel != 0)
      $fatal(1,"Cancelled audio packet started: count=%0d", audio_packet_starts_after_cancel);
    @(negedge pixel_clk); hdmi_audio_enable=1;

    // 等待路由重新稳定，再测量完整一帧；帧含48条活动行和5条垂直消隐行。
    wait(frame_counter>=3);
    @(negedge pixel_clk);
    bmp_rows_captured=0;
    bmp_pixel_index=0;
    bmp_capture_enable=1;
    frame_samples_out=0;
    measured_underflow=0;
    measured_overflow=0;
    vblank_line_prepares=0;
    vblank_packet_starts=0;
    frame_samples_in_start=accepted_samples_total;
    measure_active=1;
    wait(frame_counter>=4);
    @(negedge pixel_clk);
    measure_active=0;
    bmp_capture_enable=0;
    frame_samples_in=accepted_samples_total-frame_samples_in_start;
    if (bmp_rows_captured != V_ACTIVE_SIZE || bmp_pixel_index != H_ACTIVE_SIZE)
      $fatal(1,"BMP帧捕获尺寸错误：rows=%0d last_row_pixels=%0d",
             bmp_rows_captured,bmp_pixel_index);
    write_line_start_bmp();
    if (video_first_pixel_error != 0)
      $fatal(1,"行首前4像素与视频DE对齐检查失败；查看 hdmi_tx_line_start.bmp");

    if (frame_samples_out<EXPECTED_SAMPLES-1 || frame_samples_out>EXPECTED_SAMPLES+1)
      $fatal(1,"完整帧音频输出样本数错误：actual=%0d expected=%0d",frame_samples_out,EXPECTED_SAMPLES);
    if (frame_samples_in<EXPECTED_SAMPLES-1 || frame_samples_in>EXPECTED_SAMPLES+1)
      $fatal(1,"完整帧PCM输入样本数错误：actual=%0d expected=%0d",frame_samples_in,EXPECTED_SAMPLES);
    if (measured_underflow!=0 || measured_overflow!=0)
      $fatal(1,"稳定48k音频帧出现欠载/溢出：%0d/%0d",measured_underflow,measured_overflow);
    if (vblank_line_prepares<4 || vblank_packet_starts==0)
      $fatal(1,"VBlank没有持续产生逐行slot或数据包");
    if (color_seen!=7 || color_checks==0)
      $fatal(1,"纯红/绿/蓝颜色向量未覆盖或通道编码未检查：mask=%0d",color_seen);
    if (video_boundaries_checked < 10)
      $fatal(1,"视频前导/保护带边界检查次数不足：%0d",video_boundaries_checked);
    if (video_first_pixel_checks < 40)
      $fatal(1,"活动视频行首像素检查次数不足：%0d",video_first_pixel_checks);

    $display("TEST_PASS: embedded_video_ip_7series_tx, input=%0d output=%0d vblank_packets=%0d video_boundaries=%0d first_pixels=%0d",
             frame_samples_in,frame_samples_out,vblank_packet_starts,video_boundaries_checked,video_first_pixel_checks);
    $finish;
  end
endmodule
