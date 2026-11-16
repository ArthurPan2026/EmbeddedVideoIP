`timescale 1ns/1ps
// 固定640x480时序的水平消隐调度器，活动区和垂直消隐区逐行执行。
module hdmi_line_slot_scheduler #(
  parameter integer H_TOTAL = 800,
  parameter integer H_ACTIVE_SIZE = 640,
  parameter integer H_SYNC_START = 656,
  parameter bit HSYNC_ACTIVE_LEVEL = 1'b1,
  parameter integer VIDEO_LOOKAHEAD_CYCLES = 10
) (
  input  logic       pixel_clk,
  input  logic       aresetn,
  input  logic       video_de_lookahead,
  input  logic       video_de_delayed,
  input  logic       hsync_delayed,
  input  logic       packet_loaded,
  input  logic       packet_offer,
  input  logic       packet_cancel,
  output logic       line_prepare,
  output logic [2:0] symbol_mode,
  output logic       packet_start
);
  localparam logic [2:0] MODE_CONTROL         = 3'd0;
  localparam logic [2:0] MODE_VIDEO           = 3'd1;
  localparam logic [2:0] MODE_VIDEO_PREAMBLE  = 3'd2;
  localparam logic [2:0] MODE_DATA_PREAMBLE   = 3'd3;
  localparam logic [2:0] MODE_VIDEO_GUARD     = 3'd4;
  localparam logic [2:0] MODE_DATA_GUARD      = 3'd5;
  localparam logic [2:0] MODE_DATA_PAYLOAD    = 3'd6;
  localparam integer PREAMBLE_CYCLES = 8;
  localparam integer GUARD_CYCLES = 2;
  localparam integer PACKET_CYCLES = 32;
  localparam integer DATA_ISLAND_CYCLES = PREAMBLE_CYCLES + GUARD_CYCLES +
                                           PACKET_CYCLES + GUARD_CYCLES;
  localparam integer CONTROL_BEFORE_ISLAND = 12;
  localparam integer ISLAND_START = H_SYNC_START + CONTROL_BEFORE_ISLAND;
  localparam integer ISLAND_END = ISLAND_START + DATA_ISLAND_CYCLES;
  localparam integer PREAMBLE_START = H_TOTAL - VIDEO_LOOKAHEAD_CYCLES;
  localparam integer PREPARE_X = H_ACTIVE_SIZE - 20;
  localparam integer X_WIDTH = $clog2(H_TOTAL);

  logic timing_locked;
  logic [X_WIDTH-1:0] x_count;
  logic lookahead_de_q;
  logic [3:0] video_preamble_count;
  logic island_available;
  logic hsync_active;
  logic hsync_active_q;
  logic hsync_active_rise;
  logic lookahead_de_rise;

  assign hsync_active = (hsync_delayed == HSYNC_ACTIVE_LEVEL);
  assign hsync_active_rise = hsync_active && !hsync_active_q;
  assign lookahead_de_rise = video_de_lookahead && !lookahead_de_q;
  assign island_available = !packet_cancel && (packet_loaded || packet_offer);
  assign line_prepare = timing_locked && (x_count == PREPARE_X);

  // HSync每行同步一次计数器；同一行既能处理活动区，也能处理VBlank。
  always_ff @(posedge pixel_clk or negedge aresetn) begin
    if (!aresetn) begin
      hsync_active_q <= 1'b0;
      timing_locked <= 1'b0;
      x_count <= '0;
      lookahead_de_q <= 1'b0;
      video_preamble_count <= 4'd0;
    end else begin
      hsync_active_q <= hsync_active;
      lookahead_de_q <= video_de_lookahead;

      if (hsync_active_rise) begin
        x_count <= X_WIDTH'(H_SYNC_START);
        timing_locked <= 1'b1;
      end else if (x_count == H_TOTAL - 1) begin
        x_count <= '0;
      end else begin
        x_count <= x_count + 1'b1;
      end

      if (lookahead_de_rise)
        video_preamble_count <= 4'd1;
      else if (video_preamble_count != 4'd0 &&
               video_preamble_count < VIDEO_LOOKAHEAD_CYCLES)
        video_preamble_count <= video_preamble_count + 1'b1;
      else
        video_preamble_count <= 4'd0;
    end
  end

  always_comb begin
    symbol_mode = MODE_CONTROL;
    packet_start = 1'b0;

    if (lookahead_de_rise) begin
      symbol_mode = MODE_VIDEO_PREAMBLE;
    end else if (video_preamble_count >= 4'd1 &&
                 video_preamble_count < PREAMBLE_CYCLES) begin
      symbol_mode = MODE_VIDEO_PREAMBLE;
    end else if (video_preamble_count == PREAMBLE_CYCLES ||
                 video_preamble_count == PREAMBLE_CYCLES + 1) begin
      symbol_mode = MODE_VIDEO_GUARD;
    end else if (video_de_delayed) begin
      symbol_mode = MODE_VIDEO;
    end else if (timing_locked && island_available &&
                 x_count >= ISLAND_START && x_count < ISLAND_END) begin
      if (x_count < ISLAND_START + PREAMBLE_CYCLES)
        symbol_mode = MODE_DATA_PREAMBLE;
      else if (x_count < ISLAND_START + PREAMBLE_CYCLES + GUARD_CYCLES ||
               x_count >= ISLAND_START + PREAMBLE_CYCLES + GUARD_CYCLES + PACKET_CYCLES)
        symbol_mode = MODE_DATA_GUARD;
      else
        symbol_mode = MODE_DATA_PAYLOAD;

      if (x_count == ISLAND_START + PREAMBLE_CYCLES + GUARD_CYCLES - 1 &&
          packet_loaded && !packet_cancel)
        packet_start = 1'b1;
    end
  end

  initial begin
    if (H_TOTAL - H_ACTIVE_SIZE < CONTROL_BEFORE_ISLAND + DATA_ISLAND_CYCLES +
                                    12 + VIDEO_LOOKAHEAD_CYCLES)
      $error("水平消隐不足以容纳前后控制期、数据岛和视频前导");
    if (VIDEO_LOOKAHEAD_CYCLES != PREAMBLE_CYCLES + GUARD_CYCLES)
      $error("视频前瞻周期必须等于8拍前导加2拍保护带");
    if (H_SYNC_START <= H_ACTIVE_SIZE || H_SYNC_START >= H_TOTAL)
      $error("HSYNC起始位置必须位于活动区之后和行尾之前");
  end
endmodule
