`timescale 1ns/1ps
// Portable one-pixel-per-beat AXI4-Stream nearest-neighbor scaler.
// Geometry and DDA ratios are supplied by the host driver so this datapath
// has no variable divider in its pixel-clock critical path.
module axis_video_nn_scaler #(
  parameter int unsigned MAX_INPUT_WIDTH = 640,
  parameter int unsigned MAX_INPUT_HEIGHT = 480,
  parameter int unsigned OUTPUT_WIDTH = 640,
  parameter int unsigned OUTPUT_HEIGHT = 480
) (
  input logic aclk, input logic aresetn,
  input logic [15:0] cfg_width, input logic [15:0] cfg_height,
  input logic [9:0] cfg_active_width, input logic [9:0] cfg_active_height,
  input logic [9:0] cfg_x_offset, input logic [9:0] cfg_y_offset,
  input logic [9:0] cfg_source_x_origin, input logic [9:0] cfg_source_y_origin,
  input logic [9:0] cfg_x_step, input logic [9:0] cfg_x_rem,
  input logic [9:0] cfg_y_step, input logic [9:0] cfg_y_rem,
  input logic clear_errors,
  input logic [23:0] s_axis_tdata, input logic s_axis_tvalid,
  output logic s_axis_tready, input logic s_axis_tuser, input logic s_axis_tlast,
  output logic [23:0] m_axis_tdata, output logic m_axis_tvalid,
  input logic m_axis_tready, output logic m_axis_tuser, output logic m_axis_tlast,
  output logic busy, output logic [31:0] frame_count,
  output logic [31:0] error_flags,
  output logic [9:0] active_width, output logic [9:0] active_height
);
  typedef enum logic [2:0] {
    ST_WAIT_SOF, ST_CAPTURE, ST_LINE_READY, ST_PAD_TOP,
    ST_EMIT_ROW, ST_DRAIN, ST_PAD_BOTTOM, ST_DROP
  } state_t;
  state_t state;
  (* ram_style = "distributed" *) logic [23:0] line_buf [0:MAX_INPUT_WIDTH-1];
  logic [9:0] in_width, in_height, cap_x, cap_y;
  logic [9:0] x_offset, y_offset, emit_x, out_y_total, active_y_count;
  logic [9:0] pad_top_left, pad_bottom_left;
  logic top_emitted;
  logic [9:0] source_x, source_y, source_x_origin;
  logic [9:0] x_step, x_rem, y_step, y_rem;
  logic [10:0] x_error, y_error, x_error_sum, y_error_sum;
  logic [9:0] next_source_y;
  logic [10:0] next_y_error;
  logic in_handshake;

  always_comb begin
    s_axis_tready = 1'b0;
    case (state)
      ST_WAIT_SOF, ST_DROP: s_axis_tready = 1'b1;
      ST_CAPTURE, ST_DRAIN: s_axis_tready = !s_axis_tuser;
      default: s_axis_tready = 1'b0;
    endcase
    in_handshake = s_axis_tvalid && s_axis_tready;

    m_axis_tvalid = (state == ST_PAD_TOP) ||
                    (state == ST_EMIT_ROW) ||
                    (state == ST_PAD_BOTTOM);
    m_axis_tuser = m_axis_tvalid && (out_y_total == 0) && (emit_x == 0);
    m_axis_tlast = m_axis_tvalid && (emit_x == OUTPUT_WIDTH-1);
    m_axis_tdata = 24'd0;
    if ((state == ST_EMIT_ROW) &&
        (emit_x >= x_offset) &&
        (emit_x < (x_offset + active_width)) &&
        (source_x < in_width))
      m_axis_tdata = line_buf[source_x];

    x_error_sum = x_error + x_rem;
    y_error_sum = y_error + y_rem;
    if (y_error_sum >= active_height) begin
      next_source_y = source_y + y_step + 1'b1;
      next_y_error = y_error_sum - active_height;
    end else begin
      next_source_y = source_y + y_step;
      next_y_error = y_error_sum;
    end
    busy = (state != ST_WAIT_SOF) && (state != ST_DROP);
  end

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      state <= ST_WAIT_SOF;
      in_width <= '0; in_height <= '0; cap_x <= '0; cap_y <= '0;
      active_width <= '0; active_height <= '0;
      x_offset <= '0; y_offset <= '0; emit_x <= '0;
      out_y_total <= '0; active_y_count <= '0;
      pad_top_left <= '0; pad_bottom_left <= '0; top_emitted <= 1'b0;
      source_x <= '0; source_y <= '0; source_x_origin <= '0;
      x_step <= '0; x_rem <= '0; y_step <= '0; y_rem <= '0;
      x_error <= '0; y_error <= '0;
      frame_count <= '0; error_flags <= '0;
    end else begin
      if (clear_errors)
        error_flags <= '0;

      // Hold a newly observed SOF until the current malformed frame is aborted.
      if (((state == ST_CAPTURE) || (state == ST_DRAIN)) &&
          s_axis_tvalid && s_axis_tuser) begin
        error_flags[2] <= 1'b1;
        state <= ST_WAIT_SOF;
        cap_x <= '0;
        cap_y <= '0;
      end else begin
        case (state)
          ST_WAIT_SOF, ST_DROP: begin
            if (in_handshake && s_axis_tuser) begin
              if ((cfg_width == 0) || (cfg_height == 0) ||
                  (cfg_width > MAX_INPUT_WIDTH) ||
                  (cfg_height > MAX_INPUT_HEIGHT) ||
                  (cfg_active_width == 0) || (cfg_active_height == 0) ||
                  (cfg_active_width > OUTPUT_WIDTH) || (cfg_active_height > OUTPUT_HEIGHT) ||
                  ((cfg_x_offset + cfg_active_width) > OUTPUT_WIDTH) ||
                  ((cfg_y_offset + cfg_active_height) > OUTPUT_HEIGHT) ||
                  (cfg_source_x_origin >= cfg_width) ||
                  (cfg_source_y_origin >= cfg_height) ||
                  (cfg_x_rem >= cfg_active_width) ||
                  (cfg_y_rem >= cfg_active_height) ||
                  (cfg_x_step > MAX_INPUT_WIDTH) ||
                  (cfg_y_step > MAX_INPUT_HEIGHT)) begin
                error_flags[0] <= 1'b1;
                state <= ST_DROP;
              end else begin
                in_width <= cfg_width[9:0];
                in_height <= cfg_height[9:0];
                active_width <= cfg_active_width;
                active_height <= cfg_active_height;
                x_offset <= cfg_x_offset;
                y_offset <= cfg_y_offset;
                pad_top_left <= cfg_y_offset;
                pad_bottom_left <= OUTPUT_HEIGHT - cfg_y_offset - cfg_active_height;
                top_emitted <= 1'b0;
                cap_x <= '0; cap_y <= '0;
                emit_x <= '0; out_y_total <= '0; active_y_count <= '0;
                source_x_origin <= cfg_source_x_origin;
                source_x <= cfg_source_x_origin;
                source_y <= cfg_source_y_origin;
                x_step <= cfg_x_step; x_rem <= cfg_x_rem;
                y_step <= cfg_y_step; y_rem <= cfg_y_rem;
                x_error <= '0; y_error <= '0;
                line_buf[0] <= s_axis_tdata;
                if ((cfg_width == 1) && s_axis_tlast) begin
                  state <= ST_LINE_READY;
                end else if (s_axis_tlast || (cfg_width == 1)) begin
                  error_flags[1] <= 1'b1;
                  state <= ST_DROP;
                end else begin
                  cap_x <= 1;
                  state <= ST_CAPTURE;
                end
              end
            end
          end

          ST_CAPTURE: begin
            if (in_handshake) begin
              line_buf[cap_x] <= s_axis_tdata;
              if (s_axis_tlast) begin
                if (cap_x != in_width-1) begin
                  error_flags[1] <= 1'b1;
                  state <= ST_DROP;
                end else begin
                  cap_x <= '0;
                  state <= ST_LINE_READY;
                end
              end else if (cap_x == in_width-1) begin
                error_flags[1] <= 1'b1;
                state <= ST_DROP;
              end else begin
                cap_x <= cap_x + 1'b1;
              end
            end
          end

          ST_LINE_READY: begin
            if (!top_emitted && (pad_top_left != 0)) begin
              emit_x <= '0;
              state <= ST_PAD_TOP;
              top_emitted <= 1'b1;
            end else if ((active_y_count < active_height) &&
                         (source_y == cap_y)) begin
              emit_x <= '0;
              source_x <= source_x_origin;
              x_error <= '0;
              state <= ST_EMIT_ROW;
            end else if (cap_y + 1 < in_height) begin
              cap_y <= cap_y + 1'b1;
              cap_x <= '0;
              state <= ST_CAPTURE;
            end else begin
              if (active_y_count < active_height)
                error_flags[3] <= 1'b1;
              if (pad_bottom_left == 0) begin
                state <= ST_WAIT_SOF;
                frame_count <= frame_count + 1'b1;
              end else begin
                emit_x <= '0;
                state <= ST_PAD_BOTTOM;
              end
            end
          end

          ST_PAD_TOP: begin
            if (m_axis_tvalid && m_axis_tready) begin
              if (emit_x == OUTPUT_WIDTH-1) begin
                emit_x <= '0;
                out_y_total <= out_y_total + 1'b1;
                if (pad_top_left <= 1) begin
                  pad_top_left <= '0;
                  state <= ST_LINE_READY;
                end else begin
                  pad_top_left <= pad_top_left - 1'b1;
                end
              end else begin
                emit_x <= emit_x + 1'b1;
              end
            end
          end

          ST_EMIT_ROW: begin
            if (m_axis_tvalid && m_axis_tready) begin
              if ((emit_x >= x_offset) && (emit_x < (x_offset + active_width))) begin
                if (x_error_sum >= active_width) begin
                  source_x <= source_x + x_step + 1'b1;
                  x_error <= x_error_sum - active_width;
                end else begin
                  source_x <= source_x + x_step;
                  x_error <= x_error_sum;
                end
              end

              if (emit_x == OUTPUT_WIDTH-1) begin
                emit_x <= '0;
                out_y_total <= out_y_total + 1'b1;
                active_y_count <= active_y_count + 1'b1;
                source_y <= next_source_y;
                y_error <= next_y_error;

                if (active_y_count + 1 >= active_height) begin
                  if (cap_y + 1 < in_height) begin
                    cap_y <= cap_y + 1'b1;
                    cap_x <= '0;
                    state <= ST_DRAIN;
                  end else if (pad_bottom_left == 0) begin
                    state <= ST_WAIT_SOF;
                    frame_count <= frame_count + 1'b1;
                  end else begin
                    state <= ST_PAD_BOTTOM;
                  end
                end else begin
                  // Decide whether to repeat this source row or capture the next
                  // one in ST_LINE_READY, outside the pixel-coordinate update path.
                  state <= ST_LINE_READY;
                end
              end else begin
                emit_x <= emit_x + 1'b1;
              end
            end
          end

          ST_DRAIN: begin
            if (in_handshake) begin
              if (s_axis_tlast) begin
                if (cap_x != in_width-1) begin
                  error_flags[1] <= 1'b1;
                  state <= ST_DROP;
                end else if (cap_y + 1 >= in_height) begin
                  cap_x <= '0;
                  if (pad_bottom_left == 0) begin
                    state <= ST_WAIT_SOF;
                    frame_count <= frame_count + 1'b1;
                  end else begin
                    emit_x <= '0;
                    state <= ST_PAD_BOTTOM;
                  end
                end else begin
                  cap_y <= cap_y + 1'b1;
                  cap_x <= '0;
                end
              end else if (cap_x == in_width-1) begin
                error_flags[1] <= 1'b1;
                state <= ST_DROP;
              end else begin
                cap_x <= cap_x + 1'b1;
              end
            end
          end

          ST_PAD_BOTTOM: begin
            if (m_axis_tvalid && m_axis_tready) begin
              if (emit_x == OUTPUT_WIDTH-1) begin
                emit_x <= '0;
                out_y_total <= out_y_total + 1'b1;
                if (pad_bottom_left <= 1) begin
                  pad_bottom_left <= '0;
                  state <= ST_WAIT_SOF;
                  frame_count <= frame_count + 1'b1;
                end else begin
                  pad_bottom_left <= pad_bottom_left - 1'b1;
                end
              end else begin
                emit_x <= emit_x + 1'b1;
              end
            end
          end

          default: state <= ST_WAIT_SOF;
        endcase
      end
    end
  end
endmodule
