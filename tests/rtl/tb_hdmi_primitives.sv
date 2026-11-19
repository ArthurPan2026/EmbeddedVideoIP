`timescale 1ns/1ps
module tb_hdmi_primitives;
  logic signed [23:0] sample_in;
  logic [16:0] gain_q15;
  logic mute;
  logic signed [23:0] sample_out;
  logic [3:0] nibble;
  logic [9:0] terc4;
  logic [23:0] bch24_input;
  logic [7:0] bch24_ecc;
  logic [55:0] bch56_input;
  logic [7:0] bch56_ecc;
  logic [9:0] expected_terc4 [0:15];
  integer i;

  audio_gain_q15 dut_gain(.sample_in(sample_in), .gain_q15(gain_q15), .mute(mute), .sample_out(sample_out));
  hdmi_terc4_encoder dut_terc(.nibble(nibble), .symbol(terc4));
  hdmi_bch_ecc #(.DATA_WIDTH(24)) dut_bch24(.data_in(bch24_input), .ecc_out(bch24_ecc));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) dut_bch56(.data_in(bch56_input), .ecc_out(bch56_ecc));

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) $fatal(1, "%s", message);
    end
  endtask

  initial begin
    expected_terc4[ 0]=10'b1010011100; expected_terc4[ 1]=10'b1001100011;
    expected_terc4[ 2]=10'b1011100100; expected_terc4[ 3]=10'b1011100010;
    expected_terc4[ 4]=10'b0101110001; expected_terc4[ 5]=10'b0100011110;
    expected_terc4[ 6]=10'b0110001110; expected_terc4[ 7]=10'b0100111100;
    expected_terc4[ 8]=10'b1011001100; expected_terc4[ 9]=10'b0100111001;
    expected_terc4[10]=10'b0110011100; expected_terc4[11]=10'b1011000110;
    expected_terc4[12]=10'b1010001110; expected_terc4[13]=10'b1001110001;
    expected_terc4[14]=10'b0101100011; expected_terc4[15]=10'b1011000011;
    for (i=0;i<16;i=i+1) begin
      nibble=i[3:0]; #1;
      check(terc4 === expected_terc4[i], "TERC4 lookup mismatch");
    end

    sample_in=-24'sd1234567; gain_q15=17'd32768; mute=1'b0; #1;
    check(sample_out === -24'sd1234567, "unity gain changed negative 24-bit sample");
    sample_in=24'sd1234567; gain_q15=17'd16384; #1;
    check(sample_out === 24'sd617283, "half gain positive truncation mismatch");
    sample_in=-24'sd1234567; #1;
    check(sample_out === -24'sd617284, "half gain negative arithmetic shift mismatch");
    sample_in=-24'sh800000; gain_q15=17'd32768; #1;
    check(sample_out === -24'sh800000, "negative full scale changed at unity");
    sample_in=24'sh7fffff; gain_q15=17'd65535; #1;
    check(sample_out === 24'sh7fffff, "gain above unity was not clamped");
    gain_q15=17'd0; mute=1'b0; #1;
    check(sample_out === 24'sd0, "zero gain did not zero PCM");
    gain_q15=17'd32768; mute=1'b1; #1;
    check(sample_out === 24'sd0, "mute did not zero PCM");

    bch24_input=24'h000001; #1;
    check(bch24_ecc === 8'h4A, "BCH(32,24) vector mismatch");
    bch24_input=24'hABCDEF; #1;
    check(bch24_ecc === 8'h3B, "BCH(32,24) second vector mismatch");
    bch56_input=56'h0123456789ABCD; #1;
    check(bch56_ecc === 8'h8F, "BCH(64,56) vector mismatch");
    bch56_input={56{1'b1}}; #1;
    check(bch56_ecc === 8'h6A, "BCH(64,56) all-one vector mismatch");

    $display("TEST_PASS: hdmi_primitives, 24-bit gain/mute/full-scale");
    $finish;
  end
endmodule
