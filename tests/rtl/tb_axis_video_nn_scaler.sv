`timescale 1ns/1ps
module tb_axis_video_nn_scaler;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  always #5 clk = ~clk;

  logic [15:0] cfg_width = 16'd2;
  logic [15:0] cfg_height = 16'd2;
  logic [9:0] cfg_active_width=4, cfg_active_height=4;
  logic [9:0] cfg_x_offset=0, cfg_y_offset=0;
  logic [9:0] cfg_source_x_origin=0, cfg_source_y_origin=0;
  logic [9:0] cfg_x_step=0, cfg_x_rem=2, cfg_y_step=0, cfg_y_rem=2;
  logic clear_errors = 1'b0;
  logic [23:0] s_data = 24'd0;
  logic s_valid = 1'b0;
  wire s_ready;
  logic s_user = 1'b0;
  logic s_last = 1'b0;
  wire [23:0] m_data;
  wire m_valid;
  logic m_ready = 1'b1;
  wire m_user;
  wire m_last;
  wire busy;
  wire [31:0] frame_count;
  wire [31:0] error_flags;
  wire [9:0] active_width;
  wire [9:0] active_height;

  logic [23:0] expected [0:15];
  integer output_index = 0;
  integer cycle_count = 0;
  integer test_case = 0;
  logic was_stalled = 1'b0;
  logic [23:0] held_data;
  logic held_user, held_last;

  axis_video_nn_scaler #(
    .MAX_INPUT_WIDTH(4), .MAX_INPUT_HEIGHT(4),
    .OUTPUT_WIDTH(4), .OUTPUT_HEIGHT(4)
  ) dut (
    .aclk(clk), .aresetn(rst_n),
    .cfg_width(cfg_width), .cfg_height(cfg_height),
    .cfg_active_width(cfg_active_width), .cfg_active_height(cfg_active_height),
    .cfg_x_offset(cfg_x_offset), .cfg_y_offset(cfg_y_offset),
    .cfg_source_x_origin(cfg_source_x_origin), .cfg_source_y_origin(cfg_source_y_origin),
    .cfg_x_step(cfg_x_step), .cfg_x_rem(cfg_x_rem), .cfg_y_step(cfg_y_step), .cfg_y_rem(cfg_y_rem),
    .clear_errors(clear_errors),
    .s_axis_tdata(s_data), .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
    .s_axis_tuser(s_user), .s_axis_tlast(s_last),
    .m_axis_tdata(m_data), .m_axis_tvalid(m_valid), .m_axis_tready(m_ready),
    .m_axis_tuser(m_user), .m_axis_tlast(m_last),
    .busy(busy), .frame_count(frame_count), .error_flags(error_flags),
    .active_width(active_width), .active_height(active_height)
  );

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    m_ready <= (cycle_count % 5 != 1);
    if (m_valid && !m_ready) begin
      if (was_stalled &&
          ((m_data !== held_data) || (m_user !== held_user) || (m_last !== held_last)))
        $fatal(1, "TEST_FAIL: output changed during AXIS backpressure");
      was_stalled <= 1'b1;
      held_data <= m_data;
      held_user <= m_user;
      held_last <= m_last;
    end else if (m_valid && m_ready) begin
      was_stalled <= 1'b0;
      if (output_index >= 16)
        $fatal(1, "TEST_FAIL: too many output pixels");
      if (m_data !== expected[output_index])
        $fatal(1, "TEST_FAIL: case=%0d pixel=%0d got=%h expected=%h",
               test_case, output_index, m_data, expected[output_index]);
      if (m_user !== (output_index == 0))
        $fatal(1, "TEST_FAIL: incorrect SOF at pixel %0d", output_index);
      if (m_last !== ((output_index % 4) == 3))
        $fatal(1, "TEST_FAIL: incorrect EOL at pixel %0d", output_index);
      output_index <= output_index + 1;
    end
  end

  task automatic send_pixel(input logic [23:0] pixel,
                            input logic sof, input logic eol);
    begin
      @(negedge clk);
      s_data = pixel;
      s_user = sof;
      s_last = eol;
      s_valid = 1'b1;
      do @(posedge clk); while (!s_ready);
      @(negedge clk);
      s_valid = 1'b0;
      s_user = 1'b0;
      s_last = 1'b0;
    end
  endtask

  task automatic send_2x2;
    begin
      send_pixel(24'h000001, 1'b1, 1'b0);
      send_pixel(24'h000002, 1'b0, 1'b1);
      send_pixel(24'h000003, 1'b0, 1'b0);
      send_pixel(24'h000004, 1'b0, 1'b1);
    end
  endtask

  initial begin
    #2ms;
    $fatal(1, "TEST_FAIL: watchdog timeout");
  end

  initial begin
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // Stretch nearest-neighbor 2x2 to 4x4.
    test_case = 1;
    expected[0]=24'h000001; expected[1]=24'h000001; expected[2]=24'h000002; expected[3]=24'h000002;
    expected[4]=24'h000001; expected[5]=24'h000001; expected[6]=24'h000002; expected[7]=24'h000002;
    expected[8]=24'h000003; expected[9]=24'h000003; expected[10]=24'h000004; expected[11]=24'h000004;
    expected[12]=24'h000003; expected[13]=24'h000003; expected[14]=24'h000004; expected[15]=24'h000004;
    send_2x2();
    wait (frame_count == 1);
    if (output_index != 16 || error_flags != 0)
      $fatal(1, "TEST_FAIL: scaled frame/status mismatch idx=%0d errors=%h", output_index, error_flags);

    // Bypass is centered 1:1, with black bars around the 2x2 input.
    @(negedge clk);
    output_index = 0;
    test_case = 2;
    cfg_active_width=2; cfg_active_height=2;
    cfg_x_offset=1; cfg_y_offset=1;
    cfg_x_step=1; cfg_x_rem=0; cfg_y_step=1; cfg_y_rem=0;
    expected[0]=0; expected[1]=0; expected[2]=0; expected[3]=0;
    expected[4]=0; expected[5]=24'h000001; expected[6]=24'h000002; expected[7]=0;
    expected[8]=0; expected[9]=24'h000003; expected[10]=24'h000004; expected[11]=0;
    expected[12]=0; expected[13]=0; expected[14]=0; expected[15]=0;
    send_2x2();
    wait (frame_count == 2);
    if (output_index != 16 || error_flags != 0)
      $fatal(1, "TEST_FAIL: bypass frame/status mismatch idx=%0d errors=%h", output_index, error_flags);

    // Early EOL is rejected; the next SOF starts a clean frame.
    @(negedge clk);
    output_index = 0;
    test_case = 3;
    cfg_active_width=4; cfg_active_height=4;
    cfg_x_offset=0; cfg_y_offset=0;
    cfg_x_step=0; cfg_x_rem=2; cfg_y_step=0; cfg_y_rem=2;
    send_pixel(24'h0000aa, 1'b1, 1'b1);
    repeat (3) @(negedge clk);
    expected[0]=24'h000001; expected[1]=24'h000001; expected[2]=24'h000002; expected[3]=24'h000002;
    expected[4]=24'h000001; expected[5]=24'h000001; expected[6]=24'h000002; expected[7]=24'h000002;
    expected[8]=24'h000003; expected[9]=24'h000003; expected[10]=24'h000004; expected[11]=24'h000004;
    expected[12]=24'h000003; expected[13]=24'h000003; expected[14]=24'h000004; expected[15]=24'h000004;
    send_2x2();
    wait (frame_count == 3);
    if (output_index != 16 || !error_flags[1])
      $fatal(1, "TEST_FAIL: malformed-frame recovery mismatch idx=%0d errors=%h", output_index, error_flags);

    // Invalid geometry is reported and does not emit a frame.
    @(negedge clk);
    cfg_width = 0;
    send_pixel(24'h123456, 1'b1, 1'b1);
    repeat (2) @(negedge clk);
    if (!error_flags[0] || frame_count != 3)
      $fatal(1, "TEST_FAIL: invalid geometry was not rejected");

    $display("TEST_PASS: tb_axis_video_nn_scaler");
    $finish;
  end
endmodule
