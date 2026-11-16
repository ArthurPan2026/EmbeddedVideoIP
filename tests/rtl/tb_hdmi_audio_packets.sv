`timescale 1ns/1ps
module tb_hdmi_audio_packets;
  logic [23:0] audio_if_header;
  logic [55:0] audio_if_sub [0:3];
  logic [23:0] sample_header;
  logic [55:0] sample_sub [0:3];
  logic [31:0] samples [0:3];
  logic [2:0] sample_count;
  logic [3:0] sample_flat;
  logic [7:0] first_index;
  logic [23:0] acr_header;
  logic [55:0] acr_sub [0:3];
  logic [7:0] sum;
  integer i;

  hdmi_audio_infoframe info(.header(audio_if_header), .subpacket(audio_if_sub));
  hdmi_audio_sample_packet sample_packet(.stereo_sample(samples), .sample_count(sample_count),
      .sample_flat(sample_flat), .first_frame_index(first_index), .header(sample_header), .subpacket(sample_sub));
  hdmi_acr_packet acr(.header(acr_header), .subpacket(acr_sub));

  task automatic check(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
  endtask

  initial begin
    #1;
    check(audio_if_header === 24'h0A0184, "Audio InfoFrame header mismatch");
    sum = audio_if_header[7:0] + audio_if_header[15:8] + audio_if_header[23:16];
    for (i=0; i<28; i=i+1)
      sum = sum + audio_if_sub[i/7][(i%7)*8 +: 8];
    check(sum === 8'h00, "Audio InfoFrame checksum mismatch");
    check(audio_if_sub[0][15:8] === 8'h01, "Audio InfoFrame channel count mismatch");

    for (i=0; i<4; i=i+1)
      samples[i] = {16'(16'hFEDC-i), 16'(16'h1234+i)};
    sample_count=3'd4; sample_flat=4'b0000; first_index=8'd190; #1;
    check(sample_header === 24'h400F02, "Audio Sample Packet header/B bits mismatch");
    check(sample_sub[0][23:0] === 24'h123400, "Audio left PCM sample alignment mismatch");
    check(sample_sub[0][47:24] === 24'hFEDC00, "Audio right PCM sample alignment mismatch");
    check((^sample_sub[0][55:0]) === 1'b0, "Audio Sample subpacket even parity mismatch");
    check(sample_header[22] === 1'b1, "B bit for frame 0 missing");
    sample_count=3'd1; first_index=8'd25; #1;
    check(sample_sub[0][50] === 1'b1, "48 kHz channel-status code missing");
    sample_count=3'd1; first_index=8'd33; #1;
    check(sample_sub[0][50] === 1'b1, "16-bit word-length status missing");

    sample_count=3'd2; sample_flat=4'b0010; first_index=8'd2; #1;
    check(sample_header[15:8] === 8'h03, "Partial sample-present mask mismatch");
    check(sample_header[19:16] === 4'b0010, "Sample-flat bit order mismatch");

    check(acr_header === 24'h000001, "ACR packet header mismatch");
    // HDMI 1.3表5-11负载次序中SB0位于[7:0]。
    check(acr_sub[0][7:0] === 8'h00, "ACR SB0 reserved mismatch");
    check(acr_sub[0][15:8] === 8'h00, "ACR SB1 CTS[19:16] mismatch");
    check(acr_sub[0][23:16] === 8'h62, "ACR SB2 CTS[15:8] mismatch");
    check(acr_sub[0][31:24] === 8'h5B, "ACR SB3 CTS[7:0] mismatch");
    check(acr_sub[0][39:32] === 8'h00, "ACR SB4 N[19:16] mismatch");
    check(acr_sub[0][47:40] === 8'h18, "ACR SB5 N[15:8] mismatch");
    check(acr_sub[0][55:48] === 8'h00, "ACR SB6 N[7:0] mismatch");

    $display("TEST_PASS: hdmi_audio_packets");
    $finish;
  end
endmodule
