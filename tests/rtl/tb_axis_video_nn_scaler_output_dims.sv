`timescale 1ns/1ps
module tb_axis_video_nn_scaler_output_dims;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic [15:0] cfg_width = 16'd1;
  logic [15:0] cfg_height = 16'd1;
  logic [10:0] cfg_output_width = 11'd1280;
  logic [10:0] cfg_output_height = 11'd1;
  logic [10:0] cfg_active_width = 11'd1280;
  logic [10:0] cfg_active_height = 11'd1;
  logic [10:0] cfg_x_offset = 11'd0;
  logic [10:0] cfg_y_offset = 11'd0;
  logic [10:0] cfg_source_x_origin = 11'd0;
  logic [10:0] cfg_source_y_origin = 11'd0;
  logic [10:0] cfg_x_step = 11'd0;
  logic [10:0] cfg_x_rem = 11'd1;
  logic [10:0] cfg_y_step = 11'd1;
  logic [10:0] cfg_y_rem = 11'd0;
  logic [23:0] s_data = 24'd0;
  logic s_valid = 1'b0;
  logic s_user = 1'b0;
  logic s_last = 1'b0;
  wire s_ready;
  wire [23:0] m_data;
  wire m_valid;
  logic m_ready = 1'b1;
  wire m_user;
  wire m_last;
  wire busy;
  wire [31:0] frame_count;
  wire [31:0] error_flags;
  wire [10:0] active_width;
  wire [10:0] active_height;
  integer test_case = 0;
  integer output_index = 0;
  integer cycle_count = 0;
  logic was_stalled = 1'b0;
  logic [23:0] held_data;
  logic held_user, held_last;

  always #5 clk = ~clk;

  axis_video_nn_scaler #(
    .MAX_INPUT_WIDTH(1), .MAX_INPUT_HEIGHT(1),
    .OUTPUT_WIDTH(1920), .OUTPUT_HEIGHT(1080),
    .MAX_BUFFER_WIDTH(1), .MAX_BUFFER_HEIGHT(1)
  ) dut (
    .aclk(clk), .aresetn(resetn),
    .cfg_width(cfg_width), .cfg_height(cfg_height),
    .cfg_output_width(cfg_output_width), .cfg_output_height(cfg_output_height),
    .cfg_active_width(cfg_active_width), .cfg_active_height(cfg_active_height),
    .cfg_x_offset(cfg_x_offset), .cfg_y_offset(cfg_y_offset),
    .cfg_source_x_origin(cfg_source_x_origin), .cfg_source_y_origin(cfg_source_y_origin),
    .cfg_x_step(cfg_x_step), .cfg_x_rem(cfg_x_rem),
    .cfg_y_step(cfg_y_step), .cfg_y_rem(cfg_y_rem),
    .clear_errors(1'b0),
    .s_axis_tdata(s_data), .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
    .s_axis_tuser(s_user), .s_axis_tlast(s_last),
    .m_axis_tdata(m_data), .m_axis_tvalid(m_valid), .m_axis_tready(m_ready),
    .m_axis_tuser(m_user), .m_axis_tlast(m_last),
    .busy(busy), .frame_count(frame_count), .error_flags(error_flags),
    .active_width(active_width), .active_height(active_height)
  );

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    m_ready <= ((cycle_count % 7) != 2);
    if (was_stalled &&
        (!m_valid || m_data !== held_data || m_user !== held_user || m_last !== held_last))
      $fatal(1, "TEST_FAIL: output changed while stalled");
    if (m_valid && !m_ready) begin
      was_stalled <= 1'b1;
      held_data <= m_data;
      held_user <= m_user;
      held_last <= m_last;
    end else if (m_valid && m_ready) begin
      was_stalled <= 1'b0;
      if (m_data !== 24'h123456)
        $fatal(1, "TEST_FAIL: unexpected scaled pixel at index %0d", output_index);
      if (test_case == 1) begin
        if (m_user !== (output_index == 0) || m_last !== (output_index == 1279))
          $fatal(1, "TEST_FAIL: 1280-wide boundary markers at index %0d", output_index);
      end else if (test_case == 2) begin
        if (m_user !== (output_index == 0) || m_last !== 1'b1)
          $fatal(1, "TEST_FAIL: single-pixel line markers at row %0d", output_index);
      end else begin
        $fatal(1, "TEST_FAIL: output escaped test frame");
      end
      output_index <= output_index + 1;
    end
  end

  task automatic send_one_pixel;
    begin
      @(negedge clk);
      s_data = 24'h123456;
      s_user = 1'b1;
      s_last = 1'b1;
      s_valid = 1'b1;
      do @(posedge clk); while (!s_ready);
      @(negedge clk);
      s_valid = 1'b0;
      s_user = 1'b0;
      s_last = 1'b0;
    end
  endtask

  initial begin
    #2ms;
    $fatal(1, "TEST_FAIL: watchdog timeout");
  end

  initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;

    test_case = 1;
    send_one_pixel();
    wait (frame_count == 1);
    if (output_index != 1280 || error_flags != 0 || active_width != 1280 ||
        active_height != 1 || busy)
      $fatal(1, "TEST_FAIL: 1280x1 profile geometry/status mismatch idx=%0d err=%h", output_index, error_flags);

    @(negedge clk);
    test_case = 2;
    output_index = 0;
    cfg_output_width = 11'd1;
    cfg_output_height = 11'd1080;
    cfg_active_width = 11'd1;
    cfg_active_height = 11'd1080;
    cfg_x_step = 10'd1;
    cfg_x_rem = 10'd0;
    cfg_y_step = 10'd0;
    cfg_y_rem = 10'd1;
    send_one_pixel();
    wait (frame_count == 2);
    if (output_index != 1080 || error_flags != 0 || active_width != 1 ||
        active_height != 1080 || busy)
      $fatal(1, "TEST_FAIL: 1x1080 profile geometry/status mismatch idx=%0d err=%h", output_index, error_flags);

    @(negedge clk);
    test_case = 3;
    cfg_output_width = 11'd1921;
    cfg_output_height = 11'd1;
    cfg_active_width = 11'd1;
    cfg_active_height = 11'd1;
    cfg_x_step = 10'd1;
    cfg_x_rem = 10'd0;
    cfg_y_step = 10'd1;
    cfg_y_rem = 10'd0;
    send_one_pixel();
    repeat (3) @(negedge clk);
    if (!error_flags[0] || frame_count != 2 || busy || m_valid)
      $fatal(1, "TEST_FAIL: output width above 1920 was not rejected safely");

    $display("TEST_PASS: tb_axis_video_nn_scaler_output_dims width=1280 height=1080 invalid=1921");
    $finish;
  end
endmodule
