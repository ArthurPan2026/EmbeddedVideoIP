`timescale 1ns/1ps
module tb_hdmi_clock_profile_mux;
  logic clock_profile_sel = 1'b0;
  logic vga_pixel_clk = 1'b0;
  logic vga_serial_clk = 1'b0;
  logic hd_pixel_clk = 1'b0;
  logic hd_serial_clk = 1'b0;
  logic vga_locked = 1'b0;
  logic hd_locked = 1'b0;
  logic pixel_reset_hold = 1'b1; // External controller contract, not a mux input.

  wire pixel_clk;
  wire serial_clk;
  logic [1:0] locked_profiles;
  logic selected_locked;

  realtime last_pixel_rise = 0.0;
  realtime last_pixel_fall = 0.0;
  realtime last_serial_rise = 0.0;
  realtime last_serial_fall = 0.0;
  logic saw_pixel_rise = 1'b0, saw_pixel_fall = 1'b0;
  logic saw_serial_rise = 1'b0, saw_serial_fall = 1'b0;
  integer pixel_edges = 0;
  integer serial_edges = 0;
  integer checks = 0;

  // VGA profile: 100 MHz pixel, 500 MHz serial. HD profile: 166.667 MHz
  // pixel, 833.333 MHz serial. Each pair retains its 5:1 clock ratio.
  always #5.0 vga_pixel_clk = ~vga_pixel_clk;
  always #1.0 vga_serial_clk = ~vga_serial_clk;
  always #3.0 hd_pixel_clk = ~hd_pixel_clk;
  always #0.6 hd_serial_clk = ~hd_serial_clk;

  hdmi_clock_profile_mux dut (
    .clock_profile_sel(clock_profile_sel),
    .vga_pixel_clk(vga_pixel_clk), .vga_serial_clk(vga_serial_clk), .vga_locked(vga_locked),
    .hd_pixel_clk(hd_pixel_clk), .hd_serial_clk(hd_serial_clk), .hd_locked(hd_locked),
    .pixel_clk(pixel_clk), .serial_clk(serial_clk),
    .locked_profiles(locked_profiles), .selected_locked(selected_locked)
  );

  // Reject runt pulses across every profile and lock/reset transition. The
  // allowed minima are below the shortest half-cycle of either modeled clock.
  always @(posedge pixel_clk) begin
    if (!$isunknown(pixel_clk)) begin
      if (saw_pixel_fall && (($realtime - last_pixel_fall) < 2.0))
        $fatal(1, "pixel BUFGCTRL produced a short low pulse: %0.3f ns",
               $realtime-last_pixel_fall);
      last_pixel_rise = $realtime;
      saw_pixel_rise = 1'b1;
      pixel_edges = pixel_edges + 1;
    end
  end

  always @(negedge pixel_clk) begin
    if (!$isunknown(pixel_clk)) begin
      if (saw_pixel_rise && (($realtime - last_pixel_rise) < 2.0))
        $fatal(1, "pixel BUFGCTRL produced a short high pulse: %0.3f ns",
               $realtime-last_pixel_rise);
      last_pixel_fall = $realtime;
      saw_pixel_fall = 1'b1;
    end
  end

  always @(posedge serial_clk) begin
    if (!$isunknown(serial_clk)) begin
      if (saw_serial_fall && (($realtime - last_serial_fall) < 0.4))
        $fatal(1, "serial BUFGCTRL produced a short low pulse: %0.3f ns",
               $realtime-last_serial_fall);
      last_serial_rise = $realtime;
      saw_serial_rise = 1'b1;
      serial_edges = serial_edges + 1;
    end
  end

  always @(negedge serial_clk) begin
    if (!$isunknown(serial_clk)) begin
      if (saw_serial_rise && (($realtime - last_serial_rise) < 0.4))
        $fatal(1, "serial BUFGCTRL produced a short high pulse: %0.3f ns",
               $realtime-last_serial_rise);
      last_serial_fall = $realtime;
      saw_serial_fall = 1'b1;
    end
  end

  task automatic check(input logic condition, input string message);
    begin
      checks = checks + 1;
      if (condition !== 1'b1)
        $fatal(1, "CHECK FAILED: %s at %0t", message, $time);
    end
  endtask

  task automatic check_pixel_period(input realtime expected_period, input string label_text);
    realtime t0, measured;
    integer i;
    begin
      for (i=0; i<3; i=i+1) begin
        @(posedge pixel_clk);
        t0 = $realtime;
        @(posedge pixel_clk);
        measured = $realtime - t0;
        if ((measured < expected_period-0.02) || (measured > expected_period+0.02))
          $fatal(1, "%s pixel period %0.3f ns, expected %0.3f ns",
                 label_text, measured, expected_period);
      end
      checks = checks + 3;
    end
  endtask

  task automatic check_serial_period(input realtime expected_period, input string label_text);
    realtime t0, measured;
    integer i;
    begin
      for (i=0; i<3; i=i+1) begin
        @(posedge serial_clk);
        t0 = $realtime;
        @(posedge serial_clk);
        measured = $realtime - t0;
        if ((measured < expected_period-0.02) || (measured > expected_period+0.02))
          $fatal(1, "%s serial period %0.3f ns, expected %0.3f ns",
                 label_text, measured, expected_period);
      end
      checks = checks + 3;
    end
  endtask

  initial begin
    #0.1;
    check(locked_profiles === 2'b00 && selected_locked === 1'b0,
          "lock status is clear during startup");
    check(dut.clock_select_onehot === 2'b01,
          "reset profile selects VGA with a one-hot S pair");

    // Bring up VGA first and verify the selected lock and both output rates.
    vga_locked = 1'b1;
    #0.1;
    check(locked_profiles === 2'b01 && selected_locked === 1'b1,
          "locked_profiles[0] is VGA and VGA is selected");
    repeat (4) @(posedge pixel_clk);
    pixel_reset_hold = 1'b0;
    check_pixel_period(10.0, "VGA");
    check_serial_period(2.0, "VGA");

    // Request HD while the old pixel clock is high. Keep the external pixel
    // reset asserted until the selected source reports lock.
    pixel_reset_hold = 1'b1;
    @(posedge vga_pixel_clk);
    #2.0;
    clock_profile_sel = 1'b1;
    #0.01;
    check(dut.clock_select_onehot === 2'b10,
          "HD request produces a one-hot S pair");
    check(locked_profiles === 2'b01 && selected_locked === 1'b0 && pixel_reset_hold,
          "switch remains held in reset while HD clock is unlocked");
    repeat (8) @(posedge pixel_clk);
    check(pixel_edges > 0 && serial_edges > 0,
          "both BUFGCTRL outputs continue from the selected running clock inputs");

    hd_locked = 1'b1;
    #0.1;
    check(locked_profiles === 2'b11 && selected_locked === 1'b1 && pixel_reset_hold,
          "selected lock rises without releasing external reset early");
    repeat (4) @(posedge pixel_clk);
    pixel_reset_hold = 1'b0;
    check_pixel_period(6.0, "HD");
    check_serial_period(1.2, "HD");

    // Model lock loss followed by the controller's asynchronous reset-to-VGA
    // selection. BUFGCTRL must complete a clean handoff while reset stays held.
    hd_locked = 1'b0;
    #0.1;
    pixel_reset_hold = 1'b1;
    check(locked_profiles === 2'b01 && selected_locked === 1'b0 && pixel_reset_hold,
          "HD lock loss is visible while the pixel domain remains held");
    @(posedge hd_pixel_clk);
    #1.1;
    clock_profile_sel = 1'b0;
    #0.01;
    check(dut.clock_select_onehot === 2'b01,
          "reset recovery selects the VGA clock with a one-hot S pair");
    check(locked_profiles === 2'b01 && selected_locked === 1'b1 && pixel_reset_hold,
          "VGA fallback is locked before reset release");
    repeat (4) @(posedge pixel_clk);
    pixel_reset_hold = 1'b0;
    check_pixel_period(10.0, "VGA recovery");
    check_serial_period(2.0, "VGA recovery");

    // Unknown controller select values fail safe to VGA rather than enabling
    // both clock inputs. Restore the valid select without releasing reset.
    pixel_reset_hold = 1'b1;
    clock_profile_sel = 1'bx;
    #0.01;
    check(dut.clock_select_onehot === 2'b01 && selected_locked === 1'b1,
          "unknown profile select falls back to VGA");
    clock_profile_sel = 1'b0;
    #0.01;
    check(dut.clock_select_onehot === 2'b01,
          "valid VGA selection remains one-hot after fail-safe decode");

    if ((pixel_edges < 30) || (serial_edges < 100))
      $fatal(1, "insufficient clock-edge coverage: pixel=%0d serial=%0d",
             pixel_edges, serial_edges);
    $display("TEST_PASS: hdmi_clock_profile_mux checks=%0d pixel_edges=%0d serial_edges=%0d",
             checks, pixel_edges, serial_edges);
    $finish;
  end
endmodule
