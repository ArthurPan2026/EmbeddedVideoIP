`timescale 1ns/1ps
// HDMI 1.4b AVI InfoFrame for the fixed VIC 1 RGB 8-bit output profile.
module hdmi_avi_infoframe (
  output logic [23:0] header,
  output logic [55:0] subpacket [0:3]
);
  logic [7:0] payload [0:27];
  logic [7:0] checksum_sum;
  integer i;

  always_comb begin
    // Header bytes are transmitted low byte first: HB0, HB1, HB2.
    header = {8'h0D, 8'h02, 8'h82};
    for (i = 0; i < 28; i = i + 1)
      payload[i] = 8'h00;
    // PB1: A=1, no bar/scan flags, RGB. PB2: default colorimetry, 4:3 picture,
    // with active-format aspect equal to the picture aspect.
    payload[1] = 8'h20;
    payload[2] = 8'h18;
    // PB3: full RGB range for VGA. PB4: VIC 1; pixel repetition is zero.
    payload[3] = 8'h08;
    payload[4] = 8'h01;
    checksum_sum = header[7:0] + header[15:8] + header[23:16];
    for (i = 1; i < 13; i = i + 1)
      checksum_sum = checksum_sum + payload[i];
    payload[0] = -checksum_sum;
    for (i = 0; i < 4; i = i + 1)
      subpacket[i] = {payload[6 + i*7], payload[5 + i*7], payload[4 + i*7],
                      payload[3 + i*7], payload[2 + i*7], payload[1 + i*7],
                      payload[0 + i*7]};
  end
endmodule
