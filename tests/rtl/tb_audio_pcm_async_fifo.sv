`timescale 1ns/1ps
module tb_audio_pcm_async_fifo;
  localparam int DEPTH = 16;
  logic wr_clk=0, rd_clk=0;
  logic wr_resetn=0, rd_resetn=0;
  logic wr_clear=0, rd_clear=0;
  logic [47:0] wr_data=0, rd_data;
  logic wr_valid=0, wr_ready, wr_full, rd_valid, rd_ready=0, rd_empty;
  logic [4:0] wr_level, rd_level;
  logic [47:0] expected [0:DEPTH-1];
  integer i;
  integer read_index=0;
  integer timeout;

  always #5 wr_clk = ~wr_clk;
  always #7 rd_clk = ~rd_clk;

  audio_pcm_async_fifo #(.DATA_WIDTH(48), .ADDR_WIDTH(4)) dut (
    .wr_clk(wr_clk), .wr_resetn(wr_resetn), .wr_clear(wr_clear),
    .wr_data(wr_data), .wr_valid(wr_valid), .wr_ready(wr_ready),
    .wr_full(wr_full), .wr_level(wr_level),
    .rd_clk(rd_clk), .rd_resetn(rd_resetn), .rd_clear(rd_clear),
    .rd_data(rd_data), .rd_valid(rd_valid), .rd_ready(rd_ready),
    .rd_empty(rd_empty), .rd_level(rd_level)
  );

  task automatic fail(input string msg);
    $fatal(1, "%s", msg);
  endtask

  always @(posedge rd_clk) begin
    if (rd_resetn && rd_valid && rd_ready && read_index < DEPTH) begin
      if (rd_data !== expected[read_index])
        $fatal(1, "FIFO 48-bit order/value mismatch at %0d: got %h expected %h",
               read_index, rd_data, expected[read_index]);
      read_index = read_index + 1;
    end
  end

  initial begin
    repeat(5) @(posedge wr_clk);
    wr_resetn=1;
    rd_resetn=1;
    repeat(5) @(posedge rd_clk);
    if (!rd_empty || wr_full) fail("FIFO reset flags invalid");

    // Fill all slots while reads are stalled, then prove an extra beat is backpressured.
    for (i=0; i<DEPTH; i=i+1) begin
      expected[i] = 48'hA50000000000 | 48'(i);
      @(negedge wr_clk);
      wr_valid=1;
      wr_data=expected[i];
      do @(posedge wr_clk); while(!wr_ready);
    end
    @(negedge wr_clk);
    wr_valid=1;
    wr_data=48'hDEADBEEFCAFE;
    repeat(2) @(posedge wr_clk);
    if (!wr_full || wr_ready) fail("FIFO did not apply full backpressure");
    @(negedge wr_clk);
    wr_valid=0;

    // Drain in order with deterministic random read stalls; data must remain stable while stalled.
    @(negedge rd_clk);
    rd_ready=1;
    timeout=0;
    while (read_index < DEPTH && timeout < 500) begin
      @(negedge rd_clk);
      rd_ready = ($urandom_range(0,3) != 0);
      timeout=timeout+1;
    end
    if (read_index != DEPTH) fail("FIFO did not drain under randomized read stalls");
    @(negedge rd_clk);
    rd_ready=0;
    repeat(5) @(posedge rd_clk);
    if (!rd_empty) fail("FIFO did not become empty after drain");

    // Clearing both pointer domains discards any queued 48-bit samples.
    @(negedge wr_clk); wr_valid=1; wr_data=48'h111122223333;
    do @(posedge wr_clk); while(!wr_ready);
    @(negedge wr_clk); wr_valid=1; wr_data=48'h444455556666;
    do @(posedge wr_clk); while(!wr_ready);
    @(negedge wr_clk); wr_valid=0; wr_clear=1;
    @(negedge rd_clk); rd_clear=1;
    @(negedge wr_clk); wr_clear=0;
    @(negedge rd_clk); rd_clear=0;
    repeat(6) @(posedge wr_clk);
    repeat(6) @(posedge rd_clk);
    if (!rd_empty || wr_full || wr_level!=0 || rd_level!=0)
      fail("FIFO clear did not reset both pointers and levels");

    // A post-flush token is new data, not one of the discarded entries.
    @(negedge wr_clk); wr_valid=1; wr_data=48'hABCDEF123456;
    do @(posedge wr_clk); while(!wr_ready);
    @(negedge wr_clk); wr_valid=0;
    repeat(4) @(posedge rd_clk);
    @(negedge rd_clk); rd_ready=1;
    do @(posedge rd_clk); while(!rd_valid);
    if (rd_data !== 48'hABCDEF123456) fail("FIFO exposed stale data after clear");
    @(negedge rd_clk); rd_ready=0;
    repeat(5) @(posedge rd_clk);
    if (!rd_empty) fail("FIFO did not empty after post-clear token");

    $display("TEST_PASS: audio_pcm_async_fifo, 48-bit full/empty/backpressure/random-stall/clear");
    $finish;
  end
endmodule
