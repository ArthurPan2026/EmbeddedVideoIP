`timescale 1ns/1ps
module tb_hdmi_mode_transition_ctrl;
  localparam int LOCK_STABLE_CYCLES = 3;
  localparam int LOCK_TIMEOUT_CYCLES = 40;
  localparam int VSYNC_TIMEOUT_CYCLES = 24;
  localparam int CONFIG_TIMEOUT_CYCLES = 12;

  logic clk = 1'b0;
  logic aresetn = 1'b0;
  logic mode_commit = 1'b0;
  logic [1:0] mode_req = 2'd0;
  logic mode_error_clear = 1'b0;
  logic mode_config_ready = 1'b1;
  logic pixel_vsync_async = 1'b0;
  logic [1:0] clock_locked = 2'b00;

  logic clock_profile_sel;
  logic [1:0] timing_profile;
  logic mode_busy;
  logic [1:0] mode_active;
  logic mode_error;
  logic pixel_reset_hold;
  logic force_dvi_safe;
  logic audio_allow;

  integer checks = 0;
  integer cycle_count;
  logic [1:0] old_mode;

  always #5 clk = ~clk;

  hdmi_mode_transition_ctrl #(
    .LOCK_STABLE_CYCLES(LOCK_STABLE_CYCLES),
    .LOCK_TIMEOUT_CYCLES(LOCK_TIMEOUT_CYCLES),
    .VSYNC_TIMEOUT_CYCLES(VSYNC_TIMEOUT_CYCLES),
    .CONFIG_TIMEOUT_CYCLES(CONFIG_TIMEOUT_CYCLES)
  ) dut (
    .clk(clk),
    .aresetn(aresetn),
    .mode_commit(mode_commit),
    .mode_req(mode_req),
    .mode_error_clear(mode_error_clear),
    .mode_config_ready(mode_config_ready),
    .pixel_vsync_async(pixel_vsync_async),
    .clock_locked(clock_locked),
    .clock_profile_sel(clock_profile_sel),
    .timing_profile(timing_profile),
    .mode_busy(mode_busy),
    .mode_active(mode_active),
    .mode_error(mode_error),
    .pixel_reset_hold(pixel_reset_hold),
    .force_dvi_safe(force_dvi_safe),
    .audio_allow(audio_allow)
  );

  task automatic tick(input integer count);
    integer i;
    begin
      for (i = 0; i < count; i = i + 1) begin
        @(posedge clk);
        #1;
      end
    end
  endtask

  task automatic check(input logic condition, input string message);
    begin
      checks = checks + 1;
      if (condition !== 1'b1)
        $fatal(1, "CHECK FAILED: %s at time %0t", message, $time);
    end
  endtask

  task automatic commit_mode(input logic [1:0] requested_mode);
    begin
      @(negedge clk);
      mode_req = requested_mode;
      mode_commit = 1'b1;
      @(negedge clk);
      mode_commit = 1'b0;
    end
  endtask

  task automatic clear_error;
    begin
      @(negedge clk);
      mode_error_clear = 1'b1;
      @(negedge clk);
      mode_error_clear = 1'b0;
      tick(1);
    end
  endtask

  task automatic pulse_vsync;
    begin
      @(negedge clk);
      pixel_vsync_async = 1'b1;
      repeat (5) @(posedge clk);
      @(negedge clk);
      pixel_vsync_async = 1'b0;
      repeat (5) @(posedge clk);
      #1;
    end
  endtask

  task automatic pulse_transition_boundary;
    begin
      @(negedge clk);
      pixel_vsync_async = 1'b1;
      repeat (3) @(posedge clk);
      #1 check(pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1 &&
               audio_allow === 1'b0,
               "transition asserts safe/reset at synchronized frame boundary");
      @(negedge clk);
      pixel_vsync_async = 1'b0;
      repeat (3) @(posedge clk);
      #1;
    end
  endtask

  task automatic short_async_vsync_pulse(input logic [1:0] expected_before);
    begin
      @(negedge clk);
      pixel_vsync_async = 1'b1;
      @(posedge clk);
      #1 check(mode_active === expected_before,
               "async VSYNC does not publish mode at first synchronizer stage");
      @(posedge clk);
      #1 check(mode_active === expected_before,
               "async VSYNC does not publish mode at second synchronizer stage");
      @(posedge clk);
      #1;
      @(negedge clk);
      pixel_vsync_async = 1'b0;
      repeat (3) @(posedge clk);
      #1;
    end
  endtask

  task automatic wait_reset_release(input integer max_cycles, input string label_text);
    integer i;
    begin
      i = 0;
      while ((pixel_reset_hold !== 1'b0) && (i < max_cycles)) begin
        @(posedge clk);
        #1;
        i = i + 1;
      end
      check(pixel_reset_hold === 1'b0, {label_text, ": pixel reset released"});
    end
  endtask

  task automatic wait_mode_active(input logic [1:0] expected_mode,
                                  input integer max_cycles,
                                  input string label_text);
    integer i;
    begin
      i = 0;
      while ((mode_active !== expected_mode) && (i < max_cycles)) begin
        @(posedge clk);
        #1;
        i = i + 1;
      end
      check(mode_active === expected_mode, {label_text, ": mode committed"});
    end
  endtask

  task automatic wait_failed(input integer max_cycles, input string label_text);
    integer i;
    begin
      i = 0;
      while (((mode_error !== 1'b1) || (mode_busy !== 1'b0)) && (i < max_cycles)) begin
        @(posedge clk);
        #1;
        i = i + 1;
      end
      check(mode_error === 1'b1, {label_text, ": sticky error set"});
      check(mode_busy === 1'b0, {label_text, ": fail state not busy"});
    end
  endtask

  initial begin
    // Asynchronous reset starts in a safe VGA-clocked boot sequence.
    repeat (3) @(posedge clk);
    #1;
    check(pixel_reset_hold === 1'b1, "reset holds pixel domain");
    check(force_dvi_safe === 1'b1 && audio_allow === 1'b0,
          "reset starts DVI-safe with audio blocked");
    check(clock_profile_sel === 1'b0 && timing_profile === 2'd0 && mode_active === 2'd0,
          "reset selects VGA/VIC1 without publishing a new mode");
    check(mode_error === 1'b0, "reset clears sticky error");

    // Delayed VGA lock must remain held until it is stable for several aclk cycles.
    @(negedge clk);
    aresetn = 1'b1;
    tick(4);
    check(pixel_reset_hold === 1'b1, "boot waits for VGA lock");
    clock_locked = 2'b01;
    wait_reset_release(12, "boot lock acquisition");
    check(mode_busy === 1'b1 && force_dvi_safe === 1'b1,
          "boot waits for first output frame in safe mode");
    tick(VSYNC_TIMEOUT_CYCLES + 4);
    check(mode_busy === 1'b1 && pixel_reset_hold === 1'b0 &&
          force_dvi_safe === 1'b1 && audio_allow === 1'b0 && mode_error === 1'b0,
          "delayed PS video startup keeps pixel reset released in DVI-safe mode");
    pulse_vsync();
    check(mode_busy === 1'b0 && mode_active === 2'd0,
          "boot completes on synchronized VSYNC");
    check(force_dvi_safe === 1'b0 && pixel_reset_hold === 1'b0 && audio_allow === 1'b1,
          "boot enables output after first VSYNC");

    // Invalid profile 3 is rejected without touching the active VGA profile.
    commit_mode(2'd3);
    tick(2);
    check(mode_error === 1'b1 && mode_active === 2'd0,
          "invalid request reports error and retains old mode");
    check(clock_profile_sel === 1'b0 && timing_profile === 2'd0 &&
          pixel_reset_hold === 1'b0 && force_dvi_safe === 1'b0,
          "invalid request does not disturb outputs");
    clear_error();

    // VGA -> 720p waits for the current frame boundary, then blanks and holds reset.
    mode_config_ready = 1'b0;
    commit_mode(2'd1);
    tick(2);
    check(mode_busy === 1'b1 && mode_active === 2'd0,
          "720p request stays pending until frame boundary");
    check(pixel_reset_hold === 1'b0 && force_dvi_safe === 1'b0 && audio_allow === 1'b0,
          "pending request mutes new audio without disrupting current video frame");
    check(clock_profile_sel === 1'b0, "clock profile not changed before VSYNC");

    // A second request while busy is rejected; it must not replace the pending 720p request.
    commit_mode(2'd2);
    check(mode_error === 1'b1 && mode_active === 2'd0,
          "busy request is rejected and leaves active mode unchanged");
    pulse_transition_boundary();
    check(force_dvi_safe === 1'b1 && audio_allow === 1'b0,
          "frame boundary leaves output safe during clock switch");
    check(clock_profile_sel === 1'b1 && timing_profile === 2'd0 && mode_active === 2'd0,
          "VGA to HD changes only the clock selection before lock");
    tick(4);
    check(pixel_reset_hold === 1'b1 && timing_profile === 2'd0,
          "delayed HD clock lock keeps reset asserted");
    clock_locked = 2'b11;
    tick(8);
    check(timing_profile === 2'd1 && mode_active === 2'd0 &&
          force_dvi_safe === 1'b1 && pixel_reset_hold === 1'b1 && mode_busy === 1'b1,
          "timing updates after lock but reset waits for upstream config ready");
    tick(3);
    check(pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1,
          "delayed config-ready keeps transition safely held");
    mode_config_ready = 1'b1;
    wait_reset_release(12, "VGA to HD upstream config ready");
    short_async_vsync_pulse(2'd0);
    wait_mode_active(2'd1, 6, "VGA to 720p");
    check(clock_profile_sel === 1'b1 && timing_profile === 2'd1 &&
          force_dvi_safe === 1'b0 && pixel_reset_hold === 1'b0 && audio_allow === 1'b1,
          "720p commits only after new synchronized VSYNC");
    check(mode_error === 1'b1, "busy rejection remains sticky after successful pending transition");
    clear_error();

    // Lock can be good while upstream profile programming stalls; do not release reset.
    mode_config_ready = 1'b0;
    commit_mode(2'd2);
    pulse_transition_boundary();
    tick(LOCK_STABLE_CYCLES + 4);
    check(timing_profile === 2'd2 && mode_active === 2'd1 &&
          pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1,
          "upstream profile config is pending under reset");
    tick(CONFIG_TIMEOUT_CYCLES + 3);
    wait_failed(2, "upstream config-ready timeout");
    check(pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1 &&
          mode_active === 2'd1 && mode_error === 1'b1,
          "config-ready timeout fails closed without committing mode");
    clear_error();
    mode_config_ready = 1'b1;
    commit_mode(2'd1);
    wait_reset_release(12, "retry after config-ready timeout");
    pulse_vsync();
    check(mode_active === 2'd1 && force_dvi_safe === 1'b0 && mode_error === 1'b0,
          "valid retry recovers after config-ready timeout");

    // 720p -> 1080p30 shares the HD clock but still waits for a safe frame transition.
    commit_mode(2'd2);
    pulse_transition_boundary();
    check(force_dvi_safe === 1'b1 && mode_active === 2'd1,
          "same-clock mode change stays safe and unpublished after frame boundary");
    check(clock_profile_sel === 1'b1, "720p to 1080p does not change clock profile");
    wait_reset_release(12, "720p to 1080p lock stability");
    check(clock_profile_sel === 1'b1 && timing_profile === 2'd2 && mode_active === 2'd1,
          "1080p timing loads while 720p remains active until VSYNC");
    pulse_vsync();
    check(mode_active === 2'd2 && force_dvi_safe === 1'b0,
          "1080p30 commits at new frame VSYNC");

    // 1080p30 -> VGA switches back to the VGA clock only while reset is held.
    commit_mode(2'd0);
    check(clock_profile_sel === 1'b1, "HD to VGA retains old clock until frame edge");
    pulse_transition_boundary();
    check(force_dvi_safe === 1'b1 && clock_profile_sel === 1'b0,
          "HD to VGA selects VGA clock only inside safe held transition");
    wait_reset_release(12, "HD to VGA stable lock");
    check(timing_profile === 2'd0 && mode_active === 2'd2 && force_dvi_safe === 1'b1,
          "VGA timing loads before active mode changes");
    pulse_vsync();
    check(mode_active === 2'd0 && clock_profile_sel === 1'b0 &&
          force_dvi_safe === 1'b0 && audio_allow === 1'b1,
          "VGA profile commits after new VSYNC");

    // Lock timeout is fail-closed, clear does not release reset, and a new commit retries.
    clock_locked = 2'b01;
    commit_mode(2'd1);
    pulse_transition_boundary();
    check(clock_profile_sel === 1'b1 && pixel_reset_hold === 1'b1,
          "lock-timeout test entered HD profile under reset");
    tick(LOCK_TIMEOUT_CYCLES + 4);
    wait_failed(2, "HD clock lock timeout");
    check(pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1 && audio_allow === 1'b0 &&
          mode_active === 2'd0,
          "clock lock timeout fails closed without publishing target mode");
    clear_error();
    check(pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1,
          "clearing error does not release failed safe state");
    clock_locked = 2'b11;
    commit_mode(2'd1);
    wait_reset_release(12, "retry after lock timeout");
    pulse_vsync();
    check(mode_active === 2'd1 && mode_error === 1'b0 && force_dvi_safe === 1'b0,
          "valid commit retries and recovers after lock timeout");

    // A missing post-switch VSYNC also fails closed; retry can restore the prior active mode.
    commit_mode(2'd2);
    pulse_transition_boundary();
    wait_reset_release(12, "same-clock mode update before VSYNC timeout");
    check(timing_profile === 2'd2 && mode_active === 2'd1,
          "new timing remains unpublished while awaiting VSYNC");
    tick(VSYNC_TIMEOUT_CYCLES + 4);
    wait_failed(2, "new-profile VSYNC timeout");
    check(pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1 && mode_active === 2'd1,
          "VSYNC timeout preserves previous active mode and holds output safe");
    clear_error();
    commit_mode(2'd1);
    wait_reset_release(12, "retry after VSYNC timeout");
    pulse_vsync();
    check(mode_active === 2'd1 && timing_profile === 2'd1 &&
          force_dvi_safe === 1'b0 && mode_error === 1'b0,
          "retry restores previous mode after VSYNC timeout");

    // Lock loss while active faults closed; retry succeeds after lock returns.
    clock_locked = 2'b01;
    tick(5);
    wait_failed(3, "active HD clock loss");
    check(pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1 && audio_allow === 1'b0 &&
          mode_active === 2'd1,
          "active clock loss mutes and holds reset");
    clear_error();
    clock_locked = 2'b11;
    commit_mode(2'd1);
    wait_reset_release(12, "retry after active lock loss");
    pulse_vsync();
    check(mode_active === 2'd1 && force_dvi_safe === 1'b0 && mode_error === 1'b0,
          "active lock-loss recovery completes after VSYNC");

    // A request with no frame boundary times out and leaves a safe, recoverable state.
    commit_mode(2'd0);
    tick(VSYNC_TIMEOUT_CYCLES + 4);
    wait_failed(2, "current-frame VSYNC timeout");
    check(pixel_reset_hold === 1'b1 && force_dvi_safe === 1'b1 && mode_active === 2'd1,
          "frame-boundary timeout keeps prior mode and fails closed");
    clear_error();
    commit_mode(2'd1);
    wait_reset_release(12, "retry after frame-boundary timeout");
    pulse_vsync();
    check(mode_active === 2'd1 && force_dvi_safe === 1'b0,
          "controller recovers after frame-boundary timeout");

    $display("TEST_PASS: hdmi_mode_transition_ctrl checks=%0d", checks);
    $display("Coverage: reset/boot lock, invalid request, each profile, shared HD clock, frame boundary,");
    $display("          VSYNC synchronization, timing publish, busy rejection, lock delay/loss/timeout,");
    $display("          VSYNC/config-ready timeout, fail-closed outputs, sticky clear and retry recovery.");
    $finish;
  end
endmodule
