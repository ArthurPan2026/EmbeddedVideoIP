`timescale 1ns/1ps
module tb_hdmi_packet_assembler;
  logic pixel_clk=0, resetn=0;
  logic packet_valid=0, packet_ready, packet_cancel=0, packet_start=0, packet_loaded, packet_active, packet_done;
  logic [23:0] header;
  logic [55:0] sub0,sub1,sub2,sub3;
  logic [8:0] packet_data;
  logic [31:0] header_block;
  logic [63:0] bch0,bch1,bch2,bch3;
  logic [7:0] header_ecc, ecc0,ecc1,ecc2,ecc3;
  integer i;
  always #5 pixel_clk=~pixel_clk;

  hdmi_bch_ecc #(.DATA_WIDTH(24)) ref_h(.data_in(header),.ecc_out(header_ecc));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref0(.data_in(sub0),.ecc_out(ecc0));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref1(.data_in(sub1),.ecc_out(ecc1));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref2(.data_in(sub2),.ecc_out(ecc2));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref3(.data_in(sub3),.ecc_out(ecc3));
  hdmi_packet_assembler dut(
    .pixel_clk(pixel_clk),.resetn(resetn),.packet_valid(packet_valid),.packet_ready(packet_ready),.packet_cancel(packet_cancel),
    .packet_start(packet_start),.packet_loaded(packet_loaded),
    .packet_header(header),.packet_sub0(sub0),.packet_sub1(sub1),.packet_sub2(sub2),.packet_sub3(sub3),
    .packet_active(packet_active),.packet_data(packet_data),.packet_done(packet_done)
  );

  task automatic fail(input string msg); $fatal(1,"%s",msg); endtask
  initial begin
    header=24'h0A0184;
    sub0=56'h0123456789ABCD;
    sub1=56'hFEEDC0DE123456;
    sub2=56'h00010203040506;
    sub3=56'hFEDCBA98765432;
    repeat(3) @(posedge pixel_clk);
    resetn=1;
    @(negedge pixel_clk); packet_valid=1;
    @(posedge pixel_clk);
    if(!packet_ready) fail("packet should accept first transaction");
    @(negedge pixel_clk); packet_valid=0;
    if (!packet_loaded || packet_active) fail("packet registers did not load without starting payload");
    header_block={header_ecc,header};
    bch0={ecc0,sub0}; bch1={ecc1,sub1}; bch2={ecc2,sub2}; bch3={ecc3,sub3};
    packet_start=1;
    @(posedge pixel_clk);
    @(negedge pixel_clk);
    packet_start=0;
    for(i=0;i<32;i=i+1) begin
      #1;
      if(!packet_active) fail("packet ended before 32 pixels");
      if(packet_data[8] !== header_block[i]) fail("header bit mapping mismatch");
      if(packet_data[3:0] !== {bch3[2*i],bch2[2*i],bch1[2*i],bch0[2*i]})
        fail("even packet body bit mapping mismatch");
      if(packet_data[7:4] !== {bch3[2*i+1],bch2[2*i+1],bch1[2*i+1],bch0[2*i+1]})
        fail("odd packet body bit mapping mismatch");
      @(posedge pixel_clk);
    end
    @(negedge pixel_clk);
    if(packet_active || packet_loaded || !packet_done) fail("packet done pulse missing");
    $display("TEST_PASS: hdmi_packet_assembler");
    $finish;
  end
endmodule
