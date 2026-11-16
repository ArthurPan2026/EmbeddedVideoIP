`timescale 1ns/1ps
module tb_audio_pcm_async_fifo;
  localparam int DEPTH = 16;
  logic wr_clk=0, rd_clk=0;
  logic wr_resetn=0, rd_resetn=0;
  logic wr_clear=0, rd_clear=0;
  logic [31:0] wr_data=0, rd_data;
  logic wr_valid=0, wr_ready, wr_full, rd_valid, rd_ready=0, rd_empty;
  logic [4:0] wr_level, rd_level;
  integer i;

  always #5 wr_clk = ~wr_clk;
  always #7 rd_clk = ~rd_clk;

  audio_pcm_async_fifo #(.DATA_WIDTH(32), .ADDR_WIDTH(4)) dut (
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

  initial begin
    repeat(4) @(posedge wr_clk);
    wr_resetn=1;
    rd_resetn=1;
    repeat(4) @(posedge rd_clk);
    if (!rd_empty || wr_full) fail("FIFO reset flags invalid");

    // 暂停读时钟，向FIFO写入至容量上限。
    for (i=0; i<DEPTH; i=i+1) begin
      @(negedge wr_clk);
      wr_valid=1;
      wr_data=32'hA5000000+i;
      do @(posedge wr_clk); while(!wr_ready);
    end
    @(negedge wr_clk);
    wr_valid=1;
    wr_data=32'hDEADBEEF;
    repeat(2) @(posedge wr_clk);
    if (!wr_full || wr_ready) fail("FIFO did not apply full backpressure");
    @(negedge wr_clk);
    wr_valid=0;

    // 以较慢时钟按顺序读出已有数据。
    @(negedge rd_clk);
    rd_ready=1;
    for (i=0; i<DEPTH; i=i+1) begin
      do @(posedge rd_clk); while(!rd_valid);
      if (rd_data !== (32'hA5000000+i)) fail("FIFO data order/value mismatch");
    end
    @(negedge rd_clk);
    rd_ready=0;
    repeat(4) @(posedge rd_clk);
    if (!rd_empty) fail("FIFO did not become empty after drain");

    // 停止流量后在路由切换边界清除两个时钟域的指针。
    @(negedge wr_clk); wr_clear=1;
    @(negedge rd_clk); rd_clear=1;
    @(negedge wr_clk); wr_clear=0;
    @(negedge rd_clk); rd_clear=0;
    repeat(4) @(posedge wr_clk);
    repeat(4) @(posedge rd_clk);
    if (!rd_empty || wr_full || wr_level!=0 || rd_level!=0)
      fail("FIFO clear did not reset both pointers");
    $display("TEST_PASS: audio_pcm_async_fifo");
    $finish;
  end
endmodule
