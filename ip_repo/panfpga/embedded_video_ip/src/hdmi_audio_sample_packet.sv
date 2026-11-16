`timescale 1ns/1ps
// HDMI 1.3布局0双声道16-bit LPCM音频样本包。
// 每个子包承载一帧立体声样本，每个包最多装入连续四帧。
module hdmi_audio_sample_packet (
  input  logic [31:0] stereo_sample [0:3], // [15:0]为左声道，[31:16]为右声道。
  input  logic [2:0]  sample_count,        // 范围0..4，仅前面的子包有效。
  input  logic [3:0]  sample_flat,        // 1表示该采样周期以平直样本表示。
  input  logic [7:0]  first_frame_index,   // IEC 60958通道状态块中的帧序号0..191。
  output logic [23:0] header,
  output logic [55:0] subpacket [0:3]
);
  logic [7:0] hb0, hb1, hb2;
  logic [23:0] left_word [0:3];
  logic [23:0] right_word [0:3];
  logic [7:0] sb6 [0:3];
  logic [7:0] sample_index [0:3];
  logic block_start [0:3];
  logic c_left [0:3];
  logic c_right [0:3];
  logic p_left [0:3];
  logic p_right [0:3];
  integer i;

  function automatic logic channel_status_bit(input logic right_channel, input logic [7:0] index);
    logic [3:0] channel_number;
    begin
      channel_number = right_channel ? 4'd2 : 4'd1;
      case (index)
        8'd20: channel_status_bit = channel_number[0];
        8'd21: channel_status_bit = channel_number[1];
        8'd22: channel_status_bit = channel_number[2];
        8'd23: channel_status_bit = channel_number[3];
        8'd25: channel_status_bit = 1'b1; // 消费类设备状态位24..27中表示48 kHz。
        8'd33: channel_status_bit = 1'b1; // 表示16-bit字长，最大字长为20-bit。
        default: channel_status_bit = 1'b0;
      endcase
    end
  endfunction

  always_comb begin
    hb0 = 8'h02; // 音频样本包类型。
    hb1 = {3'b000, 1'b0, (sample_count >= 3'd4), (sample_count >= 3'd3),
           (sample_count >= 3'd2), (sample_count >= 3'd1)}; // 布局0，有效位从低位连续置位。
    hb2 = 8'h00;
    for (i = 0; i < 4; i = i + 1) begin
      sample_index[i] = first_frame_index + i[7:0];
      if (sample_index[i] >= 8'd192)
        sample_index[i] = sample_index[i] - 8'd192;
      block_start[i] = (sample_index[i] == 8'd0) && (sample_count > i);
      hb2[i] = (sample_count > i) && sample_flat[i];
      hb2[4+i] = block_start[i]; // B.0..B.3标记IEC 60958块起始帧。
      left_word[i] = {stereo_sample[i][15:0], 8'h00}; // 16-bit PCM在24-bit采样槽内左对齐。
      right_word[i] = {stereo_sample[i][31:16], 8'h00};
      c_left[i] = channel_status_bit(1'b0, sample_index[i]);
      c_right[i] = channel_status_bit(1'b1, sample_index[i]);
      // IEC 60958槽位4..30使用偶校验，V和U位为0。
      p_left[i] = ^{left_word[i], c_left[i], 2'b00};
      p_right[i] = ^{right_word[i], c_right[i], 2'b00};
      sb6[i] = {p_right[i], c_right[i], 2'b00, p_left[i], c_left[i], 2'b00};
      subpacket[i] = {sb6[i], right_word[i], left_word[i]};
    end
    header = {hb2, hb1, hb0};
  end
endmodule
