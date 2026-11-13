`timescale 1ns/1ps
`timescale 1ns/1ps
module tb_video_bram_rgb565_reader;
  logic clk=0;
  logic rst_n=0;
  always #5 clk=~clk;

  logic frame_start=0;
  logic [31:0] frame_base=0;
  logic [15:0] frame_width=2, frame_height=2;
  logic [31:0] stride_bytes=4;
  wire bram_en;
  wire [3:0] bram_addr;
  logic [31:0] bram_dout=0;
  wire [31:0] m_data;
  wire m_valid;
  logic m_ready=1;
  wire m_user, m_last, busy, frame_done;
  logic clear_errors=0;
  wire [31:0] errors;
  logic [31:0] mem[0:3];
  logic [23:0] expected[0:3];
  integer index=0;
  integer cycles=0;

  video_bram_rgb565_reader #(.MAX_WIDTH(4),.MAX_HEIGHT(4),.BRAM_ADDR_WIDTH(4)) dut(
    .aclk(clk),.aresetn(rst_n),.frame_start(frame_start),
    .frame_base_word(frame_base),.frame_width(frame_width),
    .frame_height(frame_height),.frame_stride_bytes(stride_bytes),
    .bram_en(bram_en),.bram_addr(bram_addr),.bram_dout(bram_dout),
    .m_axis_tdata(m_data),.m_axis_tvalid(m_valid),.m_axis_tready(m_ready),
    .m_axis_tuser(m_user),.m_axis_tlast(m_last),.busy(busy),
    .frame_done(frame_done),.clear_errors(clear_errors),.error_flags(errors)
  );

  always @(posedge clk) begin
    cycles <= cycles + 1;
    m_ready <= (cycles % 4 != 1);
    if (bram_en) bram_dout <= mem[bram_addr];
    if (m_valid && m_ready) begin
      if (index >= 4) $fatal(1,"TEST_FAIL: extra BRAM pixel");
      if (m_data[23:0] !== expected[index])
        $fatal(1,"TEST_FAIL: pixel %0d got %h expected %h",index,m_data[23:0],expected[index]);
      if (m_user !== (index==0)) $fatal(1,"TEST_FAIL: SOF mismatch");
      if (m_last !== ((index%2)==1)) $fatal(1,"TEST_FAIL: EOL mismatch");
      index <= index+1;
    end
  end

  initial begin
    #1ms;
    $fatal(1,"TEST_FAIL: watchdog timeout");
  end

  initial begin
    mem[0]=32'h07E0F800; // low RGB565 red, high green
    mem[1]=32'hFFFF001F; // low blue, high white
    expected[0]=24'hFF0000;
    expected[1]=24'h00FF00;
    expected[2]=24'h0000FF;
    expected[3]=24'hFFFFFF;

    repeat(4) @(negedge clk);
    rst_n=1;
    @(negedge clk);
    frame_start=1;
    @(negedge clk);
    frame_start=0;
    wait(frame_done);
    if(index!=4 || errors!=0) $fatal(1,"TEST_FAIL: BRAM frame/status mismatch");

    @(negedge clk);
    stride_bytes=2;
    frame_start=1;
    @(negedge clk);
    frame_start=0;
    repeat(2) @(negedge clk);
    if(!errors[0]) $fatal(1,"TEST_FAIL: bad BRAM stride not diagnosed");

    $display("TEST_PASS: tb_video_bram_rgb565_reader");
    $finish;
  end
endmodule
