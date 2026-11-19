`timescale 1ns/1ps
module tb_axis_video_nn_scaler_native_input #(parameter int unsigned LINE_BUFFER_IMPLEMENTATION = 0);
  logic clk = 1'b0, resetn = 1'b0;
  always #5 clk = ~clk;

  logic [15:0] cfg_width = 16'd1280, cfg_height = 16'd1;
  logic [10:0] cfg_output_width = 11'd1920, cfg_output_height = 11'd1;
  logic [10:0] cfg_active_width = 11'd1920, cfg_active_height = 11'd1;
  logic [10:0] cfg_x_offset = 11'd0, cfg_y_offset = 11'd0;
  logic [10:0] cfg_source_x_origin = 11'd0, cfg_source_y_origin = 11'd0;
  logic [10:0] cfg_x_step = 11'd0, cfg_x_rem = 11'd1280;
  logic [10:0] cfg_y_step = 11'd1, cfg_y_rem = 11'd0;
  logic [23:0] s_data = 0;
  logic s_valid = 0, s_user = 0, s_last = 0;
  wire s_ready;
  wire [23:0] m_data;
  wire m_valid, m_user, m_last;
  logic m_ready = 1;
  wire busy;
  wire [31:0] frame_count, error_flags;
  wire [10:0] active_width, active_height;
  integer test_case = 0, output_index = 0, cycle_count = 0;
  logic stalled = 0;
  logic [23:0] held_data;
  logic held_user, held_last;

  axis_video_nn_scaler #(
    .MAX_INPUT_WIDTH(1280), .MAX_INPUT_HEIGHT(720),
    .OUTPUT_WIDTH(1920), .OUTPUT_HEIGHT(1080),
    .MAX_BUFFER_WIDTH(1280), .MAX_BUFFER_HEIGHT(720),
    .LINE_BUFFER_IMPLEMENTATION(LINE_BUFFER_IMPLEMENTATION)
  ) dut (
    .aclk(clk), .aresetn(resetn),
    .cfg_width(cfg_width), .cfg_height(cfg_height),
    .cfg_output_width(cfg_output_width), .cfg_output_height(cfg_output_height),
    .cfg_active_width(cfg_active_width), .cfg_active_height(cfg_active_height),
    .cfg_x_offset(cfg_x_offset), .cfg_y_offset(cfg_y_offset),
    .cfg_source_x_origin(cfg_source_x_origin), .cfg_source_y_origin(cfg_source_y_origin),
    .cfg_x_step(cfg_x_step), .cfg_x_rem(cfg_x_rem),
    .cfg_y_step(cfg_y_step), .cfg_y_rem(cfg_y_rem), .clear_errors(1'b0),
    .s_axis_tdata(s_data), .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
    .s_axis_tuser(s_user), .s_axis_tlast(s_last),
    .m_axis_tdata(m_data), .m_axis_tvalid(m_valid), .m_axis_tready(m_ready),
    .m_axis_tuser(m_user), .m_axis_tlast(m_last),
    .busy(busy), .frame_count(frame_count), .error_flags(error_flags),
    .active_width(active_width), .active_height(active_height)
  );

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    m_ready <= ((cycle_count % 13) != 2) && ((cycle_count % 13) != 3);
    if (stalled && (!m_valid || m_data !== held_data ||
                    m_user !== held_user || m_last !== held_last))
      $fatal(1, "TEST_FAIL: native input output changed during backpressure");
    if (m_valid && !m_ready) begin
      stalled <= 1'b1;
      held_data <= m_data;
      held_user <= m_user;
      held_last <= m_last;
    end else if (m_valid && m_ready) begin
      integer expected_source;
      stalled <= 1'b0;
      if (test_case == 1)
        expected_source = (output_index * 1280) / 1920;
      else if (test_case == 2)
        expected_source = output_index * 2;
      else
        expected_source = output_index;
      if (m_data !== 24'(expected_source))
        $fatal(1, "TEST_FAIL: native input case=%0d output=%0d got=%h expected=%0d",
               test_case, output_index, m_data, expected_source);
      if (m_user !== (output_index == 0))
        $fatal(1, "TEST_FAIL: native input SOF case=%0d output=%0d", test_case, output_index);
      if (test_case == 1 && m_last !== (output_index == 1919))
        $fatal(1, "TEST_FAIL: 1920 output EOL mismatch at %0d", output_index);
      if (test_case == 2 && m_last !== (output_index == 639))
        $fatal(1, "TEST_FAIL: 640 output EOL mismatch at %0d", output_index);
      if (test_case == 3 && !m_last)
        $fatal(1, "TEST_FAIL: 1-pixel native row EOL mismatch at %0d", output_index);
      output_index <= output_index + 1;
    end
  end

  task automatic send_pixel(input integer pixel_index, input logic sof, input logic eol);
    begin
      @(negedge clk);
      s_data = 24'(pixel_index);
      s_user = sof;
      s_last = eol;
      s_valid = 1'b1;
      do @(posedge clk); while (!s_ready);
      @(negedge clk);
      s_valid = 1'b0; s_user = 1'b0; s_last = 1'b0;
    end
  endtask

  task automatic send_wide_frame;
    integer i;
    begin
      for (i = 0; i < 1280; i = i + 1)
        send_pixel(i, (i == 0), (i == 1279));
    end
  endtask

  initial begin
    #2ms;
    $fatal(1, "TEST_FAIL: native input watchdog timeout");
  end

  initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;

    // Native 1280 input expanded to 1920 with an 11-bit 1280 remainder.
    test_case = 1;
    send_wide_frame();
    wait (frame_count == 1);
    if (output_index != 1920 || error_flags != 0 || active_width != 1920 || busy)
      $fatal(1, "TEST_FAIL: 1280-to-1920 geometry/status mismatch idx=%0d errors=%h",
             output_index, error_flags);

    // Native 1280 input reduced to 640, exercising >1023 source counters/BRAM addresses.
    @(negedge clk);
    test_case = 2;
    output_index = 0;
    cfg_output_width = 11'd640; cfg_output_height = 11'd1;
    cfg_active_width = 11'd640; cfg_active_height = 11'd1;
    cfg_x_step = 11'd2; cfg_x_rem = 11'd0;
    send_wide_frame();
    wait (frame_count == 2);
    if (output_index != 640 || error_flags != 0 || active_width != 640 || busy)
      $fatal(1, "TEST_FAIL: 1280-to-640 geometry/status mismatch idx=%0d errors=%h",
             output_index, error_flags);

    // A 1280x720 1:1 source frame uses the direct path and validates the 11-bit height storage.
    @(negedge clk);
    test_case = 3;
    output_index = 0;
    cfg_width = 16'd1; cfg_height = 16'd720;
    cfg_output_width = 11'd1; cfg_output_height = 11'd720;
    cfg_active_width = 11'd1; cfg_active_height = 11'd720;
    cfg_x_step = 11'd1; cfg_x_rem = 11'd0;
    cfg_y_step = 11'd1; cfg_y_rem = 11'd0;
    begin : send_tall_frame
      integer y;
      for (y = 0; y < 720; y = y + 1)
        send_pixel(y, (y == 0), 1'b1);
    end
    wait (frame_count == 3);
    if (output_index != 720 || error_flags != 0 || active_height != 720 || busy)
      $fatal(1, "TEST_FAIL: 1x720 geometry/status mismatch idx=%0d errors=%h",
             output_index, error_flags);

    $display("TEST_PASS: tb_axis_video_nn_scaler_native_input impl=%0d profiles=1280x720=>1920x1080", LINE_BUFFER_IMPLEMENTATION);
    $finish;
  end
endmodule

module tb_axis_video_nn_scaler_native_input_bram;
  tb_axis_video_nn_scaler_native_input #(.LINE_BUFFER_IMPLEMENTATION(1)) test();
endmodule
