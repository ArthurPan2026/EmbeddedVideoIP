`timescale 1ns/1ps
module tb_hdmi_pcm_packet_source;
  localparam integer PIXEL_CLOCK_HZ = 8_000_000;
  localparam integer AUDIO_SAMPLE_RATE_HZ = 48_000;
  localparam integer H_TOTAL = 100;
  localparam integer FIFO_DEPTH = 16;

  logic pixel_clk=0, audio_pcm_clk=0, resetn=0;
  logic line_prepare=0, packet_active=0, packet_ready=1, hdmi_mode_active=1, vsync=0;
  logic [31:0] pixel_clock_hz=PIXEL_CLOCK_HZ, h_total=H_TOTAL;
  logic [7:0] video_vic=8'd1;
  logic [47:0] audio_pcm_tdata=0;
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
  logic force_packet_stall=0, random_stalls=0, scoreboard_enable=1, acr_cadence_check=1;
  logic [23:0] expected_left [0:255];
  logic [23:0] expected_right [0:255];
  integer expected_write=0, expected_read=0;
  integer scoreboard_samples_sent=0;
  integer line_phase=0, generated_lines=0, line_count=0;
  integer packet_count=0, samples_in_packet=0, sub_index=0;
  integer underflow_count=0, avi_packet_count=0, infoframe_count=0, acr_count=0;
  integer last_acr_line=-1;
  integer target_samples, wait_cycles, i, timeout;
  integer transmitted_this_packet;
  logic [3:0] mask_seen;
  logic seen_zero;
  logic accepted;

  always #5 pixel_clk=~pixel_clk;
  always #1 audio_pcm_clk=~audio_pcm_clk;

  hdmi_pcm_packet_source #(
    .ENABLE_HDMI_AUDIO(1'b1), .AUDIO_SAMPLE_RATE_HZ(AUDIO_SAMPLE_RATE_HZ), .FIFO_ADDR_WIDTH(4)
  ) dut (
    .pixel_clk(pixel_clk), .audio_pcm_clk(audio_pcm_clk),
    .pixel_clock_hz(pixel_clock_hz), .h_total(h_total), .video_vic(video_vic),
    .pixel_aresetn(resetn), .audio_pcm_aresetn(resetn),
    .hdmi_mode_active(hdmi_mode_active), .vsync(vsync), .line_prepare(line_prepare), .packet_active(packet_active),
    .audio_pcm_tdata(audio_pcm_tdata), .audio_pcm_tvalid(audio_pcm_tvalid),
    .audio_pcm_tready(audio_pcm_tready), .hdmi_audio_enable(hdmi_audio_enable),
    .audio_mute(audio_mute), .audio_gain_q15(audio_gain_q15),
    .packet_ready(packet_ready), .packet_valid(packet_valid), .packet_cancel(packet_cancel), .packet_cancel_link(packet_cancel_link),
    .packet_header(packet_header),
    .packet_sub0(packet_sub0), .packet_sub1(packet_sub1), .packet_sub2(packet_sub2), .packet_sub3(packet_sub3),
    .audio_underflow_event(audio_underflow_event), .audio_overflow_event(audio_overflow_event)
  );

  hdmi_pcm_packet_source #(
    .ENABLE_HDMI_AUDIO(1'b0), .AUDIO_SAMPLE_RATE_HZ(AUDIO_SAMPLE_RATE_HZ), .FIFO_ADDR_WIDTH(4)
  ) static_disabled (
    .pixel_clk(pixel_clk), .audio_pcm_clk(audio_pcm_clk),
    .pixel_clock_hz(pixel_clock_hz), .h_total(h_total), .video_vic(video_vic),
    .pixel_aresetn(resetn), .audio_pcm_aresetn(resetn),
    .hdmi_mode_active(hdmi_mode_active), .vsync(vsync), .line_prepare(line_prepare), .packet_active(packet_active),
    .audio_pcm_tdata(audio_pcm_tdata), .audio_pcm_tvalid(audio_pcm_tvalid),
    .audio_pcm_tready(static_disabled_ready), .hdmi_audio_enable(hdmi_audio_enable),
    .audio_mute(audio_mute), .audio_gain_q15(audio_gain_q15),
    .packet_ready(packet_ready), .packet_valid(static_disabled_valid), .packet_cancel(static_disabled_cancel),
    .packet_cancel_link(), .packet_header(static_disabled_header), .packet_sub0(static_disabled_sub0),
    .packet_sub1(static_disabled_sub1), .packet_sub2(static_disabled_sub2), .packet_sub3(static_disabled_sub3),
    .audio_underflow_event(static_disabled_underflow), .audio_overflow_event(static_disabled_overflow)
  );

  // One prepare pulse per 100 pixel clocks, matching H_TOTAL for ACR line-rate checks.
  always @(negedge pixel_clk) begin
    if (!resetn) begin
      line_prepare = 1'b0;
      vsync = 1'b0;
      line_phase = 0;
      generated_lines = 0;
      packet_ready = 1'b1;
    end else begin
      if (line_phase == 0) begin
        line_prepare = 1'b1;
        vsync = ((generated_lines % 10) == 0);
        generated_lines = generated_lines + 1;
        line_phase = 1;
      end else begin
        line_prepare = 1'b0;
        vsync = 1'b0;
        if (line_phase == H_TOTAL-1)
          line_phase = 0;
        else
          line_phase = line_phase + 1;
      end
      if (force_packet_stall)
        packet_ready = 1'b0;
      else if (random_stalls)
        packet_ready = ($urandom_range(0,3) != 0);
      else
        packet_ready = 1'b1;
    end
  end

  always_ff @(posedge pixel_clk or negedge resetn) begin
    if (!resetn) packet_active <= 1'b0;
    else packet_active <= packet_valid || static_disabled_valid;
  end

  always @(posedge pixel_clk) begin
    if (resetn) begin
      if (line_prepare) line_count = line_count + 1;
      if (packet_valid && packet_ready && packet_header[7:0] == 8'h01) begin
        if (acr_cadence_check && last_acr_line >= 0 && (line_count-last_acr_line) != 80)
          $fatal(1,"48 kHz ACR cadence must be 80 lines in this accelerated profile, got %0d",
                 line_count-last_acr_line);
        last_acr_line = line_count;
        acr_count = acr_count + 1;
      end
      if (packet_valid && packet_ready && packet_header[7:0] == 8'h84) begin
        if (packet_header[15:8] !== 8'h01 || packet_header[23:16] !== 8'h0A ||
            packet_sub0[15:8] !== 8'h01 || packet_sub0[23:16] !== 8'h0F ||
            packet_sub0[7:0] !== 8'h61)
          $fatal(1,"48 kHz 24-bit Audio InfoFrame fields/checksum mismatch");
        infoframe_count = infoframe_count + 1;
      end
      if (packet_valid && packet_ready && packet_header[7:0] == 8'h82) begin
        if (packet_sub0[14:13] !== 2'b00 || packet_sub0[12] !== 1'b1)
          $fatal(1,"AVI PB1 must advertise RGB (Y=00, A0=1)");
        avi_packet_count = avi_packet_count + 1;
      end
      if (packet_valid && packet_ready && packet_header[7:0] == 8'h02) begin
        packet_count = packet_count + 1;
        samples_in_packet = 0;
        seen_zero = 1'b0;
        transmitted_this_packet = 0;
        for (sub_index=0; sub_index<4; sub_index=sub_index+1) begin
          if (packet_header[8+sub_index]) begin
            if (seen_zero) $fatal(1,"sample_present mask must be contiguous from subpacket zero");
            samples_in_packet = samples_in_packet + 1;
            if ((^{(sub_index==0 ? packet_sub0 :
                    sub_index==1 ? packet_sub1 : sub_index==2 ? packet_sub2 : packet_sub3)}) !== 1'b0)
              $fatal(1,"IEC 60958 24-bit sample subpacket parity mismatch");
            if (scoreboard_enable) begin
              if (expected_read >= expected_write)
                $fatal(1,"sample packet emitted without an accepted input sample");
              case (sub_index)
                0: begin
                  if (packet_sub0[23:0] !== expected_left[expected_read] ||
                      packet_sub0[47:24] !== expected_right[expected_read])
                    $fatal(1,"PCM sample %0d L/R mismatch got=%h/%h expected=%h/%h",
                           expected_read, packet_sub0[23:0],packet_sub0[47:24],
                           expected_left[expected_read],expected_right[expected_read]);
                end
                1: begin
                  if (packet_sub1[23:0] !== expected_left[expected_read] ||
                      packet_sub1[47:24] !== expected_right[expected_read])
                    $fatal(1,"PCM sample %0d L/R mismatch got=%h/%h expected=%h/%h",
                           expected_read,packet_sub1[23:0],packet_sub1[47:24],
                           expected_left[expected_read],expected_right[expected_read]);
                end
                2: begin
                  if (packet_sub2[23:0] !== expected_left[expected_read] ||
                      packet_sub2[47:24] !== expected_right[expected_read])
                    $fatal(1,"PCM sample %0d L/R mismatch got=%h/%h expected=%h/%h",
                           expected_read,packet_sub2[23:0],packet_sub2[47:24],
                           expected_left[expected_read],expected_right[expected_read]);
                end
                3: begin
                  if (packet_sub3[23:0] !== expected_left[expected_read] ||
                      packet_sub3[47:24] !== expected_right[expected_read])
                    $fatal(1,"PCM sample %0d L/R mismatch got=%h/%h expected=%h/%h",
                           expected_read,packet_sub3[23:0],packet_sub3[47:24],
                           expected_left[expected_read],expected_right[expected_read]);
                end
              endcase
              expected_read = expected_read + 1;
              transmitted_this_packet = transmitted_this_packet + 1;
            end
          end else begin
            seen_zero = 1'b1;
          end
        end
        if (scoreboard_enable) scoreboard_samples_sent = scoreboard_samples_sent + transmitted_this_packet;
      end
      if (audio_underflow_event) underflow_count = underflow_count + 1;
      if (audio_overflow_event) $fatal(1,"AXI input backpressure must not report FIFO overflow");
      if (static_disabled_cancel || static_disabled_underflow || static_disabled_overflow)
        $fatal(1,"static disabled audio profile must not generate audio cancel/error events");
    end
  end

  task automatic send_sample(input logic signed [23:0] left,
                             input logic signed [23:0] right,
                             input logic signed [23:0] expected_l,
                             input logic signed [23:0] expected_r);
    begin
      if (scoreboard_enable) begin
        expected_left[expected_write] = expected_l;
        expected_right[expected_write] = expected_r;
        expected_write = expected_write + 1;
      end
      @(negedge audio_pcm_clk);
      audio_pcm_tdata = {right,left};
      audio_pcm_tvalid = 1'b1;
      do @(posedge audio_pcm_clk); while (!audio_pcm_tready);
      @(negedge audio_pcm_clk);
      audio_pcm_tvalid = 1'b0;
    end
  endtask

  task automatic send_raw(input logic [47:0] value);
    begin
      @(negedge audio_pcm_clk);
      audio_pcm_tdata = value;
      audio_pcm_tvalid = 1'b1;
      do @(posedge audio_pcm_clk); while (!audio_pcm_tready);
      @(negedge audio_pcm_clk);
      audio_pcm_tvalid = 1'b0;
    end
  endtask

  task automatic send_stalled_candidate(input integer id, output logic was_accepted);
    integer spins;
    logic signed [23:0] left_value, right_value;
    begin
      left_value = 24'(1000+id);
      right_value = -24'(2000+id);
      @(negedge audio_pcm_clk);
      audio_pcm_tdata = {right_value,left_value};
      audio_pcm_tvalid = 1'b1;
      was_accepted = 1'b0;
      spins = 0;
      while (!was_accepted && spins < 100) begin
        @(posedge audio_pcm_clk);
        if (audio_pcm_tready) begin
          was_accepted = 1'b1;
          if (scoreboard_enable) begin
            expected_left[expected_write] = left_value;
            expected_right[expected_write] = right_value;
            expected_write = expected_write + 1;
          end
        end else if (audio_pcm_tdata !== {right_value,left_value}) begin
          $fatal(1,"AXI TDATA changed while TREADY was low");
        end
        spins = spins + 1;
      end
      if (!was_accepted) begin
        repeat(5) begin
          @(posedge audio_pcm_clk);
          if (audio_pcm_tready || audio_pcm_tdata !== {right_value,left_value})
            $fatal(1,"full FIFO did not hold backpressure/data stable");
        end
      end
      @(negedge audio_pcm_clk);
      audio_pcm_tvalid = 1'b0;
    end
  endtask

  task automatic wait_for_samples(input integer target, input integer max_cycles, input string label);
    integer cycles;
    begin
      cycles=0;
      while (scoreboard_samples_sent < target && cycles < max_cycles) begin
        @(posedge pixel_clk);
        cycles=cycles+1;
      end
      if (scoreboard_samples_sent < target)
        $fatal(1,"timeout waiting for %s: sent=%0d target=%0d",label,scoreboard_samples_sent,target);
    end
  endtask

  initial begin
    repeat(6) @(posedge pixel_clk);
    @(negedge pixel_clk); resetn=1;
    repeat(8) @(posedge audio_pcm_clk);
    if (!static_disabled_ready) $fatal(1,"audio-off profile TREADY must be high");
    hdmi_audio_enable=1'b1;
    repeat(12) @(posedge pixel_clk);
    if (!dut.g_hdmi_audio_enabled.pixel_audio_enable || dut.g_hdmi_audio_enabled.rd_flush_pending)
      $fatal(1,"audio enable did not complete its pixel-domain flush");

    // Signed extrema and distinct left/right markers prove the packed input map.
    send_sample(24'sh123456, -24'sh234567, 24'h123456, 24'hDCBA99);
    send_sample(-24'sh800000, 24'sh7FFFFF, 24'h800000, 24'h7FFFFF);
    send_sample(24'sd1, -24'sd1, 24'h000001, 24'hFFFFFF);
    send_sample(-24'sd1234567, 24'sd765432, 24'hED2979, 24'h0BADF8);
    wait_for_samples(4, 12000, "initial 24-bit sample packet");

    timeout=0;
    while (underflow_count==0 && timeout<2000) begin
      @(posedge pixel_clk); timeout=timeout+1;
    end
    if (underflow_count==0) $fatal(1,"underflow event was not reported after stable startup");

    // Q1.15 gain and mute are applied to both signed 24-bit channels.
    audio_gain_q15=17'd16384;
    repeat(8) @(posedge pixel_clk);
    send_sample(24'sd13579, -24'sd13579, 24'sd6789, -24'sd6790);
    wait_for_samples(5, 8000, "half-gain sample");
    audio_mute=1'b1;
    repeat(8) @(posedge pixel_clk);
    send_sample(24'sh123456, -24'sh123456, 24'sd0, 24'sd0);
    wait_for_samples(6, 8000, "muted sample");
    audio_mute=1'b0;
    audio_gain_q15=17'd32768;
    repeat(8) @(posedge pixel_clk);

    // Stop packet consumption until the 4-frame staging buffer and 16-entry CDC FIFO fill.
    force_packet_stall=1'b1;
    random_stalls=1'b0;
    repeat(8) @(posedge pixel_clk);
    accepted=1'b1;
    i=0;
    while (accepted && i<40) begin
      send_stalled_candidate(i, accepted);
      i=i+1;
    end
    if (accepted) $fatal(1,"could not fill the sample buffer/FIFO to assert TREADY backpressure");
    if (audio_pcm_tready) $fatal(1,"full sample FIFO must deassert AXI TREADY");
    target_samples=expected_write;

    // Reopen packet slots with randomized readiness; all accepted beats must emerge in order.
    force_packet_stall=1'b0;
    random_stalls=1'b1;
    wait_for_samples(target_samples, 40000, "random-stall FIFO drain");
    random_stalls=1'b0;
    repeat(8) @(posedge pixel_clk);

    // Observe two complete 80-line ACR intervals in the fixed 48 kHz profile.
    wait_cycles=0;
    while (acr_count < 3 && wait_cycles < 22000) begin
      @(posedge pixel_clk); wait_cycles=wait_cycles+1;
    end
    if (acr_count < 3) $fatal(1,"48 kHz ACR profile did not emit three packets at the expected line rate");

    // Queue frames, switch the active link to DVI before a sample slot opens, and verify flush.
    acr_cadence_check=1'b0;
    force_packet_stall=1'b1;
    scoreboard_enable=1'b0;
    send_raw({24'h654321,24'h123abc});
    send_raw({24'h800001,24'hFFFFFE});
    send_raw({24'h0BADF0,24'h012345});
    send_raw({24'h13579B,24'h2468AC});
    wait_cycles=0;
    while (dut.g_hdmi_audio_enabled.buffered_sample_count < 4 && wait_cycles<5000) begin
      @(posedge pixel_clk); wait_cycles=wait_cycles+1;
    end
    if (dut.g_hdmi_audio_enabled.buffered_sample_count < 4)
      $fatal(1,"could not stage stale frames before DVI mode switch");
    @(negedge pixel_clk); hdmi_mode_active=1'b0;
    repeat(12) @(posedge pixel_clk);
    if (!packet_cancel_link) $fatal(1,"DVI switch must request packet cancellation at boundary");
    if (packet_valid) $fatal(1,"DVI mode must not offer an HDMI packet");
    if (dut.g_hdmi_audio_enabled.buffered_sample_count != 0 || dut.g_hdmi_audio_enabled.rd_flush_pending)
      $fatal(1,"mode switch did not clear the pixel-domain audio buffer");
    if (!audio_pcm_tready) $fatal(1,"PCM TREADY must rise while DVI disables audio collection");
    send_raw({24'h555555,24'hAAAAAA}); // accepted-and-dropped while audio is disabled.

    @(negedge pixel_clk); hdmi_mode_active=1'b1;
    repeat(12) @(posedge pixel_clk);
    if (!dut.g_hdmi_audio_enabled.pixel_audio_enable || dut.g_hdmi_audio_enabled.rd_flush_pending)
      $fatal(1,"HDMI re-entry did not complete audio FIFO flush");
    scoreboard_enable=1'b1;
    expected_write=0; expected_read=0; scoreboard_samples_sent=0;
    force_packet_stall=1'b0;
    send_sample(24'sh456789, -24'sh123456, 24'h456789, 24'hEDCBAA);
    wait_for_samples(1, 8000, "fresh post-flush frame");

    wait_cycles=0;
    while ((avi_packet_count==0 || infoframe_count==0 || acr_count<2) && wait_cycles<40000) begin
      @(posedge pixel_clk); wait_cycles=wait_cycles+1;
    end
    if (avi_packet_count==0 || infoframe_count==0 || acr_count<2)
      $fatal(1,"missing AVI/Audio InfoFrame/ACR slots: avi=%0d info=%0d acr=%0d",
             avi_packet_count,infoframe_count,acr_count);
    if (static_disabled_cancel || static_disabled_underflow || static_disabled_overflow)
      $fatal(1,"static audio-off instance emitted an audio event");
    if (expected_read != expected_write)
      $fatal(1,"unconsumed expected samples remain: read=%0d write=%0d",expected_read,expected_write);
    $display("TEST_PASS: hdmi_pcm_packet_source, 24-bit signed PCM, gain/mute, FIFO backpressure, random stalls, flush, ACR/InfoFrame slots");
    $finish;
  end
endmodule
