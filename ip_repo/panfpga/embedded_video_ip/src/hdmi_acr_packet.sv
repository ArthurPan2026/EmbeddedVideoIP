`timescale 1ns/1ps
// HDMI 1.3 音频时钟再生包，按参数提供的像素时钟计算 N/CTS。
module hdmi_acr_packet #(
  parameter integer PIXEL_CLOCK_HZ = 25_178_571,
  parameter integer AUDIO_SAMPLE_RATE_HZ = 48_000,
  parameter integer ACR_N = 6144
) (
  output logic [23:0] header,
  output logic [55:0] subpacket [0:3]
);
  localparam longint unsigned CTS_CALC =
      ((64'(PIXEL_CLOCK_HZ) * 64'(ACR_N)) +
       ((64'd128 * 64'(AUDIO_SAMPLE_RATE_HZ)) / 2)) /
      (64'd128 * 64'(AUDIO_SAMPLE_RATE_HZ));
  localparam logic [19:0] N_VALUE = 20'(ACR_N);
  localparam logic [19:0] CTS_VALUE = 20'(CTS_CALC);
  integer i;
  always_comb begin
    header = 24'h000001; // HB0为音频时钟再生包类型，HB1/HB2保留。
    for (i = 0; i < 4; i = i + 1)
      subpacket[i] = {N_VALUE[7:0], N_VALUE[15:8], {4'b0000, N_VALUE[19:16]},
                      CTS_VALUE[7:0], CTS_VALUE[15:8], {4'b0000, CTS_VALUE[19:16]},
                      8'h00};
  end
endmodule
