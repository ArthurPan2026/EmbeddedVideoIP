`timescale 1ns/1ps

module tb_hdmi_four_mode_clocks;
  logic ctrl_clk = 1'b0;
  logic ref_clk = 1'b0;
  logic resetn = 1'b0;
  logic [1:0] mode = 2'd0;
  wire pixel_clk;
  wire serial_clk;
  wire serdes_pixel_clk;
  wire serial_monitor_clk;
  wire locked;

  integer checks = 0;
  integer mode_write_index = 0;
  logic [1:0] observed_mode = 2'd0;
  integer write_divider;
  logic [15:0] expected_word;

  always #5.0 ctrl_clk = ~ctrl_clk;
  always #10.0 ref_clk = ~ref_clk;

  hdmi_four_mode_clocks dut (
    .ctrl_clk(ctrl_clk), .resetn(resetn), .ref_clk(ref_clk), .mode(mode),
    .pixel_clk(pixel_clk), .serial_clk(serial_clk),
    .serdes_pixel_clk(serdes_pixel_clk), .serial_monitor_clk(serial_monitor_clk),
    .locked(locked)
  );

  task automatic check(input logic condition, input string message);
    begin
      checks = checks + 1;
      if (condition !== 1'b1)
        $fatal(1, "CHECK FAILED: %s at %0t", message, $time);
    end
  endtask

  task automatic wait_for_lock(input string profile_name);
    integer cycles;
    begin
      cycles = 0;
      while (((locked !== 1'b1) || (dut.applied_mode !== mode)) &&
             (cycles < 5000)) begin
        @(posedge ctrl_clk);
        cycles = cycles + 1;
      end
      if (locked !== 1'b1)
        $fatal(1, "%s clock profile did not lock after %0d control clocks",
               profile_name, cycles);
      repeat (4) @(posedge ctrl_clk);
    end
  endtask

  task automatic check_period(
    input integer clock_id,
    input realtime expected_period,
    input realtime tolerance,
    input string clock_name
  );
    realtime t0;
    realtime measured;
    integer sample;
    begin
      for (sample = 0; sample < 3; sample = sample + 1) begin
        case (clock_id)
          0: begin @(posedge serial_clk); t0 = $realtime; @(posedge serial_clk); end
          1: begin @(posedge serdes_pixel_clk); t0 = $realtime; @(posedge serdes_pixel_clk); end
          2: begin @(posedge pixel_clk); t0 = $realtime; @(posedge pixel_clk); end
          3: begin @(posedge serial_monitor_clk); t0 = $realtime; @(posedge serial_monitor_clk); end
          default: $fatal(1, "invalid clock id %0d", clock_id);
        endcase
        measured = $realtime - t0;
        checks = checks + 1;
        if ((measured < expected_period - tolerance) ||
            (measured > expected_period + tolerance))
          $fatal(1, "%s period %0.4f ns, expected %0.4f ns",
                 clock_name, measured, expected_period);
      end
    end
  endtask

  task automatic check_programmed_profile(input logic [1:0] expected_mode);
    begin
      check(observed_mode === expected_mode,
            "DRP writes belong to the selected profile");
      check(mode_write_index == 6,
            "each profile writes the three divider register pairs exactly once");
    end
  endtask

  always @(posedge dut.drp_en) begin
    if (resetn === 1'b1) begin
      #0.001;
      if (dut.drp_we === 1'b1) begin
        if (dut.applied_mode !== observed_mode) begin
          observed_mode = dut.applied_mode;
          mode_write_index = 0;
        end
        if (mode_write_index > 5)
          $fatal(1, "unexpected extra MMCM divider write for profile %0d", observed_mode);
        if (dut.index !== mode_write_index[2:0])
          $fatal(1, "DRP write index %0d did not match expected %0d",
                 dut.index, mode_write_index);
        if (dut.drp_addr !== (7'h08 + mode_write_index))
          $fatal(1, "DRP address %02h did not match expected %02h",
                 dut.drp_addr, 7'h08 + mode_write_index);

        write_divider = hdmi_clock_profile_drp_pkg::divider_for_output(
          dut.index[2:1], observed_mode);
        if ((mode_write_index % 2) == 0) begin
          expected_word = hdmi_clock_profile_drp_pkg::encode_divider_reg1(write_divider);
          if (dut.drp_di[11:0] !== expected_word[11:0] ||
              dut.drp_di[12] !== dut.drp_old[12])
            $fatal(1, "CLKOUT%0d divider count fields were encoded incorrectly",
                   mode_write_index / 2);
        end else begin
          expected_word = hdmi_clock_profile_drp_pkg::encode_divider_reg2(
            dut.drp_old, write_divider);
          if (dut.drp_di[7:6] !== expected_word[7:6] ||
              dut.drp_di[15:10] !== dut.drp_old[15:10])
            $fatal(1, "CLKOUT%0d edge/no-count fields were encoded incorrectly",
                   mode_write_index / 2);
        end
        mode_write_index = mode_write_index + 1;
        checks = checks + 4;
      end
    end
  end

  initial begin
    check(hdmi_clock_profile_drp_pkg::divider_for_output(2'd0, 2'd0) == 5,
          "VGA serial divider is five");
    check(hdmi_clock_profile_drp_pkg::divider_for_output(2'd1, 2'd0) == 25,
          "VGA pixel divider is twenty-five");
    check(hdmi_clock_profile_drp_pkg::divider_for_output(2'd0, 2'd1) == 2,
          "720p serial divider is two");
    check(hdmi_clock_profile_drp_pkg::divider_for_output(2'd1, 2'd1) == 10,
          "720p pixel divider is ten");
    check(hdmi_clock_profile_drp_pkg::divider_for_output(2'd0, 2'd2) == 2,
          "1080p30 serial divider is two");
    check(hdmi_clock_profile_drp_pkg::divider_for_output(2'd1, 2'd2) == 10,
          "1080p30 pixel divider is ten");
    check(hdmi_clock_profile_drp_pkg::divider_for_output(2'd0, 2'd3) == 1,
          "1080p60 serial divider uses no-count mode");
    check(hdmi_clock_profile_drp_pkg::divider_for_output(2'd1, 2'd3) == 5,
          "1080p60 pixel divider is five");
    check(hdmi_clock_profile_drp_pkg::encode_divider_reg1(5) == 16'h0083,
          "odd divide-by-five uses 2/3 count fields");
    check(hdmi_clock_profile_drp_pkg::encode_divider_reg1(25) == 16'h030d,
          "odd divide-by-twenty-five uses 12/13 count fields");
    expected_word = hdmi_clock_profile_drp_pkg::encode_divider_reg2(16'h0000, 5);
    check(expected_word[7:6] == 2'b10,
          "odd divider enables EDGE and leaves NO_COUNT clear");
    check(hdmi_clock_profile_drp_pkg::encode_divider_reg1(1) == 16'h0041,
          "divide-by-one has legal nonzero bypass count fields");
    expected_word = hdmi_clock_profile_drp_pkg::encode_divider_reg2(16'h0000, 1);
    check(expected_word[7:6] == 2'b01,
          "divide-by-one sets NO_COUNT and clears EDGE");

    #1.0 resetn = 1'b1;
    wait_for_lock("480p60");
    check_programmed_profile(2'd0);
    check_period(0, 7.9433, 0.02, "480p60 serial");
    check_period(1, 39.7163, 0.02, "480p60 BUFR CLKDIV");
    check_period(2, 39.7163, 0.02, "480p60 pixel");
    check_period(3, 7.9433, 0.02, "480p60 monitor");

    mode = 2'd1;
    wait_for_lock("720p60");
    check_programmed_profile(2'd1);
    check_period(0, 2.6936, 0.01, "720p60 serial");
    check_period(1, 13.4680, 0.02, "720p60 BUFR CLKDIV");
    check_period(2, 13.4680, 0.02, "720p60 pixel");
    check_period(3, 6.7340, 0.01, "720p60 monitor");

    mode = 2'd2;
    wait_for_lock("1080p30");
    check_programmed_profile(2'd2);
    check_period(0, 2.6936, 0.01, "1080p30 serial");
    check_period(1, 13.4680, 0.02, "1080p30 BUFR CLKDIV");
    check_period(2, 13.4680, 0.02, "1080p30 pixel");

    mode = 2'd3;
    wait_for_lock("1080p60");
    check_programmed_profile(2'd3);
    check_period(0, 1.3468, 0.01, "1080p60 serial");
    check_period(1, 6.7340, 0.01, "1080p60 BUFR CLKDIV");
    check_period(2, 6.7340, 0.01, "1080p60 pixel");
    check_period(3, 6.7340, 0.01, "1080p60 monitor");

    if (mode_write_index != 6)
      $fatal(1, "final profile did not complete all DRP writes");
    $display("TEST_PASS: hdmi_four_mode_clocks checks=%0d", checks);
    $finish;
  end
endmodule
