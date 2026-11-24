`timescale 1ns/1ps
module tb_hdmi_audio_packets;
  logic [23:0] info48_header, info96_header, info192_header;
  logic [55:0] info48_sub [0:3], info96_sub [0:3], info192_sub [0:3];
  logic [23:0] sample48_header, sample96_header, sample192_header;
  logic [55:0] sample48_sub [0:3], sample96_sub [0:3], sample192_sub [0:3];
  logic [47:0] samples [0:3];
  logic [2:0] sample_count;
  logic [3:0] sample_flat;
  logic [7:0] first_index;
  logic [23:0] acr48_header, acr96_header, acr192_header;
  logic [55:0] acr48_sub [0:3], acr96_sub [0:3], acr192_sub [0:3];
  logic [23:0] acr_round_low_header, acr_round_high_header, acr_max_header;
  logic [55:0] acr_round_low_sub [0:3], acr_round_high_sub [0:3], acr_max_sub [0:3];
  logic [31:0] profile_pixel_clock=32'd25_178_571;
  logic [7:0] profile_vic=8'd1;
  logic [23:0] acr_profile48_header, acr_profile96_header, acr_profile192_header;
  logic [55:0] acr_profile48_sub [0:3], acr_profile96_sub [0:3], acr_profile192_sub [0:3];
  logic [31:0] acr48_pixel_clock=32'd25_178_571, acr96_pixel_clock=32'd25_178_571;
  logic [31:0] acr192_pixel_clock=32'd25_178_571, acr_round_low_pixel_clock=32'd25_178_499;
  logic [31:0] acr_round_high_pixel_clock=32'd25_178_500, acr_max_pixel_clock=32'd1_048_575_000;
  integer i;

  hdmi_audio_infoframe #(.AUDIO_SAMPLE_RATE_HZ(48_000), .AUDIO_SAMPLE_SIZE_BITS(24)) info48
    (.header(info48_header), .subpacket(info48_sub));
  hdmi_audio_infoframe #(.AUDIO_SAMPLE_RATE_HZ(96_000), .AUDIO_SAMPLE_SIZE_BITS(24)) info96
    (.header(info96_header), .subpacket(info96_sub));
  hdmi_audio_infoframe #(.AUDIO_SAMPLE_RATE_HZ(192_000), .AUDIO_SAMPLE_SIZE_BITS(24)) info192
    (.header(info192_header), .subpacket(info192_sub));

  hdmi_audio_sample_packet #(.AUDIO_SAMPLE_RATE_HZ(48_000)) sample48
    (.stereo_sample(samples), .sample_count(sample_count), .sample_flat(sample_flat),
     .first_frame_index(first_index), .header(sample48_header), .subpacket(sample48_sub));
  hdmi_audio_sample_packet #(.AUDIO_SAMPLE_RATE_HZ(96_000)) sample96
    (.stereo_sample(samples), .sample_count(sample_count), .sample_flat(sample_flat),
     .first_frame_index(first_index), .header(sample96_header), .subpacket(sample96_sub));
  hdmi_audio_sample_packet #(.AUDIO_SAMPLE_RATE_HZ(192_000)) sample192
    (.stereo_sample(samples), .sample_count(sample_count), .sample_flat(sample_flat),
     .first_frame_index(first_index), .header(sample192_header), .subpacket(sample192_sub));

  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(48_000)) acr48
    (.pixel_clock_hz(acr48_pixel_clock), .video_vic(8'd0), .header(acr48_header), .subpacket(acr48_sub));
  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(96_000)) acr96
    (.pixel_clock_hz(acr96_pixel_clock), .video_vic(8'd0), .header(acr96_header), .subpacket(acr96_sub));
  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(192_000)) acr192
    (.pixel_clock_hz(acr192_pixel_clock), .video_vic(8'd0), .header(acr192_header), .subpacket(acr192_sub));
  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(48_000)) acr_round_low
    (.pixel_clock_hz(acr_round_low_pixel_clock), .video_vic(8'd0), .header(acr_round_low_header), .subpacket(acr_round_low_sub));
  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(48_000)) acr_round_high
    (.pixel_clock_hz(acr_round_high_pixel_clock), .video_vic(8'd0), .header(acr_round_high_header), .subpacket(acr_round_high_sub));
  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(48_000)) acr_max
    (.pixel_clock_hz(acr_max_pixel_clock), .video_vic(8'd0), .header(acr_max_header), .subpacket(acr_max_sub));
  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(48_000), .USE_VIDEO_PROFILE_CLOCKS(1'b1)) acr_profile48
    (.pixel_clock_hz(profile_pixel_clock), .video_vic(profile_vic), .header(acr_profile48_header), .subpacket(acr_profile48_sub));
  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(96_000), .USE_VIDEO_PROFILE_CLOCKS(1'b1)) acr_profile96
    (.pixel_clock_hz(profile_pixel_clock), .video_vic(profile_vic), .header(acr_profile96_header), .subpacket(acr_profile96_sub));
  hdmi_acr_packet #(.AUDIO_SAMPLE_RATE_HZ(192_000), .USE_VIDEO_PROFILE_CLOCKS(1'b1)) acr_profile192
    (.pixel_clock_hz(profile_pixel_clock), .video_vic(profile_vic), .header(acr_profile192_header), .subpacket(acr_profile192_sub));

  task automatic check(input logic condition, input string message);
    if (!condition) $fatal(1, "%s", message);
  endtask

  task automatic check_infoframe(
    input logic [23:0] h,
    input logic [55:0] p0, input logic [55:0] p1,
    input logic [55:0] p2, input logic [55:0] p3,
    input logic [7:0] expected_checksum, input logic [7:0] expected_pb2,
    input string label
  );
    logic [7:0] sum;
    logic [55:0] payloads [0:3];
    integer b;
    begin
      payloads[0]=p0; payloads[1]=p1; payloads[2]=p2; payloads[3]=p3;
      check(h === 24'h0A0184, {label, " Audio InfoFrame header mismatch"});
      sum = h[7:0] + h[15:8] + h[23:16];
      for (b=0; b<28; b=b+1)
        sum = sum + payloads[b/7][(b%7)*8 +: 8];
      check(sum === 8'h00, {label, " Audio InfoFrame checksum sum is nonzero"});
      check(p0[7:0] === expected_checksum, {label, " checksum byte mismatch"});
      check(p0[15:8] === 8'h01, {label, " channel count is not two"});
      check(p0[23:16] === expected_pb2, {label, " Fs/SS fields mismatch"});
      check(p0[31:24] === 8'h00 && p0[39:32] === 8'h00 && p0[47:40] === 8'h00,
            {label, " reserved Audio InfoFrame bytes must be zero"});
      check(p1 === 56'd0 && p2 === 56'd0 && p3 === 56'd0,
            {label, " unused Audio InfoFrame payload bytes must be zero"});
    end
  endtask

  task automatic check_acr(input logic [55:0] p, input logic [19:0] n,
                           input logic [19:0] cts, input string label);
    begin
      check(p[7:0] === 8'h00, {label, " ACR SB0 reserved byte mismatch"});
      check(p[15:8] === {4'b0000,cts[19:16]}, {label, " ACR CTS[19:16] mismatch"});
      check(p[23:16] === cts[15:8], {label, " ACR CTS[15:8] mismatch"});
      check(p[31:24] === cts[7:0], {label, " ACR CTS[7:0] mismatch"});
      check(p[39:32] === {4'b0000,n[19:16]}, {label, " ACR N[19:16] mismatch"});
      check(p[47:40] === n[15:8], {label, " ACR N[15:8] mismatch"});
      check(p[55:48] === n[7:0], {label, " ACR N[7:0] mismatch"});
    end
  endtask

  initial begin
    samples[0] = {24'h7FFFFF,24'h800000};
    samples[1] = {24'hFEDCBA,24'h123456};
    samples[2] = {24'h000001,24'hFFFFFF};
    samples[3] = {24'hABCDEF,24'h654321};
    sample_count=3'd4; sample_flat=4'b0000; first_index=8'd190;
    #1;

    check_infoframe(info48_header, info48_sub[0], info48_sub[1], info48_sub[2], info48_sub[3],
                    8'h61, 8'h0F, "48 kHz");
    check_infoframe(info96_header, info96_sub[0], info96_sub[1], info96_sub[2], info96_sub[3],
                    8'h59, 8'h17, "96 kHz");
    check_infoframe(info192_header, info192_sub[0], info192_sub[1], info192_sub[2], info192_sub[3],
                    8'h51, 8'h1F, "192 kHz");

    check(sample48_header === 24'h400F02, "24-bit sample header/B-block-start mismatch");
    check(sample48_sub[0][23:0] === 24'h800000, "negative full-scale left sample mapping mismatch");
    check(sample48_sub[0][47:24] === 24'h7FFFFF, "positive full-scale right sample mapping mismatch");
    check((^sample48_sub[0]) === 1'b0 && (^sample96_sub[0]) === 1'b0 &&
          (^sample192_sub[0]) === 1'b0, "24-bit IEC 60958 subpacket parity mismatch");
    check(sample48_sub[0][53:52] === 2'b00 && sample48_sub[0][49:48] === 2'b00,
          "left sample V/U bits must be zero");
    check(sample48_sub[0][47:24] === samples[0][47:24], "right sample word is not preserved");
    check(sample48_header[22] === 1'b1, "B bit for wrapped frame index zero missing");
    check(sample48_header[23:20] === 4'b0100, "B bit position must mark the third sample only");

    for (i=0; i<=4; i=i+1) begin
      sample_count=3'(i); sample_flat=4'b0000; first_index=8'd10; #1;
      case (i)
        0: check(sample48_header[15:8] === 8'h00, "zero-sample mask mismatch");
        1: check(sample48_header[15:8] === 8'h01, "one-sample mask mismatch");
        2: check(sample48_header[15:8] === 8'h03, "two-sample mask mismatch");
        3: check(sample48_header[15:8] === 8'h07, "three-sample mask mismatch");
        4: check(sample48_header[15:8] === 8'h0F, "four-sample mask mismatch");
      endcase
    end
    sample_count=3'd2; sample_flat=4'b0010; first_index=8'd2; #1;
    check(sample48_header[19:16] === 4'b0010, "sample-flat bit order mismatch");

    sample_count=3'd1; sample_flat=4'b0000; first_index=8'd20; #1;
    check(sample48_sub[0][50] === 1'b1 && sample48_sub[0][54] === 1'b0,
          "left channel-status number mismatch");
    first_index=8'd21; #1;
    check(sample48_sub[0][50] === 1'b0 && sample48_sub[0][54] === 1'b1,
          "right channel-status number mismatch");
    first_index=8'd25; #1;
    check(sample48_sub[0][50] === 1'b1 && sample96_sub[0][50] === 1'b1 &&
          sample192_sub[0][50] === 1'b1, "48/96/192 kHz channel-status Fs LSB mismatch");
    first_index=8'd26; #1;
    check(sample48_sub[0][50] === 1'b0 && sample96_sub[0][50] === 1'b0 &&
          sample192_sub[0][50] === 1'b1, "192 kHz channel-status bit 26 mismatch");
    first_index=8'd27; #1;
    check(sample48_sub[0][50] === 1'b0 && sample96_sub[0][50] === 1'b1 &&
          sample192_sub[0][50] === 1'b1, "96/192 kHz channel-status bit 27 mismatch");
    first_index=8'd32; #1;
    check(sample48_sub[0][50] === 1'b1, "24-bit maximum word-length flag missing");
    first_index=8'd33; #1;
    check(sample48_sub[0][50] === 1'b1, "24-bit word-length bit 33 missing");
    first_index=8'd34; #1;
    check(sample48_sub[0][50] === 1'b0, "reserved word-length bit 34 must be zero");
    first_index=8'd35; #1;
    check(sample48_sub[0][50] === 1'b1, "24-bit word-length bit 35 missing");
    first_index=8'd36; #1;
    check(sample48_sub[0][50] === 1'b1, "original Fs bit 36 missing");
    first_index=8'd38; #1;
    check(sample48_sub[0][50] === 1'b1 && sample192_sub[0][50] === 1'b0,
          "original Fs bit 38 mismatch");
    first_index=8'd39; #1;
    check(sample48_sub[0][50] === 1'b1 && sample96_sub[0][50] === 1'b0 &&
          sample192_sub[0][50] === 1'b0, "original Fs bit 39 mismatch");

    check(acr48_header === 24'h000001 && acr96_header === 24'h000001 &&
          acr192_header === 24'h000001, "ACR packet header mismatch");
    check_acr(acr48_sub[0], 20'd6144, 20'd25179, "48 kHz ACR");
    check_acr(acr96_sub[0], 20'd12288, 20'd25179, "96 kHz ACR");
    check_acr(acr192_sub[0], 20'd24576, 20'd25179, "192 kHz ACR");
    check_acr(acr_round_low_sub[0], 20'd6144, 20'd25178, "below half-integer CTS");
    check_acr(acr_round_high_sub[0], 20'd6144, 20'd25179, "at half-integer CTS");
    check_acr(acr_max_sub[0], 20'd6144, 20'd1048575, "maximum 20-bit CTS");
    check_acr(acr_profile48_sub[0], 20'd6144, 20'd25179, "static VGA 48 kHz ACR");
    check_acr(acr_profile96_sub[0], 20'd12288, 20'd25179, "static VGA 96 kHz ACR");
    check_acr(acr_profile192_sub[0], 20'd24576, 20'd25179, "static VGA 192 kHz ACR");
    profile_vic=8'd34; profile_pixel_clock=32'd25_178_571; #1;
    check_acr(acr_profile48_sub[0], 20'd6144, 20'd74250, "VIC34 48 kHz ACR ignores dynamic clock bus");
    check_acr(acr_profile96_sub[0], 20'd12288, 20'd74250, "VIC34 96 kHz ACR ignores dynamic clock bus");
    check_acr(acr_profile192_sub[0], 20'd24576, 20'd74250, "VIC34 192 kHz ACR ignores dynamic clock bus");
    profile_vic=8'd16; profile_pixel_clock=32'd60_000_000; #1;
    check_acr(acr_profile48_sub[0], 20'd6144, 20'd148500, "VIC16 48 kHz ACR ignores dynamic clock bus");
    check_acr(acr_profile96_sub[0], 20'd12288, 20'd148500, "VIC16 96 kHz ACR ignores dynamic clock bus");
    check_acr(acr_profile192_sub[0], 20'd24576, 20'd148500, "VIC16 192 kHz ACR ignores dynamic clock bus");
    profile_vic=8'd0; #1;
    check_acr(acr_profile48_sub[0], 20'd6144, 20'd0, "unsupported VIC fails closed");
    check(acr48_sub[1] === acr48_sub[0] && acr48_sub[2] === acr48_sub[0] &&
          acr48_sub[3] === acr48_sub[0], "ACR values must repeat in all four subpackets");

    $display("TEST_PASS: hdmi_audio_packets, 24-bit payloads, InfoFrames, channel status, ACR profiles/rounding/range");
    $finish;
  end
endmodule
