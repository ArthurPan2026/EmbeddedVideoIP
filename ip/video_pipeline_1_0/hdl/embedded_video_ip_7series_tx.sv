`timescale 1ns/1ps
// 7系列HDMI发射低层：复用Digilent视频编码与SERDES，并由本模块生成音频包。
module embedded_video_ip_7series_tx #(
  parameter bit ENABLE_HDMI_AUDIO = 1'b1,
  parameter integer PIXEL_CLOCK_HZ = 25_178_571,
  parameter integer AUDIO_SAMPLE_RATE_HZ = 48_000,
  parameter integer H_ACTIVE_SIZE = 640,
  parameter integer HBLANK_PIXELS = 160,
  parameter integer H_TOTAL = H_ACTIVE_SIZE + HBLANK_PIXELS,
  parameter integer H_SYNC_START = 656,
  parameter bit HSYNC_ACTIVE_LEVEL = 1'b1,
  parameter integer ACR_N = 6144
) (
  input  logic        pixel_clk,
  input  logic        serial_clk,
  input  logic        audio_pcm_clk,
  input  logic        aresetn,
  input  logic        hdmi_mode_request,
  input  logic [23:0] video_rgb,
  input  logic        video_de,
  input  logic        hsync,
  input  logic        vsync,
  input  logic [31:0] audio_pcm_tdata,
  input  logic        audio_pcm_tvalid,
  output logic        audio_pcm_tready,
  input  logic        hdmi_audio_enable,
  input  logic        audio_mute,
  input  logic [16:0] audio_gain_q15,
  output logic        tmds_tx_clk_p,
  output logic        tmds_tx_clk_n,
  output logic [2:0]  tmds_tx_data_p,
  output logic [2:0]  tmds_tx_data_n,
  output logic        audio_underflow_event,
  output logic        audio_overflow_event
);
  localparam integer VIDEO_LOOKAHEAD_CYCLES = 10;
  localparam integer VIDEO_PIPE_STAGES = VIDEO_LOOKAHEAD_CYCLES + 1;
  localparam logic [9:0] TMDS_CLOCK_SYMBOL = 10'b1111100000;

  logic pixel_aresetn, audio_pcm_aresetn;
  logic [2:0] tmds_release_pipe;
  logic tmds_serializer_aresetn;
  logic [23:0] rgb_pipe [0:VIDEO_LOOKAHEAD_CYCLES];
  logic de_pipe [0:VIDEO_LOOKAHEAD_CYCLES];
  logic hsync_pipe [0:VIDEO_LOOKAHEAD_CYCLES];
  logic vsync_pipe [0:VIDEO_LOOKAHEAD_CYCLES];
  logic [2:0] symbol_mode;
  logic hdmi_mode_active;
  logic packet_start;
  logic line_prepare, packet_cancel;
  logic packet_valid, packet_ready, packet_loaded, packet_active, packet_done;
  logic packet_cancel_link;
  logic [23:0] packet_header;
  logic [55:0] packet_sub0, packet_sub1, packet_sub2, packet_sub3;
  logic [8:0] packet_data;
  logic [9:0] video_lane0, video_lane1, video_lane2;
  logic [9:0] tmds_lane0, tmds_lane1, tmds_lane2;
  logic underflow_pixel, overflow_audio;
  integer pipe_index;

  embedded_video_ip_reset_sync u_pixel_reset_sync (
    .clk(pixel_clk), .async_aresetn(aresetn), .sync_aresetn(pixel_aresetn)
  );
  embedded_video_ip_reset_sync u_audio_reset_sync (
    .clk(audio_pcm_clk), .async_aresetn(aresetn), .sync_aresetn(audio_pcm_aresetn)
  );

  // Digilent TMDS_Encoder有三级像素流水，延迟释放OSERDES复位以屏蔽流水填充期间的未知值。
  always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
    if (!pixel_aresetn)
      tmds_release_pipe <= 3'b000;
    else
      tmds_release_pipe <= {tmds_release_pipe[1:0],1'b1};
  end
  assign tmds_serializer_aresetn = pixel_aresetn && tmds_release_pipe[2];

  // 延迟视频输入10个像素时钟，为首个有效像素前插入8拍前导和2拍保护带。
  always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
    if (!pixel_aresetn) begin
      for (pipe_index = 0; pipe_index < VIDEO_PIPE_STAGES; pipe_index = pipe_index + 1) begin
        rgb_pipe[pipe_index] <= 24'd0;
        de_pipe[pipe_index] <= 1'b0;
        hsync_pipe[pipe_index] <= 1'b0;
        vsync_pipe[pipe_index] <= 1'b0;
      end
    end else begin
      rgb_pipe[0] <= video_rgb;
      de_pipe[0] <= video_de;
      hsync_pipe[0] <= hsync;
      vsync_pipe[0] <= vsync;
      for (pipe_index = 1; pipe_index < VIDEO_PIPE_STAGES; pipe_index = pipe_index + 1) begin
        rgb_pipe[pipe_index] <= rgb_pipe[pipe_index-1];
        de_pipe[pipe_index] <= de_pipe[pipe_index-1];
        hsync_pipe[pipe_index] <= hsync_pipe[pipe_index-1];
        vsync_pipe[pipe_index] <= vsync_pipe[pipe_index-1];
      end
    end
  end

  hdmi_pcm_packet_source #(
    .ENABLE_HDMI_AUDIO(ENABLE_HDMI_AUDIO),
    .PIXEL_CLOCK_HZ(PIXEL_CLOCK_HZ),
    .AUDIO_SAMPLE_RATE_HZ(AUDIO_SAMPLE_RATE_HZ),
    .H_TOTAL(H_TOTAL), .ACR_N(ACR_N)
  ) u_audio_packet_source (
    .pixel_clk(pixel_clk), .audio_pcm_clk(audio_pcm_clk),
    .pixel_aresetn(pixel_aresetn), .audio_pcm_aresetn(audio_pcm_aresetn),
    .hdmi_mode_active(hdmi_mode_active), .vsync(vsync_pipe[VIDEO_LOOKAHEAD_CYCLES]),
    .line_prepare(line_prepare), .packet_active(packet_active),
    .audio_pcm_tdata(audio_pcm_tdata), .audio_pcm_tvalid(audio_pcm_tvalid),
    .audio_pcm_tready(audio_pcm_tready),
    .hdmi_audio_enable(hdmi_audio_enable && hdmi_mode_active),
    .audio_mute(audio_mute), .audio_gain_q15(audio_gain_q15),
    .packet_ready(packet_ready), .packet_valid(packet_valid), .packet_cancel(packet_cancel),
    .packet_cancel_link(packet_cancel_link), .packet_header(packet_header), .packet_sub0(packet_sub0), .packet_sub1(packet_sub1),
    .packet_sub2(packet_sub2), .packet_sub3(packet_sub3),
    .audio_underflow_event(underflow_pixel), .audio_overflow_event(overflow_audio)
  );

  hdmi_packet_assembler #(.STATIC_AVI_ONLY(!ENABLE_HDMI_AUDIO)) u_packet_assembler (
    .pixel_clk(pixel_clk), .resetn(pixel_aresetn),
    .packet_valid(packet_valid), .packet_ready(packet_ready), .packet_cancel(packet_cancel),
    .packet_cancel_link(packet_cancel_link), .packet_start(packet_start), .packet_loaded(packet_loaded),
    .packet_header(packet_header), .packet_sub0(packet_sub0), .packet_sub1(packet_sub1),
    .packet_sub2(packet_sub2), .packet_sub3(packet_sub3),
    .packet_active(packet_active), .packet_data(packet_data), .packet_done(packet_done)
  );

  hdmi_line_slot_scheduler #(
    .H_TOTAL(H_TOTAL), .H_ACTIVE_SIZE(H_ACTIVE_SIZE), .H_SYNC_START(H_SYNC_START),
    .HSYNC_ACTIVE_LEVEL(HSYNC_ACTIVE_LEVEL),
    .VIDEO_LOOKAHEAD_CYCLES(VIDEO_LOOKAHEAD_CYCLES)
  ) u_line_slot_scheduler (
    .pixel_clk(pixel_clk), .aresetn(pixel_aresetn),
    .hdmi_mode_request(hdmi_mode_request), .hdmi_mode_active(hdmi_mode_active),
    .packet_active(packet_active),
    .video_de_lookahead(video_de), .video_de_delayed(de_pipe[VIDEO_LOOKAHEAD_CYCLES]),
    .hsync_delayed(hsync_pipe[VIDEO_LOOKAHEAD_CYCLES]),
    .packet_loaded(packet_loaded), .packet_offer(packet_valid), .packet_cancel(packet_cancel_link),
    .line_prepare(line_prepare), .symbol_mode(symbol_mode), .packet_start(packet_start)
  );

  // video_rgb按RBG解释，显式把B/G/R送往TMDS通道0/1/2。
  hdmi_tmds_video_encoder u_digilent_video_encoder (
    .pixel_clk(pixel_clk), .serial_clk(serial_clk), .aresetn(pixel_aresetn),
    .video_rgb_rbg(rgb_pipe[VIDEO_LOOKAHEAD_CYCLES]),
    .video_de(de_pipe[VIDEO_LOOKAHEAD_CYCLES]),
    .hsync(hsync_pipe[VIDEO_LOOKAHEAD_CYCLES]),
    .vsync(vsync_pipe[VIDEO_LOOKAHEAD_CYCLES]),
    .lane0_blue_symbol(video_lane0), .lane1_green_symbol(video_lane1),
    .lane2_red_symbol(video_lane2)
  );

  hdmi_tmds_mode_mux #(.ENCODER_LATENCY(3)) u_hdmi_mode_mux (
    .pixel_clk(pixel_clk), .aresetn(pixel_aresetn), .symbol_mode(symbol_mode),
    .hsync(hsync_pipe[VIDEO_LOOKAHEAD_CYCLES]),
    .vsync(vsync_pipe[VIDEO_LOOKAHEAD_CYCLES]), .packet_data(packet_data),
    .video_lane0(video_lane0), .video_lane1(video_lane1), .video_lane2(video_lane2),
    .tmds_lane0(tmds_lane0), .tmds_lane1(tmds_lane1), .tmds_lane2(tmds_lane2)
  );

  // 时钟通道发送固定TMDS时钟图样，三个数据通道使用Digilent OSERDES/OBUFDS。
  OutputSERDES #(.kParallelWidth(10)) u_clock_serdes (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .sDataOut_p(tmds_tx_clk_p),
    .sDataOut_n(tmds_tx_clk_n), .pDataOut(TMDS_CLOCK_SYMBOL), .aRst(~tmds_serializer_aresetn)
  );
  OutputSERDES #(.kParallelWidth(10)) u_data0_serdes (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .sDataOut_p(tmds_tx_data_p[0]),
    .sDataOut_n(tmds_tx_data_n[0]), .pDataOut(tmds_lane0), .aRst(~tmds_serializer_aresetn)
  );
  OutputSERDES #(.kParallelWidth(10)) u_data1_serdes (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .sDataOut_p(tmds_tx_data_p[1]),
    .sDataOut_n(tmds_tx_data_n[1]), .pDataOut(tmds_lane1), .aRst(~tmds_serializer_aresetn)
  );
  OutputSERDES #(.kParallelWidth(10)) u_data2_serdes (
    .PixelClk(pixel_clk), .SerialClk(serial_clk), .sDataOut_p(tmds_tx_data_p[2]),
    .sDataOut_n(tmds_tx_data_n[2]), .pDataOut(tmds_lane2), .aRst(~tmds_serializer_aresetn)
  );

  assign audio_underflow_event = underflow_pixel;
  assign audio_overflow_event = overflow_audio;
endmodule
