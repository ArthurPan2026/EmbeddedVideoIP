`timescale 1ns/1ps
// HDMI数据岛包的32像素时钟串行映射器。
// 输入包头/子包按HB0..HB2、SB0..SB6低字节优先排列；
// 输出packet_data[8]为通道0的header位，低/高半字节分别送到通道1/2。
module hdmi_packet_assembler (
  input  logic        pixel_clk,
  input  logic        resetn,
  input  logic        packet_valid,
  output logic        packet_ready,
  input  logic        packet_cancel,
  input  logic        packet_start,
  output logic        packet_loaded,
  input  logic [23:0] packet_header,
  input  logic [55:0] packet_sub0,
  input  logic [55:0] packet_sub1,
  input  logic [55:0] packet_sub2,
  input  logic [55:0] packet_sub3,
  output logic        packet_active,
  output logic [8:0]  packet_data,
  output logic        packet_done
);
  logic [23:0] header_q;
  logic [55:0] sub_q [0:3];
  logic [7:0] header_ecc;
  logic [7:0] sub_ecc [0:3];
  logic [31:0] header_block;
  logic [63:0] bch_block [0:3];
  logic [4:0] pixel_index;
  logic [5:0] bit_even, bit_odd;
  integer i;

  assign packet_ready = !packet_loaded;

  hdmi_bch_ecc #(.DATA_WIDTH(24)) u_header_bch (.data_in(header_q), .ecc_out(header_ecc));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) u_sub0_bch (.data_in(sub_q[0]), .ecc_out(sub_ecc[0]));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) u_sub1_bch (.data_in(sub_q[1]), .ecc_out(sub_ecc[1]));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) u_sub2_bch (.data_in(sub_q[2]), .ecc_out(sub_ecc[2]));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) u_sub3_bch (.data_in(sub_q[3]), .ecc_out(sub_ecc[3]));

  always_comb begin
    header_block = {header_ecc, header_q};
    for (i=0; i<4; i=i+1)
      bch_block[i] = {sub_ecc[i], sub_q[i]};
    bit_even = {1'b0, pixel_index, 1'b0};
    bit_odd = bit_even + 1'b1;
    packet_data[8] = header_block[pixel_index];
    packet_data[3:0] = {bch_block[3][bit_even], bch_block[2][bit_even],
                        bch_block[1][bit_even], bch_block[0][bit_even]};
    packet_data[7:4] = {bch_block[3][bit_odd], bch_block[2][bit_odd],
                        bch_block[1][bit_odd], bch_block[0][bit_odd]};
  end

  always_ff @(posedge pixel_clk or negedge resetn) begin
    if (!resetn) begin
      header_q <= '0;
      sub_q[0] <= '0;
      sub_q[1] <= '0;
      sub_q[2] <= '0;
      sub_q[3] <= '0;
      pixel_index <= '0;
      packet_active <= 1'b0;
      packet_loaded <= 1'b0;
      packet_done <= 1'b0;
    end else begin
      packet_done <= 1'b0;
      if (packet_cancel && !packet_active) begin
        packet_loaded <= 1'b0;
        pixel_index <= 5'd0;
      end else if (packet_valid && packet_ready) begin
        header_q <= packet_header;
        sub_q[0] <= packet_sub0;
        sub_q[1] <= packet_sub1;
        sub_q[2] <= packet_sub2;
        sub_q[3] <= packet_sub3;
        pixel_index <= 5'd0;
        packet_loaded <= 1'b1;
      end else if (packet_start && packet_loaded && !packet_active) begin
        pixel_index <= 5'd0;
        packet_active <= 1'b1;
      end else if (packet_active) begin
        if (pixel_index == 5'd31) begin
          packet_active <= 1'b0;
          packet_loaded <= 1'b0;
          packet_done <= 1'b1;
          pixel_index <= 5'd0;
        end else begin
          pixel_index <= pixel_index + 1'b1;
        end
      end
    end
  end
endmodule
