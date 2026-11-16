`timescale 1ns/1ps
// 双声道LPCM Audio InfoFrame；V1配置为48 kHz立体声。
module hdmi_audio_infoframe (
  output logic [23:0] header,
  output logic [55:0] subpacket [0:3]
);
  logic [7:0] bytes [0:27];
  integer i;
  logic [7:0] checksum_sum;
  always_comb begin
    header = {8'h0A, 8'h01, 8'h84}; // 顺序为HB2、HB1、HB0，传输时低字节优先。
    for (i = 0; i < 28; i = i + 1)
      bytes[i] = 8'h00;
    bytes[1] = 8'h01; // CC=1表示双声道，CT=0表示沿用数据流头字段。
    bytes[2] = 8'h00; // LPCM的SF/SS为0，表示沿用数据流头字段。
    bytes[3] = 8'h00;
    bytes[4] = 8'h00; // CA=0表示前左/前右声道。
    bytes[5] = 8'h00;
    checksum_sum = header[7:0] + header[15:8] + header[23:16];
    for (i = 1; i <= 10; i = i + 1)
      checksum_sum = checksum_sum + bytes[i];
    bytes[0] = -checksum_sum;
    for (i = 0; i < 4; i = i + 1)
      subpacket[i] = {bytes[6 + i*7], bytes[5 + i*7], bytes[4 + i*7],
                      bytes[3 + i*7], bytes[2 + i*7], bytes[1 + i*7], bytes[0 + i*7]};
  end
endmodule
