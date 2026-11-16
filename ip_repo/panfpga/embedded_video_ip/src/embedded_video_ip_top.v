`timescale 1ns/1ps
// EmbeddedVideoIP 单一 PL+PS composite 顶层。
module embedded_video_ip_top #(
  parameter integer MAX_INPUT_WIDTH = 640,
  parameter integer MAX_INPUT_HEIGHT = 480,
  parameter integer BRAM_ADDR_WIDTH = 18,
  parameter integer AXI_ADDR_WIDTH = 6,
  parameter integer ENABLE_BRAM_SOURCE = 1,
  parameter integer ENABLE_HLS_SOURCE = 1,
  parameter integer ENABLE_VDMA_SOURCE = 1,
  parameter integer SOURCE_SELECT_MODE = 0,
  parameter integer FIXED_SOURCE = 2,
  parameter integer FORMAT_SELECT_MODE = 0,
  parameter integer FIXED_FORMAT = 2,
  parameter integer MAX_SCALER_INPUT_WIDTH = MAX_INPUT_WIDTH,
  parameter integer MAX_SCALER_INPUT_HEIGHT = MAX_INPUT_HEIGHT,
  parameter integer ENABLE_SCALER = 1,
  parameter integer LINE_BUFFER_IMPLEMENTATION = 0,
  parameter integer ENABLE_HDMI_AUDIO = 0
) (
  input wire aclk,
  input wire aresetn,
  input wire hdmi_ref_clk,

  input wire [31:0] s_axis_hls_tdata,
  input wire s_axis_hls_tvalid,
  output wire s_axis_hls_tready,
  input wire s_axis_hls_tuser,
  input wire s_axis_hls_tlast,

  input wire [31:0] s_axis_vdma_tdata,
  input wire s_axis_vdma_tvalid,
  output wire s_axis_vdma_tready,
  input wire s_axis_vdma_tuser,
  input wire s_axis_vdma_tlast,

  output wire bram_en,
  output wire [BRAM_ADDR_WIDTH-1:0] bram_addr,
  input wire [31:0] bram_dout,
  output wire bram_busy,
  output wire bram_frame_done,

  input wire audio_pcm_clk,
  input wire [31:0] s_axis_audio_pcm_tdata,
  input wire s_axis_audio_pcm_tvalid,
  output wire s_axis_audio_pcm_tready,

  input wire [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
  input wire s_axi_awvalid,
  output wire s_axi_awready,
  input wire [31:0] s_axi_wdata,
  input wire [3:0] s_axi_wstrb,
  input wire s_axi_wvalid,
  output wire s_axi_wready,
  output wire [1:0] s_axi_bresp,
  output wire s_axi_bvalid,
  input wire s_axi_bready,
  input wire [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
  input wire s_axi_arvalid,
  output wire s_axi_arready,
  output wire [31:0] s_axi_rdata,
  output wire [1:0] s_axi_rresp,
  output wire s_axi_rvalid,
  input wire s_axi_rready,

  output wire tmds_tx_clk_p,
  output wire tmds_tx_clk_n,
  output wire [2:0] tmds_tx_data_p,
  output wire [2:0] tmds_tx_data_n
);
  localparam integer EVIP_AUDIO_SAMPLE_RATE_HZ = 48000;
  localparam integer EVIP_PIXEL_CLOCK_HZ = 25178571;
  localparam integer EVIP_H_ACTIVE_SIZE = 640;
  localparam integer EVIP_HBLANK_PIXELS = 160;
  localparam integer EVIP_H_SYNC_START = 656;
  localparam integer EVIP_HSYNC_ACTIVE_LEVEL = 1;

  wire [23:0] m_axis_video_tdata;
  wire m_axis_video_tvalid;
  wire m_axis_video_tready;
  wire m_axis_video_tuser;
  wire m_axis_video_tlast;
  wire hdmi_audio_enable;
  wire audio_mute;
  wire [16:0] audio_gain_q15;
  wire audio_underflow_event_pixel;
  wire audio_overflow_event_audio;
  wire audio_pcm_resetn_sync;
  wire audio_underflow_aclk;
  wire audio_overflow_aclk;
  wire tx_audio_pcm_tready;
  wire [23:0] video_rgb;
  wire video_de;
  wire video_hsync;
  wire video_vsync;
  wire pixel_clk;
  wire serial_clk;
  wire pixel_aresetn;
  wire hdmi_mmcm_locked;
  wire pixel_reset_ext_asserted;
  wire [5:0] hdmi_diag_status;

  hdmi_runtime_status u_hdmi_runtime_status (
    .aclk(aclk), .aresetn(aresetn),
    .pixel_clk(pixel_clk), .mmcm_locked_async(hdmi_mmcm_locked),
    .pixel_resetn_async(pixel_aresetn),
    .pixel_reset_ext_asserted_async(pixel_reset_ext_asserted),
    .serial_clk(serial_clk),
    .video_vsync_async(video_vsync), .status(hdmi_diag_status)
  );

  video_pipeline_v1_0 #(
    .MAX_INPUT_WIDTH(MAX_INPUT_WIDTH),
    .MAX_INPUT_HEIGHT(MAX_INPUT_HEIGHT),
    .BRAM_ADDR_WIDTH(BRAM_ADDR_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .ENABLE_BRAM_SOURCE(ENABLE_BRAM_SOURCE),
    .ENABLE_HLS_SOURCE(ENABLE_HLS_SOURCE),
    .ENABLE_VDMA_SOURCE(ENABLE_VDMA_SOURCE),
    .SOURCE_SELECT_MODE(SOURCE_SELECT_MODE),
    .FIXED_SOURCE(FIXED_SOURCE),
    .FORMAT_SELECT_MODE(FORMAT_SELECT_MODE),
    .FIXED_FORMAT(FIXED_FORMAT),
    .MAX_SCALER_INPUT_WIDTH(MAX_SCALER_INPUT_WIDTH),
    .MAX_SCALER_INPUT_HEIGHT(MAX_SCALER_INPUT_HEIGHT),
    .ENABLE_SCALER(ENABLE_SCALER),
    .LINE_BUFFER_IMPLEMENTATION(LINE_BUFFER_IMPLEMENTATION),
    .ENABLE_HDMI_AUDIO(ENABLE_HDMI_AUDIO)
  ) video_core (
    .aclk(aclk), .aresetn(aresetn),
    .bram_en(bram_en), .bram_addr(bram_addr), .bram_dout(bram_dout),
    .bram_busy(bram_busy), .bram_frame_done(bram_frame_done),
    .s_axis_hls_tdata(s_axis_hls_tdata), .s_axis_hls_tvalid(s_axis_hls_tvalid),
    .s_axis_hls_tready(s_axis_hls_tready), .s_axis_hls_tuser(s_axis_hls_tuser),
    .s_axis_hls_tlast(s_axis_hls_tlast),
    .s_axis_vdma_tdata(s_axis_vdma_tdata), .s_axis_vdma_tvalid(s_axis_vdma_tvalid),
    .s_axis_vdma_tready(s_axis_vdma_tready), .s_axis_vdma_tuser(s_axis_vdma_tuser),
    .s_axis_vdma_tlast(s_axis_vdma_tlast),
    .m_axis_video_tdata(m_axis_video_tdata), .m_axis_video_tvalid(m_axis_video_tvalid),
    .m_axis_video_tready(m_axis_video_tready), .m_axis_video_tuser(m_axis_video_tuser),
    .m_axis_video_tlast(m_axis_video_tlast),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .hdmi_audio_enable(hdmi_audio_enable), .audio_mute(audio_mute),
    .audio_gain_q15(audio_gain_q15), .audio_underflow(audio_underflow_aclk),
    .audio_overflow(audio_overflow_aclk), .hdmi_diag_status(hdmi_diag_status)
  );

  embedded_video_ip_video_out_wrapper video_output (
    .aclk(aclk), .aresetn(aresetn), .hdmi_ref_clk(hdmi_ref_clk),
    .s_axis_video_tdata(m_axis_video_tdata), .s_axis_video_tvalid(m_axis_video_tvalid),
    .s_axis_video_tready(m_axis_video_tready), .s_axis_video_tuser(m_axis_video_tuser),
    .s_axis_video_tlast(m_axis_video_tlast),
    .video_rgb(video_rgb), .video_de(video_de), .video_hsync(video_hsync),
    .video_vsync(video_vsync), .pixel_clk(pixel_clk), .serial_clk(serial_clk),
    .pixel_aresetn(pixel_aresetn), .hdmi_mmcm_locked(hdmi_mmcm_locked),
    .pixel_reset_ext_asserted(pixel_reset_ext_asserted)
  );

  embedded_video_ip_7series_tx #(
    .ENABLE_HDMI_AUDIO(ENABLE_HDMI_AUDIO),
    .AUDIO_SAMPLE_RATE_HZ(EVIP_AUDIO_SAMPLE_RATE_HZ),
    .PIXEL_CLOCK_HZ(EVIP_PIXEL_CLOCK_HZ),
    .H_ACTIVE_SIZE(EVIP_H_ACTIVE_SIZE),
    .HBLANK_PIXELS(EVIP_HBLANK_PIXELS),
    .H_TOTAL(EVIP_H_ACTIVE_SIZE + EVIP_HBLANK_PIXELS),
    .H_SYNC_START(EVIP_H_SYNC_START),
    .HSYNC_ACTIVE_LEVEL(EVIP_HSYNC_ACTIVE_LEVEL)
  ) hdmi_tx (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .aresetn(pixel_aresetn),
    .video_rgb(video_rgb), .video_de(video_de), .hsync(video_hsync),
    .vsync(video_vsync),
    .audio_pcm_clk(audio_pcm_clk), .audio_pcm_tdata(s_axis_audio_pcm_tdata),
    .audio_pcm_tvalid(s_axis_audio_pcm_tvalid), .audio_pcm_tready(tx_audio_pcm_tready),
    .hdmi_audio_enable(hdmi_audio_enable), .audio_mute(audio_mute),
    .audio_gain_q15(audio_gain_q15),
    .tmds_tx_clk_p(tmds_tx_clk_p), .tmds_tx_clk_n(tmds_tx_clk_n),
    .tmds_tx_data_p(tmds_tx_data_p), .tmds_tx_data_n(tmds_tx_data_n),
    .audio_underflow_event(audio_underflow_event_pixel),
    .audio_overflow_event(audio_overflow_event_audio)
  );

  generate
    if (ENABLE_HDMI_AUDIO != 0) begin : gen_hdmi_audio_events
      assign s_axis_audio_pcm_tready = tx_audio_pcm_tready;
      embedded_video_ip_reset_sync audio_event_reset_sync (
        .clk(audio_pcm_clk), .async_aresetn(aresetn),
        .sync_aresetn(audio_pcm_resetn_sync)
      );
      audio_event_pulse_sync underflow_event_sync (
        .src_clk(pixel_clk), .src_resetn(pixel_aresetn),
        .src_pulse(audio_underflow_event_pixel), .dst_clk(aclk),
        .dst_resetn(aresetn), .dst_pulse(audio_underflow_aclk)
      );
      audio_event_pulse_sync overflow_event_sync (
        .src_clk(audio_pcm_clk), .src_resetn(audio_pcm_resetn_sync),
        .src_pulse(audio_overflow_event_audio), .dst_clk(aclk),
        .dst_resetn(aresetn), .dst_pulse(audio_overflow_aclk)
      );
    end else begin : gen_hdmi_audio_disabled
      // Audio关断时始终接收并丢弃样本，避免阻塞消费工程的PCM源。
      assign s_axis_audio_pcm_tready = 1'b1;
      assign audio_underflow_aclk = 1'b0;
      assign audio_overflow_aclk = 1'b0;
    end
  endgenerate


endmodule
