`timescale 1ns/1ps
module tb_hdmi_7series_output_serdes;
  logic pixel_clk = 1'b0;
  logic serial_clk = 1'b0;
  logic areset = 1'b1;
  logic [9:0] parallel_data = 10'd0;
  logic serial_p, serial_n;
  integer words_checked = 0;

  always #10 pixel_clk = ~pixel_clk;
  initial begin
    #1;
    forever #2 serial_clk = ~serial_clk;
  end

  hdmi_7series_output_serdes #(.PARALLEL_WIDTH(10)) dut (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .areset(areset),
    .parallel_data(parallel_data), .serial_p(serial_p), .serial_n(serial_n)
  );

  task automatic check_word(input logic [9:0] word_bits);
    integer bit_number;
    begin
      @(negedge pixel_clk);
      parallel_data = word_bits;
      @(posedge pixel_clk);
`ifdef SYNTHESIS
      // OSERDESE2 DATA_WIDTH=10 DDR has five SerialClk cycles of input-to-
      // output latency. This branch is used only with the actual UNISIM
      // primitive, never as a substitute for implementation timing analysis.
      repeat (5) @(posedge serial_clk);
`endif
      #0.1;
      for (bit_number=0; bit_number<10; bit_number=bit_number+1) begin
        if ((serial_p !== word_bits[bit_number]) ||
            (serial_n !== ~word_bits[bit_number]))
          $fatal(1, "OSERDES bit order/differential mismatch at D%0d: P/N=%b/%b expected=%b",
                 bit_number+1, serial_p, serial_n, word_bits[bit_number]);
        if (bit_number < 9) begin
          @(serial_clk);
          #0.1;
        end
      end
      words_checked = words_checked + 1;
    end
  endtask

  initial begin
`ifndef SYNTHESIS
    #0.1;
    if ((serial_p !== 1'b0) || (serial_n !== 1'b1))
      $fatal(1, "OSERDES reset output must be deterministic and complementary");
`else
    repeat (2) @(posedge pixel_clk);
`endif
    repeat (2) @(posedge pixel_clk);
    @(negedge pixel_clk);
    areset = 1'b0;

    // Distinct and asymmetric symbols expose MSB/LSB reversal and skipped
    // cascade bits. The wrapper must serialize D1..D10, i.e. symbol bit 0..9.
    check_word(10'b1011000101);
    check_word(10'b0100111010);
    check_word(10'b1111100000);

    // Assert reset with a word in flight, then verify the next frame starts
    // again at bit 0 and the P/N outputs remain complementary.
    @(negedge pixel_clk);
    areset = 1'b1;
`ifndef SYNTHESIS
    #0.1;
`else
    repeat (2) @(posedge serial_clk);
    #0.1;
`endif
    if ((serial_p !== 1'b0) || (serial_n !== 1'b1))
      $fatal(1, "OSERDES asynchronous reset boundary failed");
    @(negedge pixel_clk);
    areset = 1'b0;
    check_word(10'b0110100101);

    if (words_checked != 4)
      $fatal(1, "Expected four serialized words, got %0d", words_checked);
    $display("TEST_PASS: hdmi_7series_output_serdes words=%0d bit_order=LSB-first", words_checked);
    $finish;
  end
endmodule
