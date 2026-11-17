`timescale 1ns/1ps
module tb_hdmi_gain_bus_cdc;
  logic src_clk = 1'b0;
  logic dst_clk = 1'b0;
  logic src_resetn = 1'b0;
  logic dst_resetn = 1'b0;
  logic [16:0] src_gain_q15 = 17'd32768;
  logic [16:0] dst_gain_q15;
  logic [16:0] last_gain = 17'd32768;
  integer observed_changes = 0;

  always #5 src_clk = ~src_clk;
  always #17 dst_clk = ~dst_clk;

  hdmi_gain_bus_cdc dut (
    .src_clk(src_clk), .src_resetn(src_resetn),
    .src_gain_q15(src_gain_q15),
    .dst_clk(dst_clk), .dst_resetn(dst_resetn),
    .dst_gain_q15(dst_gain_q15)
  );

  always @(posedge dst_clk) begin
    if (dst_resetn && (dst_gain_q15 !== last_gain)) begin
      if ((dst_gain_q15 !== 17'd32768) &&
          (dst_gain_q15 !== 17'd10000) &&
          (dst_gain_q15 !== 17'd12345) &&
          (dst_gain_q15 !== 17'd30000) &&
          (dst_gain_q15 !== 17'd22222))
        $fatal(1, "gain bus tore across CDC: %0d", dst_gain_q15);
      last_gain <= dst_gain_q15;
      observed_changes <= observed_changes + 1;
    end
  end

  task automatic wait_gain(input logic [16:0] expected);
    integer cycles;
    begin
      cycles = 0;
      while ((dst_gain_q15 !== expected) && (cycles < 60)) begin
        @(posedge dst_clk);
        cycles = cycles + 1;
      end
      if (dst_gain_q15 !== expected)
        $fatal(1, "gain CDC timeout: expected %0d, got %0d", expected, dst_gain_q15);
    end
  endtask

  initial begin
    #13;
    src_resetn = 1'b1;
    dst_resetn = 1'b1;
    repeat (4) @(posedge dst_clk);
    if (dst_gain_q15 !== 17'd32768)
      $fatal(1, "gain CDC reset value mismatch");

    @(negedge src_clk);
    src_gain_q15 = 17'd10000;
    wait_gain(17'd10000);

    // Updates while a previous transfer may still be returning its ACK must
    // be delivered as complete values, with the latest value eventually applied.
    @(negedge src_clk);
    src_gain_q15 = 17'd12345;
    repeat (2) @(negedge src_clk);
    src_gain_q15 = 17'd30000;
    wait_gain(17'd30000);

    @(negedge src_clk);
    src_gain_q15 = 17'd22222;
    wait_gain(17'd22222);
    repeat (4) @(posedge src_clk);
    @(negedge dst_clk);
    dst_resetn = 1'b0;
    repeat (3) @(posedge dst_clk);
    if (dst_gain_q15 !== 17'd32768)
      $fatal(1, "pixel reset did not clear destination gain state");
    @(negedge dst_clk);
    dst_resetn = 1'b1;
    wait_gain(17'd22222);
    if (observed_changes < 4)
      $fatal(1, "gain CDC did not report expected updates");
    $display("TEST_PASS: tb_hdmi_gain_bus_cdc");
    $finish;
  end

  initial begin
    #20us;
    $fatal(1, "TEST_FAIL: gain CDC timeout");
  end
endmodule
