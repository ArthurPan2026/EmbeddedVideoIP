`timescale 1ns/1ps
module tb_hdmi_packet_assembler;
  logic pixel_clk=0, resetn=0;
  logic packet_valid=0, packet_ready, packet_cancel=0, packet_cancel_link=0;
  logic packet_start=0, packet_loaded, packet_active, packet_done;
  logic [23:0] header;
  logic [55:0] sub0,sub1,sub2,sub3;
  logic [8:0] packet_data;
  logic [31:0] header_block;
  logic [63:0] bch0,bch1,bch2,bch3;
  logic [7:0] header_ecc, ecc0,ecc1,ecc2,ecc3;
  integer i;
  logic static_valid=0, static_ready, static_start=0, static_loaded;
  logic static_active, static_done;
  logic [23:0] static_header;
  logic [55:0] static_sub [0:3];
  logic [8:0] static_data;
  logic [7:0] static_header_ecc;
  logic [7:0] static_sub_ecc [0:3];
  logic [31:0] static_header_block;
  logic [63:0] static_bch_block [0:3];
  integer static_index;
  always #5 pixel_clk=~pixel_clk;

  hdmi_bch_ecc #(.DATA_WIDTH(24)) ref_h(.data_in(header),.ecc_out(header_ecc));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref0(.data_in(sub0),.ecc_out(ecc0));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref1(.data_in(sub1),.ecc_out(ecc1));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref2(.data_in(sub2),.ecc_out(ecc2));
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref3(.data_in(sub3),.ecc_out(ecc3));
  hdmi_packet_assembler dut(
    .pixel_clk(pixel_clk),.resetn(resetn),.packet_valid(packet_valid),.packet_ready(packet_ready),.packet_cancel(packet_cancel),.packet_cancel_link(packet_cancel_link),
    .packet_start(packet_start),.packet_loaded(packet_loaded),
    .packet_header(header),.packet_sub0(sub0),.packet_sub1(sub1),.packet_sub2(sub2),.packet_sub3(sub3),
    .packet_active(packet_active),.packet_data(packet_data),.packet_done(packet_done)
  );

  hdmi_avi_infoframe u_static_avi (
    .video_vic(8'd1), .header(static_header), .subpacket(static_sub)
  );
  hdmi_bch_ecc #(.DATA_WIDTH(24)) ref_static_header (
    .data_in(static_header), .ecc_out(static_header_ecc)
  );
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref_static_sub0 (
    .data_in(static_sub[0]), .ecc_out(static_sub_ecc[0])
  );
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref_static_sub1 (
    .data_in(static_sub[1]), .ecc_out(static_sub_ecc[1])
  );
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref_static_sub2 (
    .data_in(static_sub[2]), .ecc_out(static_sub_ecc[2])
  );
  hdmi_bch_ecc #(.DATA_WIDTH(56)) ref_static_sub3 (
    .data_in(static_sub[3]), .ecc_out(static_sub_ecc[3])
  );
  always_comb begin
    static_header_block = {static_header_ecc, static_header};
    static_bch_block[0] = {static_sub_ecc[0], static_sub[0]};
    static_bch_block[1] = {static_sub_ecc[1], static_sub[1]};
    static_bch_block[2] = {static_sub_ecc[2], static_sub[2]};
    static_bch_block[3] = {static_sub_ecc[3], static_sub[3]};
  end
  hdmi_packet_assembler #(.STATIC_AVI_ONLY(1'b1)) static_dut (
    .pixel_clk(pixel_clk), .resetn(resetn),
    .packet_valid(static_valid), .packet_ready(static_ready),
    .packet_cancel(1'b0), .packet_cancel_link(1'b0),
    .packet_start(static_start), .packet_loaded(static_loaded),
    .packet_header(static_header), .packet_sub0(static_sub[0]),
    .packet_sub1(static_sub[1]), .packet_sub2(static_sub[2]),
    .packet_sub3(static_sub[3]), .packet_active(static_active),
    .packet_data(static_data), .packet_done(static_done)
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
    // Audio cancellation must preserve AVI; link cancellation must clear it.
    @(negedge pixel_clk); header=24'h0D0282; packet_valid=1;
    @(posedge pixel_clk);
    @(negedge pixel_clk); packet_valid=0; packet_cancel=1;
    @(posedge pixel_clk);
    @(negedge pixel_clk);
    if (!packet_loaded) fail("audio disable must preserve pending AVI InfoFrame");
    packet_cancel=0; packet_cancel_link=1;
    @(posedge pixel_clk);
    @(negedge pixel_clk);
    if (packet_loaded) fail("DVI link switch must cancel pending AVI packet");
    // The audio-off specialization streams its constant AVI payload without
    // loading the general packet data registers, while preserving BCH mapping.
    @(negedge pixel_clk); static_valid=1;
    @(posedge pixel_clk);
    @(negedge pixel_clk); static_valid=0;
    if (!static_loaded || static_ready)
      fail("static AVI profile failed to latch its packet state");
    static_start=1;
    @(posedge pixel_clk);
    @(negedge pixel_clk); static_start=0;
    for (i=0;i<32;i=i+1) begin
      #1;
      if (!static_active) fail("static AVI packet ended before 32 pixels");
      if (static_data[8] !== static_header_block[i])
        fail("static AVI header BCH bit mapping mismatch");
      if (static_data[3:0] !== {static_bch_block[3][2*i],static_bch_block[2][2*i],
                                static_bch_block[1][2*i],static_bch_block[0][2*i]})
        fail("static AVI even payload BCH mapping mismatch");
      if (static_data[7:4] !== {static_bch_block[3][2*i+1],static_bch_block[2][2*i+1],
                                static_bch_block[1][2*i+1],static_bch_block[0][2*i+1]})
        fail("static AVI odd payload BCH mapping mismatch");
      @(posedge pixel_clk);
    end
    @(negedge pixel_clk);
    if (static_active || static_loaded || !static_done)
      fail("static AVI packet did not complete after 32 pixels");

    $display("TEST_PASS: hdmi_packet_assembler");
    $finish;
  end
endmodule
