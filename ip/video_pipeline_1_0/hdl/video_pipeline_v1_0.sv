`timescale 1ns/1ps
module video_pipeline_v1_0 #(
  parameter int unsigned MAX_INPUT_WIDTH = 640,
  parameter int unsigned MAX_INPUT_HEIGHT = 480,
  parameter int unsigned OUTPUT_WIDTH = 640,
  parameter int unsigned OUTPUT_HEIGHT = 480,
  parameter int unsigned BRAM_ADDR_WIDTH = 18,
  parameter int unsigned AXI_ADDR_WIDTH = 6
) (
  input logic aclk, input logic aresetn,

  // BRAM source: 32-bit words with two RGB565 pixels, low pixel first.
  output logic bram_en,
  output logic [BRAM_ADDR_WIDTH-1:0] bram_addr,
  input logic [31:0] bram_dout,
  output logic bram_busy,
  output logic bram_frame_done,

  // HLS and VDMA sources use one 32-bit beat per pixel, TUSER=SOF, TLAST=EOL.
  input logic [31:0] s_axis_hls_tdata,
  input logic s_axis_hls_tvalid,
  output logic s_axis_hls_tready,
  input logic s_axis_hls_tuser,
  input logic s_axis_hls_tlast,

  input logic [31:0] s_axis_vdma_tdata,
  input logic s_axis_vdma_tvalid,
  output logic s_axis_vdma_tready,
  input logic s_axis_vdma_tuser,
  input logic s_axis_vdma_tlast,

  // Processed RGB888 AXI4-Stream Video.
  output logic [23:0] m_axis_video_tdata,
  output logic m_axis_video_tvalid,
  input logic m_axis_video_tready,
  output logic m_axis_video_tuser,
  output logic m_axis_video_tlast,

  // AXI4-Lite control and status.
  input logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  input logic s_axi_awvalid,
  output logic s_axi_awready,
  input logic [31:0] s_axi_wdata,
  input logic [3:0] s_axi_wstrb,
  input logic s_axi_wvalid,
  output logic s_axi_wready,
  output logic [1:0] s_axi_bresp,
  output logic s_axi_bvalid,
  input logic s_axi_bready,
  input logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  input logic s_axi_arvalid,
  output logic s_axi_arready,
  output logic [31:0] s_axi_rdata,
  output logic [1:0] s_axi_rresp,
  output logic s_axi_rvalid,
  input logic s_axi_rready
);
  logic cfg_enable, cfg_scale, cfg_stretch;
  logic [1:0] cfg_source, cfg_format;
  logic [15:0] cfg_width, cfg_height;
  logic [31:0] cfg_stride, cfg_bram_base;
  logic cfg_commit, bram_start, clear_errors;
  logic [31:0] cfg_frame_count, cfg_error_flags;
  logic [9:0] req_active_width, req_active_height;
  logic [9:0] req_x_offset, req_y_offset, req_x_origin, req_y_origin;
  logic [9:0] req_x_step, req_x_rem, req_y_step, req_y_rem;
  logic [9:0] measured_active_width, measured_active_height;
  logic cfg_busy;

  logic active_enable, active_scale, active_stretch;
  logic [1:0] active_source, active_format;
  logic [15:0] active_width, active_height;
  logic [9:0] active_active_width, active_active_height;
  logic [9:0] active_x_offset, active_y_offset, active_x_origin, active_y_origin;
  logic [9:0] active_x_step, active_x_rem, active_y_step, active_y_rem;
  logic [31:0] active_stride, active_bram_base;
  logic cfg_pending;

  logic [31:0] bram_axis_tdata;
  logic bram_axis_tvalid, bram_axis_tready, bram_axis_tuser, bram_axis_tlast;
  logic [31:0] mux_tdata;
  logic mux_tvalid, mux_tready, mux_tuser, mux_tlast;
  logic [23:0] rgb_tdata;
  logic rgb_tvalid, rgb_source_ready, rgb_scaler_ready, rgb_tuser, rgb_tlast;
  logic [31:0] bram_error_flags;
  logic [31:0] scaler_error_flags;
  logic bram_start_pending, bram_start_reader;

  axi_lite_video_regs #(.ADDR_WIDTH(AXI_ADDR_WIDTH)) u_regs (
    .aclk(aclk), .aresetn(aresetn),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .cfg_enable(cfg_enable), .cfg_source(cfg_source), .cfg_scale_enable(cfg_scale),
    .cfg_stretch(cfg_stretch), .cfg_format(cfg_format), .cfg_width(cfg_width),
    .cfg_height(cfg_height), .cfg_stride_bytes(cfg_stride), .cfg_bram_base_word(cfg_bram_base),
    .cfg_active_width(req_active_width), .cfg_active_height(req_active_height),
    .cfg_x_offset(req_x_offset), .cfg_y_offset(req_y_offset),
    .cfg_source_x_origin(req_x_origin), .cfg_source_y_origin(req_y_origin),
    .cfg_x_step(req_x_step), .cfg_x_rem(req_x_rem), .cfg_y_step(req_y_step), .cfg_y_rem(req_y_rem),
    .cfg_commit(cfg_commit), .bram_start(bram_start), .clear_errors(clear_errors),
    .busy(cfg_busy), .bram_busy(bram_busy), .active_source(active_source),
    .active_width(measured_active_width), .active_height(measured_active_height),
    .frame_count(cfg_frame_count), .error_flags(cfg_error_flags)
  );

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      active_enable <= 1'b0;
      active_source <= 2'd0;
      active_scale <= 1'b0;
      active_stretch <= 1'b0;
      active_format <= 2'd1;
      active_width <= 16'd320;
      active_height <= 16'd240;
      active_stride <= 32'd640;
      active_bram_base <= 32'd0;
      active_active_width <= 10'd320; active_active_height <= 10'd240;
      active_x_offset <= 10'd160; active_y_offset <= 10'd120;
      active_x_origin <= '0; active_y_origin <= '0;
      active_x_step <= 10'd1; active_x_rem <= '0;
      active_y_step <= 10'd1; active_y_rem <= '0;
      cfg_pending <= 1'b0;
    end else begin
      if (cfg_commit)
        cfg_pending <= 1'b1;
      if ((cfg_commit || cfg_pending) && !cfg_busy) begin
        active_enable <= cfg_enable;
        active_source <= cfg_source;
        active_scale <= cfg_scale;
        active_stretch <= cfg_stretch;
        active_format <= cfg_format;
        active_width <= cfg_width;
        active_height <= cfg_height;
        active_stride <= cfg_stride;
        active_bram_base <= cfg_bram_base;
        active_active_width <= req_active_width; active_active_height <= req_active_height;
        active_x_offset <= req_x_offset; active_y_offset <= req_y_offset;
        active_x_origin <= req_x_origin; active_y_origin <= req_y_origin;
        active_x_step <= req_x_step; active_x_rem <= req_x_rem;
        active_y_step <= req_y_step; active_y_rem <= req_y_rem;
        cfg_pending <= 1'b0;
      end
    end
  end

  video_bram_rgb565_reader #(
    .MAX_WIDTH(MAX_INPUT_WIDTH),
    .MAX_HEIGHT(MAX_INPUT_HEIGHT),
    .BRAM_ADDR_WIDTH(BRAM_ADDR_WIDTH)
  ) u_bram_reader (
    .aclk(aclk), .aresetn(aresetn), .frame_start(bram_start_reader),
    .frame_base_word(active_bram_base), .frame_width(active_width),
    .frame_height(active_height), .frame_stride_bytes(active_stride),
    .bram_en(bram_en), .bram_addr(bram_addr), .bram_dout(bram_dout),
    .m_axis_tdata(bram_axis_tdata), .m_axis_tvalid(bram_axis_tvalid),
    .m_axis_tready(bram_axis_tready), .m_axis_tuser(bram_axis_tuser),
    .m_axis_tlast(bram_axis_tlast), .busy(bram_busy), .frame_done(bram_frame_done),
    .clear_errors(clear_errors), .error_flags(bram_error_flags)
  );

  axis_video_mux3 u_source_mux (
    .select(active_source),
    .s0_tdata(bram_axis_tdata), .s0_tvalid(bram_axis_tvalid), .s0_tready(bram_axis_tready),
    .s0_tuser(bram_axis_tuser), .s0_tlast(bram_axis_tlast),
    .s1_tdata(s_axis_hls_tdata), .s1_tvalid(s_axis_hls_tvalid), .s1_tready(s_axis_hls_tready),
    .s1_tuser(s_axis_hls_tuser), .s1_tlast(s_axis_hls_tlast),
    .s2_tdata(s_axis_vdma_tdata), .s2_tvalid(s_axis_vdma_tvalid), .s2_tready(s_axis_vdma_tready),
    .s2_tuser(s_axis_vdma_tuser), .s2_tlast(s_axis_vdma_tlast),
    .m_tdata(mux_tdata), .m_tvalid(mux_tvalid), .m_tready(mux_tready),
    .m_tuser(mux_tuser), .m_tlast(mux_tlast)
  );

  axis_rgb888 u_format (
    .s_axis_tdata(mux_tdata), .s_axis_tvalid(mux_tvalid && active_enable),
    .s_axis_tready(rgb_source_ready), .s_axis_tuser(mux_tuser), .s_axis_tlast(mux_tlast),
    .format((active_source == 2'd0) ? 2'd1 : active_format),
    .m_axis_tdata(rgb_tdata), .m_axis_tvalid(rgb_tvalid), .m_axis_tready(rgb_scaler_ready),
    .m_axis_tuser(rgb_tuser), .m_axis_tlast(rgb_tlast)
  );
  assign mux_tready = active_enable && rgb_source_ready;

  axis_video_nn_scaler #(
    .MAX_INPUT_WIDTH(MAX_INPUT_WIDTH), .MAX_INPUT_HEIGHT(MAX_INPUT_HEIGHT),
    .OUTPUT_WIDTH(OUTPUT_WIDTH), .OUTPUT_HEIGHT(OUTPUT_HEIGHT)
  ) u_scaler (
    .aclk(aclk), .aresetn(aresetn),
    .cfg_width(active_width), .cfg_height(active_height),
    .cfg_active_width(active_active_width), .cfg_active_height(active_active_height),
    .cfg_x_offset(active_x_offset), .cfg_y_offset(active_y_offset),
    .cfg_source_x_origin(active_x_origin), .cfg_source_y_origin(active_y_origin),
    .cfg_x_step(active_x_step), .cfg_x_rem(active_x_rem),
    .cfg_y_step(active_y_step), .cfg_y_rem(active_y_rem), .clear_errors(clear_errors),
    .s_axis_tdata(rgb_tdata), .s_axis_tvalid(rgb_tvalid),
    .s_axis_tready(rgb_scaler_ready), .s_axis_tuser(rgb_tuser), .s_axis_tlast(rgb_tlast),
    .m_axis_tdata(m_axis_video_tdata), .m_axis_tvalid(m_axis_video_tvalid),
    .m_axis_tready(m_axis_video_tready), .m_axis_tuser(m_axis_video_tuser),
    .m_axis_tlast(m_axis_video_tlast), .busy(cfg_busy), .frame_count(cfg_frame_count),
    .error_flags(scaler_error_flags), .active_width(measured_active_width),
    .active_height(measured_active_height)
  );

  // Defer BRAM reads until committed geometry has reached the active registers.
  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      bram_start_pending <= 1'b0;
      bram_start_reader <= 1'b0;
    end else begin
      bram_start_reader <= 1'b0;
      if (bram_start)
        bram_start_pending <= 1'b1;
      if (bram_start_pending && !cfg_pending && !cfg_commit && !cfg_busy) begin
        bram_start_reader <= 1'b1;
        bram_start_pending <= 1'b0;
      end
    end
  end

  // BRAM reader faults occupy the upper half of the shared error status word.
  assign cfg_error_flags = {bram_error_flags[15:0], scaler_error_flags[15:0]};
endmodule
