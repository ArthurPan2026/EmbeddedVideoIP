`timescale 1ns/1ps
// 7系列HDMI/DVI TMDS 10-bit符号生成器。
// mode：0=控制期，1=视频，2=视频前导，3=数据岛前导，
//       4=视频保护带，5=数据岛保护带，6=数据岛负载。
module hdmi_tmds_symbol_encoder (
  input  logic        pixel_clk,
  input  logic        resetn,
  input  logic [2:0]  mode,
  input  logic [23:0] video_rgb, // R[23:16]、B[15:8]、G[7:0]。
  input  logic        hsync,
  input  logic        vsync,
  input  logic [3:0]  ctl_bits, // {CTL3,CTL2,CTL1,CTL0}。
  input  logic [8:0]  packet_data, // header位和通道1/2的半字节数据。
  output logic [9:0]  lane0_symbol,
  output logic [9:0]  lane1_symbol,
  output logic [9:0]  lane2_symbol
);
  localparam logic [2:0] MODE_CONTROL = 3'd0;
  localparam logic [2:0] MODE_VIDEO = 3'd1;
  localparam logic [2:0] MODE_VIDEO_PREAMBLE = 3'd2;
  localparam logic [2:0] MODE_DATA_PREAMBLE = 3'd3;
  localparam logic [2:0] MODE_VIDEO_GUARD = 3'd4;
  localparam logic [2:0] MODE_DATA_GUARD = 3'd5;
  localparam logic [2:0] MODE_DATA_PAYLOAD = 3'd6;

  logic signed [5:0] disparity0, disparity1, disparity2;
  logic signed [5:0] next_disparity0, next_disparity1, next_disparity2;
  logic [9:0] video_symbol0, video_symbol1, video_symbol2;
  logic [1:0] lane0_ctl;
  logic [1:0] lane1_ctl;
  logic [1:0] lane2_ctl;
  logic [3:0] lane0_terc, lane1_terc, lane2_terc;
  logic [9:0] lane0_terc_symbol, lane1_terc_symbol, lane2_terc_symbol;

  function automatic logic [15:0] encode_video_byte(
    input logic [7:0] din,
    input logic signed [5:0] disparity_in
  );
    logic [8:0] q_m;
    logic use_xnor;
    logic [9:0] encoded;
    integer n1_input;
    integer n1_qm;
    integer dc_bias;
    integer disparity_next;
    integer bit_index;
    begin
      n1_input = 0;
      for (bit_index=0; bit_index<8; bit_index=bit_index+1)
        n1_input = n1_input + din[bit_index];
      use_xnor = (n1_input > 4) || ((n1_input == 4) && (din[0] == 1'b0));
      q_m[0] = din[0];
      for (bit_index=1; bit_index<8; bit_index=bit_index+1)
        q_m[bit_index] = use_xnor ? ~(q_m[bit_index-1] ^ din[bit_index]) :
                                    (q_m[bit_index-1] ^ din[bit_index]);
      q_m[8] = use_xnor ? 1'b0 : 1'b1;

      n1_qm = 0;
      for (bit_index=0; bit_index<8; bit_index=bit_index+1)
        n1_qm = n1_qm + q_m[bit_index];
      dc_bias = 8 - 2*n1_qm;
      disparity_next = $signed(disparity_in);

      if (($signed(disparity_in) == 0) || (n1_qm == 4)) begin
        if (q_m[8] == 1'b0) begin
          encoded = {1'b1, 1'b0, ~q_m[7:0]};
          disparity_next = disparity_next + dc_bias;
        end else begin
          encoded = {1'b0, 1'b1, q_m[7:0]};
          disparity_next = disparity_next - dc_bias;
        end
      end else if (($signed(disparity_in) > 0 && n1_qm > 4) ||
                   ($signed(disparity_in) < 0 && n1_qm < 4)) begin
        encoded = {1'b1, q_m[8], ~q_m[7:0]};
        disparity_next = disparity_next + (q_m[8] ? 2 : 0) + dc_bias;
      end else begin
        encoded = {1'b0, q_m[8], q_m[7:0]};
        disparity_next = disparity_next - (q_m[8] ? 0 : 2) - dc_bias;
      end
      encode_video_byte = {disparity_next[5:0], encoded};
    end
  endfunction

  function automatic logic [9:0] control_symbol(input logic [1:0] control);
    case (control)
      2'b00: control_symbol = 10'b1101010100;
      2'b01: control_symbol = 10'b0010101011;
      2'b10: control_symbol = 10'b0101010100;
      default: control_symbol = 10'b1010101011;
    endcase
  endfunction

  assign {next_disparity0, video_symbol0} = encode_video_byte(video_rgb[15:8], disparity0);
  assign {next_disparity1, video_symbol1} = encode_video_byte(video_rgb[7:0], disparity1);
  assign {next_disparity2, video_symbol2} = encode_video_byte(video_rgb[23:16], disparity2);

  assign lane0_ctl = {vsync, hsync};
  assign lane1_ctl = {ctl_bits[1], ctl_bits[0]};
  assign lane2_ctl = {ctl_bits[3], ctl_bits[2]};

  // 数据岛负载期间，通道0承载HSYNC、VSYNC和header位。
  // 通道1/2各承载4个负载位。
  assign lane0_terc = (mode == MODE_DATA_GUARD) ?
                      {2'b11, vsync, hsync} :
                      {1'b0, packet_data[8], vsync, hsync};
  assign lane1_terc = packet_data[3:0];
  assign lane2_terc = packet_data[7:4];

  hdmi_terc4_encoder u_lane0_terc(.nibble(lane0_terc), .symbol(lane0_terc_symbol));
  hdmi_terc4_encoder u_lane1_terc(.nibble(lane1_terc), .symbol(lane1_terc_symbol));
  hdmi_terc4_encoder u_lane2_terc(.nibble(lane2_terc), .symbol(lane2_terc_symbol));

  always_ff @(posedge pixel_clk or negedge resetn) begin
    if (!resetn) begin
      disparity0 <= '0;
      disparity1 <= '0;
      disparity2 <= '0;
      lane0_symbol <= 10'b1101010100;
      lane1_symbol <= 10'b1101010100;
      lane2_symbol <= 10'b1101010100;
    end else begin
      if (mode == MODE_VIDEO) begin
        disparity0 <= next_disparity0;
        disparity1 <= next_disparity1;
        disparity2 <= next_disparity2;
        lane0_symbol <= video_symbol0;
        lane1_symbol <= video_symbol1;
        lane2_symbol <= video_symbol2;
      end else begin
        disparity0 <= '0;
        disparity1 <= '0;
        disparity2 <= '0;
        case (mode)
          MODE_CONTROL: begin
            lane0_symbol <= control_symbol(lane0_ctl);
            lane1_symbol <= control_symbol(lane1_ctl);
            lane2_symbol <= control_symbol(lane2_ctl);
          end
          MODE_VIDEO_PREAMBLE: begin
            lane0_symbol <= control_symbol(lane0_ctl);
            lane1_symbol <= control_symbol(2'b01); // CTL0=1，CTL1=0。
            lane2_symbol <= control_symbol(2'b00); // CTL2=0，CTL3=0。
          end
          MODE_DATA_PREAMBLE: begin
            lane0_symbol <= control_symbol(lane0_ctl);
            lane1_symbol <= control_symbol(2'b01); // CTL0=1，CTL1=0。
            lane2_symbol <= control_symbol(2'b01); // CTL2=1，CTL3=0。
          end
          MODE_VIDEO_GUARD: begin
            lane0_symbol <= 10'b1011001100;
            lane1_symbol <= 10'b0100110011;
            lane2_symbol <= 10'b1011001100;
          end
          MODE_DATA_GUARD, MODE_DATA_PAYLOAD: begin
            lane0_symbol <= lane0_terc_symbol;
            lane1_symbol <= (mode == MODE_DATA_GUARD) ? 10'b0100110011 : lane1_terc_symbol;
            lane2_symbol <= (mode == MODE_DATA_GUARD) ? 10'b0100110011 : lane2_terc_symbol;
          end
          default: begin
            lane0_symbol <= control_symbol(lane0_ctl);
            lane1_symbol <= control_symbol(lane1_ctl);
            lane2_symbol <= control_symbol(lane2_ctl);
          end
        endcase
      end
    end
  end
endmodule
