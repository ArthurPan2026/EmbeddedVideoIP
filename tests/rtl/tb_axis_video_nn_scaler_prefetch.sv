// Exercise concurrent next-row capture, RGB replication, and native bypass.
module tb_axis_video_nn_scaler_prefetch;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  always #5 clk = ~clk;

  logic [15:0] cfg_width = 16'd3, cfg_height = 16'd2;
  logic [10:0] cfg_output_width = 11'd6, cfg_output_height = 11'd4;
  logic [10:0] cfg_active_width = 11'd6, cfg_active_height = 11'd4;
  logic [10:0] cfg_x_offset = 0, cfg_y_offset = 0;
  logic [10:0] cfg_source_x_origin = 0, cfg_source_y_origin = 0;
  logic [10:0] cfg_x_step = 0, cfg_x_rem = 3;
  logic [10:0] cfg_y_step = 0, cfg_y_rem = 2;
  logic [23:0] s_data = 0;
  logic s_valid = 0, s_user = 0, s_last = 0;
  wire s_ready;
  wire [23:0] m_data;
  wire m_valid, m_user, m_last;
  logic m_ready = 1;
  logic clear_errors = 0;
  wire busy;
  wire [31:0] frame_count, error_flags;
  wire [10:0] active_width, active_height;

  integer cycle_count = 0;
  integer test_case = 0;
  integer output_index = 0;
  integer prefetch_during_output = 0;
  integer active_stall_cycles = 0, padding_stall_cycles = 0;
  logic was_stalled = 0, held_active_window = 0;
  logic [23:0] held_data;
  logic held_user, held_last;

  axis_video_nn_scaler_prefetch #(
    .MAX_INPUT_WIDTH(16), .MAX_INPUT_HEIGHT(8),
    .OUTPUT_WIDTH(16), .OUTPUT_HEIGHT(12),
    .MAX_BUFFER_WIDTH(4), .MAX_BUFFER_HEIGHT(3)
  ) dut (
    .aclk(clk), .aresetn(resetn),
    .cfg_width(cfg_width), .cfg_height(cfg_height),
    .cfg_output_width(cfg_output_width), .cfg_output_height(cfg_output_height),
    .cfg_active_width(cfg_active_width), .cfg_active_height(cfg_active_height),
    .cfg_x_offset(cfg_x_offset), .cfg_y_offset(cfg_y_offset),
    .cfg_source_x_origin(cfg_source_x_origin), .cfg_source_y_origin(cfg_source_y_origin),
    .cfg_x_step(cfg_x_step), .cfg_x_rem(cfg_x_rem),
    .cfg_y_step(cfg_y_step), .cfg_y_rem(cfg_y_rem), .clear_errors(clear_errors),
    .s_axis_tdata(s_data), .s_axis_tvalid(s_valid), .s_axis_tready(s_ready),
    .s_axis_tuser(s_user), .s_axis_tlast(s_last),
    .m_axis_tdata(m_data), .m_axis_tvalid(m_valid), .m_axis_tready(m_ready),
    .m_axis_tuser(m_user), .m_axis_tlast(m_last),
    .busy(busy), .frame_count(frame_count), .error_flags(error_flags),
    .active_width(active_width), .active_height(active_height)
  );

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    m_ready <= ((cycle_count % 9) != 2) && ((cycle_count % 9) != 3);
    if ((test_case >= 1) && (test_case <= 3) && (dut.state == 3'd4) && dut.line_buf_wr_en)
      prefetch_during_output <= prefetch_during_output + 1;
    if (resetn && (dut.state == 3'd4) &&
        (dut.active_x_window !==
         ((dut.emit_x >= dut.x_offset) &&
          (dut.emit_x < (dut.x_offset + dut.active_width)))))
      $fatal(1, "TEST_FAIL: registered active-window state is out of phase at x=%0d", dut.emit_x);
    if (was_stalled &&
        (!m_valid || m_data !== held_data ||
         m_user !== held_user || m_last !== held_last ||
         dut.active_x_window !== held_active_window))
      $fatal(1, "TEST_FAIL: output/window state changed during backpressure");
    if (m_valid && !m_ready) begin
      if (dut.state == 3'd4) begin
        if (dut.active_x_window) active_stall_cycles <= active_stall_cycles + 1;
        else padding_stall_cycles <= padding_stall_cycles + 1;
      end
      was_stalled <= 1;
      held_data <= m_data;
      held_user <= m_user;
      held_last <= m_last;
      held_active_window <= dut.active_x_window;
    end else if (m_valid && m_ready) begin
      was_stalled <= 0;
      if (((test_case >= 1) && (test_case <= 3)) ||
          (test_case == 5) || (test_case == 6)) begin
        integer out_row, out_col, src_row, src_col;
        logic [23:0] expected_pixel;
        out_row = output_index / cfg_output_width;
        out_col = output_index % cfg_output_width;
        expected_pixel = 24'd0;
        if ((out_col >= cfg_x_offset) &&
            (out_col < cfg_x_offset + cfg_active_width) &&
            (out_row >= cfg_y_offset) &&
            (out_row < cfg_y_offset + cfg_active_height)) begin
          if (test_case == 6)
            src_row = cfg_source_y_origin + (out_row - cfg_y_offset);
          else
            src_row = cfg_source_y_origin +
                      ((out_row - cfg_y_offset) * 2 / cfg_active_height);
          src_col = cfg_source_x_origin +
                    ((out_col - cfg_x_offset) * 3 / cfg_active_width);
          expected_pixel = ((test_case == 6) ? 24'h300000 : 24'h100000) +
                           src_row * 3 + src_col;
        end
        if (m_data !== expected_pixel)
          $fatal(1, "TEST_FAIL: scaled pixel %0d got=%h expected=%h",
                 output_index, m_data, expected_pixel);
        if (m_user !== (output_index == 0) ||
            m_last !== (out_col == cfg_output_width-1))
          $fatal(1, "TEST_FAIL: scaled SOF/EOL mismatch at %0d", output_index);
      end else if (test_case == 4) begin
        if (m_data !== (24'h200000 + output_index) ||
            m_user !== (output_index == 0) ||
            m_last !== ((output_index % 8) == 7))
          $fatal(1, "TEST_FAIL: bypass pixel/marker mismatch at %0d", output_index);
      end else if (test_case == 7) begin
        if (m_data !== (((output_index % 3) == 1) ? 24'h400000 : 24'd0) ||
            m_user !== (output_index == 0) ||
            m_last !== ((output_index % 3) == 2))
          $fatal(1, "TEST_FAIL: one-pixel active-window boundary mismatch at %0d", output_index);
      end
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
      s_valid = 1;
      do @(posedge clk); while (!s_ready);
      @(negedge clk);
      s_valid = 0;
      s_user = 0;
      s_last = 0;
    end
  endtask

  task automatic send_scaled_frame;
    integer i;
    begin
      for (i = 0; i < 6; i = i + 1)
        send_pixel(24'h100000 + i, (i == 0), ((i % 3) == 2));
    end
  endtask

  task automatic send_native_frame;
    integer i;
    begin
      for (i = 0; i < 32; i = i + 1)
        send_pixel(24'h200000 + i, (i == 0), ((i % 8) == 7));
    end
  endtask

  task automatic send_three_line_frame;
    integer i;
    begin
      for (i = 0; i < 9; i = i + 1)
        send_pixel(24'h300000 + i, (i == 0), ((i % 3) == 2));
    end
  endtask

  initial begin
    #2ms;
    $fatal(1, "TEST_FAIL: watchdog timeout");
  end

  initial begin
    repeat (4) @(negedge clk);
    resetn = 1;

    test_case = 1;
    send_scaled_frame();
    wait (frame_count == 1);
    if (output_index != 24 || error_flags != 0 || busy ||
        active_width != 6 || active_height != 4 || prefetch_during_output == 0)
      $fatal(1, "TEST_FAIL: scaled prefetch status idx=%0d errors=%h overlap=%0d",
             output_index, error_flags, prefetch_during_output);

    @(negedge clk);
    test_case = 2;
    output_index = 0;
    cfg_output_width = 11'd12; cfg_output_height = 11'd9;
    cfg_active_width = 11'd12; cfg_active_height = 11'd8;
    cfg_x_offset = 0; cfg_y_offset = 0;
    send_scaled_frame();
    wait (frame_count == 2);
    if (output_index != 108 || error_flags != 0 || busy ||
        active_width != 12 || active_height != 8)
      $fatal(1, "TEST_FAIL: 4:3 fit profile status idx=%0d err=%h", output_index, error_flags);

    @(negedge clk);
    test_case = 3;
    output_index = 0;
    cfg_output_width = 11'd16; cfg_output_height = 11'd9;
    cfg_active_width = 11'd13; cfg_active_height = 11'd9;
    cfg_x_offset = 1; cfg_y_offset = 0;
    send_scaled_frame();
    wait (frame_count == 3);
    if (output_index != 144 || error_flags != 0 || busy ||
        active_width != 13 || active_height != 9)
      $fatal(1, "TEST_FAIL: 16:9 fit profile status idx=%0d err=%h", output_index, error_flags);

    @(negedge clk);
    test_case = 4;
    output_index = 0;
    cfg_width = 16'd8; cfg_height = 16'd4;
    cfg_output_width = 11'd8; cfg_output_height = 11'd4;
    cfg_active_width = 11'd8; cfg_active_height = 11'd4;
    cfg_x_offset = 0; cfg_y_offset = 0;
    cfg_source_x_origin = 0; cfg_source_y_origin = 0;
    cfg_x_step = 1; cfg_x_rem = 0;
    cfg_y_step = 1; cfg_y_rem = 0;
    send_native_frame();
    wait (frame_count == 4);
    if (output_index != 32 || error_flags != 0 || busy ||
        !dut.cfg_bypass_1to1 || dut.line_buf_wr_en)
      $fatal(1, "TEST_FAIL: native bypass status idx=%0d errors=%h",
             output_index, error_flags);

    // A malformed line may write into a reserved bank, but cannot be
    // published. A following valid SOF must recover and render normally.
    @(negedge clk);
    test_case = 5;
    output_index = 0;
    cfg_width = 16'd3; cfg_height = 16'd2;
    cfg_output_width = 11'd6; cfg_output_height = 11'd4;
    cfg_active_width = 11'd6; cfg_active_height = 11'd4;
    cfg_x_offset = 0; cfg_y_offset = 0;
    cfg_source_x_origin = 0; cfg_source_y_origin = 0;
    cfg_x_step = 0; cfg_x_rem = 3;
    cfg_y_step = 0; cfg_y_rem = 2;
    send_pixel(24'h100000, 1'b1, 1'b0);
    send_pixel(24'h100001, 1'b0, 1'b1); // early EOL
    send_pixel(24'h100002, 1'b0, 1'b1);
    send_pixel(24'h100003, 1'b0, 1'b0);
    send_pixel(24'h100004, 1'b0, 1'b0);
    send_pixel(24'h100005, 1'b0, 1'b1);
    repeat (8) @(posedge clk);
    if (frame_count != 4 || output_index != 0 || !error_flags[1])
      $fatal(1, "TEST_FAIL: malformed line escaped or did not flag frame=%0d idx=%0d err=%h",
             frame_count, output_index, error_flags);

    @(negedge clk); clear_errors = 1'b1;
    @(negedge clk); clear_errors = 1'b0;
    send_scaled_frame();
    wait (frame_count == 5);
    if (output_index != 24 || error_flags != 0 || busy)
      $fatal(1, "TEST_FAIL: valid frame did not recover after malformed line idx=%0d err=%h",
             output_index, error_flags);

    // Three source rows require recycling the first line bank after source_y
    // advances, while the second bank supplies the current output row.
    @(negedge clk);
    test_case = 6;
    output_index = 0;
    cfg_width = 16'd3; cfg_height = 16'd3;
    cfg_output_width = 11'd6; cfg_output_height = 11'd3;
    cfg_active_width = 11'd6; cfg_active_height = 11'd3;
    cfg_x_offset = 0; cfg_y_offset = 0;
    cfg_source_x_origin = 0; cfg_source_y_origin = 0;
    cfg_x_step = 0; cfg_x_rem = 3;
    cfg_y_step = 1; cfg_y_rem = 0;
    send_three_line_frame();
    wait (frame_count == 6);
    if (output_index != 18 || error_flags != 0 || busy)
      $fatal(1, "TEST_FAIL: line bank was not recycled frame=%0d idx=%0d err=%h",
             frame_count, output_index, error_flags);

    // A one-pixel active window between left and right padding tests both
    // state transitions, with the periodic ready pattern applying backpressure.
    @(negedge clk);
    test_case = 7;
    output_index = 0;
    cfg_width = 16'd1; cfg_height = 16'd1;
    cfg_output_width = 11'd3; cfg_output_height = 11'd1;
    cfg_active_width = 11'd1; cfg_active_height = 11'd1;
    cfg_x_offset = 1; cfg_y_offset = 0;
    cfg_source_x_origin = 0; cfg_source_y_origin = 0;
    cfg_x_step = 0; cfg_x_rem = 0;
    cfg_y_step = 0; cfg_y_rem = 0;
    send_pixel(24'h400000, 1'b1, 1'b1);
    wait (frame_count == 7);
    if (output_index != 3 || error_flags != 0 || busy ||
        active_stall_cycles == 0 || padding_stall_cycles == 0)
      $fatal(1, "TEST_FAIL: active-window boundary/backpressure coverage idx=%0d active_stalls=%0d pad_stalls=%0d err=%h",
             output_index, active_stall_cycles, padding_stall_cycles, error_flags);

    $display("TEST_PASS: tb_axis_video_nn_scaler_prefetch profiles=3:2,4:3,16:9 overlap=%0d bypass=8x4 malformed_recovery=1 bank_reuse=3-line active-window-stalls=%0d/%0d",
             prefetch_during_output, active_stall_cycles, padding_stall_cycles);
    $finish;
  end
endmodule

