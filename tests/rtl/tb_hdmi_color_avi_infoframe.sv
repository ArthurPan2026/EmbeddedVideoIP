`timescale 1ns/1ps
module tb_hdmi_color_avi_infoframe;
  logic [23:0] h_rgb, h_601_l, h_601_f, h_709_l, h_709_f;
  logic [7:0] video_vic=8'd1;
  logic [55:0] s_rgb [0:3];
  logic [55:0] s_601_l [0:3], s_601_f [0:3];
  logic [55:0] s_709_l [0:3], s_709_f [0:3];
  hdmi_avi_infoframe u_rgb_default (.video_vic(video_vic), .header(h_rgb), .subpacket(s_rgb));
  hdmi_avi_infoframe #(.COLOR_MODE(1), .COLORIMETRY(0), .YCC_RANGE(0)) u_601_limited (
    .video_vic(video_vic), .header(h_601_l), .subpacket(s_601_l)
  );
  hdmi_avi_infoframe #(.COLOR_MODE(1), .COLORIMETRY(0), .YCC_RANGE(1)) u_601_full (
    .video_vic(video_vic), .header(h_601_f), .subpacket(s_601_f)
  );
  hdmi_avi_infoframe #(.COLOR_MODE(1), .COLORIMETRY(1), .YCC_RANGE(0)) u_709_limited (
    .video_vic(video_vic), .header(h_709_l), .subpacket(s_709_l)
  );
  hdmi_avi_infoframe #(.COLOR_MODE(1), .COLORIMETRY(1), .YCC_RANGE(1)) u_709_full (
    .video_vic(video_vic), .header(h_709_f), .subpacket(s_709_f)
  );

  function automatic logic [7:0] payload_byte(
    input integer index,
    input logic [55:0] p0,
    input logic [55:0] p1,
    input logic [55:0] p2,
    input logic [55:0] p3
  );
    integer byte_in_packet;
    begin
      byte_in_packet = index % 7;
      case (index / 7)
        0: payload_byte = p0[byte_in_packet*8 +: 8];
        1: payload_byte = p1[byte_in_packet*8 +: 8];
        2: payload_byte = p2[byte_in_packet*8 +: 8];
        default: payload_byte = p3[byte_in_packet*8 +: 8];
      endcase
    end
  endfunction

  task automatic check_profile(
    input logic [23:0] header,
    input logic [55:0] p0,
    input logic [55:0] p1,
    input logic [55:0] p2,
    input logic [55:0] p3,
    input logic [7:0] expected_pb1,
    input logic [7:0] expected_pb2,
    input logic [7:0] expected_pb3,
    input logic [7:0] expected_pb4,
    input logic [7:0] expected_pb5,
    input string profile_name
  );
    logic [7:0] checksum;
    integer byte_index;
    begin
      if (header !== 24'h0D0282)
        $fatal(1, "%s AVI header/order mismatch: %06h", profile_name, header);
      if ((p0[15:8] !== expected_pb1) || (p0[23:16] !== expected_pb2) ||
          (p0[31:24] !== expected_pb3) || (p0[39:32] !== expected_pb4) ||
          (p0[47:40] !== expected_pb5))
        $fatal(1, "%s AVI payload mismatch: PB1..5=%02h/%02h/%02h/%02h/%02h",
               profile_name, p0[15:8], p0[23:16], p0[31:24], p0[39:32], p0[47:40]);

      // HDMI transmits HB0..HB2 then PB0..PB12 low byte first. The checksum
      // must make their modulo-256 sum zero for each selected color profile.
      checksum = header[7:0] + header[15:8] + header[23:16];
      for (byte_index=0; byte_index<13; byte_index=byte_index+1)
        checksum = checksum + payload_byte(byte_index, p0, p1, p2, p3);
      if (checksum !== 8'h00)
        $fatal(1, "%s AVI checksum failed: sum=%02h", profile_name, checksum);
    end
  endtask

  initial begin
    #1;
    check_profile(h_rgb, s_rgb[0], s_rgb[1], s_rgb[2], s_rgb[3],
                  8'h10, 8'h18, 8'h08, 8'h01, 8'h00, "RGB8 VIC1");
    check_profile(h_601_l, s_601_l[0], s_601_l[1], s_601_l[2], s_601_l[3],
                  8'h50, 8'h58, 8'h00, 8'h01, 8'h00, "YCbCr444 BT.601 limited VIC1");
    check_profile(h_601_f, s_601_f[0], s_601_f[1], s_601_f[2], s_601_f[3],
                  8'h50, 8'h58, 8'h00, 8'h01, 8'h40, "YCbCr444 BT.601 full VIC1");
    check_profile(h_709_l, s_709_l[0], s_709_l[1], s_709_l[2], s_709_l[3],
                  8'h50, 8'h98, 8'h00, 8'h01, 8'h00, "YCbCr444 BT.709 limited VIC1");
    check_profile(h_709_f, s_709_f[0], s_709_f[1], s_709_f[2], s_709_f[3],
                  8'h50, 8'h98, 8'h00, 8'h01, 8'h40, "YCbCr444 BT.709 full VIC1");

    video_vic=8'd4; #1;
    check_profile(h_rgb,s_rgb[0],s_rgb[1],s_rgb[2],s_rgb[3],8'h10,8'h28,8'h08,8'h04,8'h00,"RGB8 VIC4");
    check_profile(h_601_l,s_601_l[0],s_601_l[1],s_601_l[2],s_601_l[3],8'h50,8'h68,8'h00,8'h04,8'h00,"YCbCr601 VIC4");
    check_profile(h_709_l,s_709_l[0],s_709_l[1],s_709_l[2],s_709_l[3],8'h50,8'hA8,8'h00,8'h04,8'h00,"YCbCr709 VIC4");
    video_vic=8'd34; #1;
    check_profile(h_rgb,s_rgb[0],s_rgb[1],s_rgb[2],s_rgb[3],8'h10,8'h28,8'h08,8'h22,8'h00,"RGB8 VIC34");
    check_profile(h_601_f,s_601_f[0],s_601_f[1],s_601_f[2],s_601_f[3],8'h50,8'h68,8'h00,8'h22,8'h40,"YCbCr601 full VIC34");
    check_profile(h_709_f,s_709_f[0],s_709_f[1],s_709_f[2],s_709_f[3],8'h50,8'hA8,8'h00,8'h22,8'h40,"YCbCr709 full VIC34");
    video_vic=8'd16; #1;
    check_profile(h_rgb,s_rgb[0],s_rgb[1],s_rgb[2],s_rgb[3],8'h10,8'h28,8'h08,8'h10,8'h00,"RGB8 VIC16 1080p60");
    check_profile(h_601_l,s_601_l[0],s_601_l[1],s_601_l[2],s_601_l[3],8'h50,8'h68,8'h00,8'h10,8'h00,"YCbCr601 limited VIC16 1080p60");
    check_profile(h_601_f,s_601_f[0],s_601_f[1],s_601_f[2],s_601_f[3],8'h50,8'h68,8'h00,8'h10,8'h40,"YCbCr601 full VIC16 1080p60");
    check_profile(h_709_l,s_709_l[0],s_709_l[1],s_709_l[2],s_709_l[3],8'h50,8'hA8,8'h00,8'h10,8'h00,"YCbCr709 limited VIC16 1080p60");
    check_profile(h_709_f,s_709_f[0],s_709_f[1],s_709_f[2],s_709_f[3],8'h50,8'hA8,8'h00,8'h10,8'h40,"YCbCr709 full VIC16 1080p60");
    $display("TEST_PASS: hdmi_color_avi_infoframe color profiles, runtime VIC/aspect, byte order, checksum");
    $finish;
  end
endmodule
