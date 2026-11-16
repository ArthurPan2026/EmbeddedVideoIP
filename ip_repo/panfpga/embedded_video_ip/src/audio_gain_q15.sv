`timescale 1ns/1ps
// PCM Q1.15 增益；合法增益范围为 0..32768，32768 表示单位增益。
module audio_gain_q15 (
  input  logic signed [15:0] sample_in,
  input  logic        [16:0] gain_q15,
  input  logic               mute,
  output logic signed [15:0] sample_out
);
  logic signed [32:0] sample_ext;
  logic signed [32:0] gain_ext;
  logic signed [32:0] product;
  logic signed [32:0] scaled;
  logic [16:0] gain_limited;
  always_comb begin
    gain_limited = (gain_q15 > 17'd32768) ? 17'd32768 : gain_q15;
    sample_ext = {{17{sample_in[15]}}, sample_in};
    gain_ext = {16'd0, gain_limited};
    product = sample_ext * gain_ext;
    scaled = product >>> 15;
    if (mute || gain_limited == 16'd0)
      sample_out = 16'sd0;
    else if (scaled > 33'sd32767)
      sample_out = 16'sh7fff;
    else if (scaled < -33'sd32768)
      sample_out = 16'sh8000;
    else
      sample_out = scaled[15:0];
  end
endmodule
