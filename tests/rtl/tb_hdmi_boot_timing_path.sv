`timescale 1ns/1ps
module tb_hdmi_boot_timing_path;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #5 clk = ~clk;

  wire master_vsync;
  wire legacy_slave_vsync;
  wire master_busy;
  wire master_error;
  wire master_audio_allow;
  wire slave_busy;
  wire slave_error;
  wire slave_audio_allow;
  logic master_vsync_prev = 1'b0;
  logic slave_vsync_prev = 1'b0;
  integer master_vsync_edges = 0;
  integer slave_vsync_edges = 0;

  // Master mode drives the raster with the always-high native pixel CE.
  hdmi_video_timing_gen #(
    .VGA_H_TOTAL(12), .VGA_H_ACTIVE(8), .VGA_H_FRONT(1), .VGA_H_SYNC(2),
    .VGA_V_TOTAL(8), .VGA_V_ACTIVE(4), .VGA_V_FRONT(1), .VGA_V_SYNC(2)
  ) master_timing (
    .pixel_clk(clk), .resetn(resetn), .enable(1'b1), .timing_profile(2'd0),
    .ACTIVE_VIDEO(), .HBLANK(), .VBLANK(), .HSYNC(), .VSYNC(master_vsync), .FIELD()
  );

  // Before an accepted AXI SOF, slave-mode VTG enable may remain low.
  hdmi_video_timing_gen #(
    .VGA_H_TOTAL(12), .VGA_H_ACTIVE(8), .VGA_H_FRONT(1), .VGA_H_SYNC(2),
    .VGA_V_TOTAL(8), .VGA_V_ACTIVE(4), .VGA_V_FRONT(1), .VGA_V_SYNC(2)
  ) legacy_slave_timing (
    .pixel_clk(clk), .resetn(resetn), .enable(1'b0), .timing_profile(2'd0),
    .ACTIVE_VIDEO(), .HBLANK(), .VBLANK(), .HSYNC(),
    .VSYNC(legacy_slave_vsync), .FIELD()
  );

  hdmi_mode_transition_ctrl #(
    .LOCK_STABLE_CYCLES(2), .LOCK_TIMEOUT_CYCLES(1000),
    .VSYNC_TIMEOUT_CYCLES(1000), .CONFIG_TIMEOUT_CYCLES(1000)
  ) master_ctrl (
    .clk(clk), .aresetn(resetn), .mode_commit(1'b0), .mode_req(2'd0),
    .mode_error_clear(1'b0), .mode_config_ready(1'b1),
    .pixel_vsync_async(master_vsync), .clock_locked(2'b01),
    .clock_profile_sel(), .timing_profile(), .mode_busy(master_busy),
    .mode_active(), .mode_error(master_error), .pixel_reset_hold(),
    .force_dvi_safe(), .audio_allow(master_audio_allow)
  );

  hdmi_mode_transition_ctrl #(
    .LOCK_STABLE_CYCLES(2), .LOCK_TIMEOUT_CYCLES(1000),
    .VSYNC_TIMEOUT_CYCLES(1000), .CONFIG_TIMEOUT_CYCLES(1000)
  ) legacy_slave_ctrl (
    .clk(clk), .aresetn(resetn), .mode_commit(1'b0), .mode_req(2'd0),
    .mode_error_clear(1'b0), .mode_config_ready(1'b1),
    .pixel_vsync_async(legacy_slave_vsync), .clock_locked(2'b01),
    .clock_profile_sel(), .timing_profile(), .mode_busy(slave_busy),
    .mode_active(), .mode_error(slave_error), .pixel_reset_hold(),
    .force_dvi_safe(), .audio_allow(slave_audio_allow)
  );

  always @(posedge clk) begin
    if (!resetn) begin
      master_vsync_prev <= 1'b0;
      slave_vsync_prev <= 1'b0;
      master_vsync_edges <= 0;
      slave_vsync_edges <= 0;
    end else begin
      if (master_vsync != master_vsync_prev)
        master_vsync_edges <= master_vsync_edges + 1;
      if (legacy_slave_vsync != slave_vsync_prev)
        slave_vsync_edges <= slave_vsync_edges + 1;
      master_vsync_prev <= master_vsync;
      slave_vsync_prev <= legacy_slave_vsync;
    end
  end

  initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;
    repeat (200) @(negedge clk);
    if (master_vsync_edges == 0 || master_busy || master_error || !master_audio_allow)
      $fatal(1, "TEST_FAIL: free-running raw VSYNC did not release boot controller");
    // One initial 0->inactive-high transition can occur before lock acquisition;
    // it must not be treated as a completed frame while the controller is in BOOT_LOCK.
    if (slave_vsync_edges > 1 || !slave_busy || slave_error || slave_audio_allow)
      $fatal(1, "TEST_FAIL: frozen slave timing did not remain in startup wait");
    $display("TEST_PASS: master raw VSYNC releases boot; no-SOF slave timing remains waiting");
    $finish;
  end

  initial begin
    #100us;
    $fatal(1, "TEST_FAIL: boot timing path watchdog");
  end
endmodule
