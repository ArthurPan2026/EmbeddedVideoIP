`timescale 1ns/1ps
// 将48 kHz立体声PCM整理为HDMI音频包，并提供ACR与Audio InfoFrame。
module hdmi_pcm_packet_source #(
  parameter bit ENABLE_HDMI_AUDIO = 1'b1,
  parameter integer PIXEL_CLOCK_HZ = 25_178_571,
  parameter integer AUDIO_SAMPLE_RATE_HZ = 48_000,
  parameter integer FIFO_ADDR_WIDTH = 4
) (
  input  logic        pixel_clk,
  input  logic        audio_pcm_clk,
  input  logic        pixel_aresetn,
  input  logic        audio_pcm_aresetn,
  input  logic        line_prepare,
  input  logic        packet_active,
  input  logic [31:0] audio_pcm_tdata,
  input  logic        audio_pcm_tvalid,
  output logic        audio_pcm_tready,
  input  logic        hdmi_audio_enable,
  input  logic        audio_mute,
  input  logic [16:0] audio_gain_q15,
  input  logic        packet_ready,
  output logic        packet_valid,
  output logic        packet_cancel,
  output logic [23:0] packet_header,
  output logic [55:0] packet_sub0,
  output logic [55:0] packet_sub1,
  output logic [55:0] packet_sub2,
  output logic [55:0] packet_sub3,
  output logic        audio_underflow_event,
  output logic        audio_overflow_event
);
  generate if (ENABLE_HDMI_AUDIO) begin : g_hdmi_audio_enabled
    localparam logic [1:0] PACKET_NONE = 2'd0;
    localparam logic [1:0] PACKET_SAMPLE = 2'd1;
    localparam logic [1:0] PACKET_ACR = 2'd2;
    localparam logic [1:0] PACKET_INFOFRAME = 2'd3;
    localparam integer SAMPLE_PHASE_WIDTH = 32;

    logic audio_enable_meta, audio_enable_sync, audio_enable_prev;
    logic pixel_enable_meta, pixel_enable_sync, pixel_enable_prev;
    logic mute_meta, mute_sync;
    logic [16:0] gain_meta, gain_sync;
    logic wr_clear, rd_clear;
    logic rd_flush_pending;
    logic [31:0] fifo_rd_data;
    logic fifo_wr_ready, fifo_rd_valid, fifo_rd_ready;
    logic fifo_wr_full, fifo_rd_empty;
    logic [FIFO_ADDR_WIDTH:0] fifo_wr_level, fifo_rd_level;
    logic [31:0] sample_phase;
    logic [32:0] sample_phase_sum;
    logic sample_due;
    logic rd_fire;
    logic audio_started;
    logic [2:0] startup_sample_count;
    logic [4:0] sample_debt;
    logic [2:0] buffered_sample_count;
    logic [31:0] sample_buffer [0:3];
    logic [7:0] next_frame_index;
    logic [7:0] first_buffer_frame_index;
    logic signed [15:0] gained_left, gained_right;
    logic [1:0] selected_packet;
    logic packet_sample_fire;
    logic acr_due;
    logic [5:0] acr_line_counter;
    logic infoframe_due;
    logic [9:0] frame_line_counter;
    logic [23:0] sample_header, acr_header, info_header;
    logic [55:0] sample_sub [0:3];
    logic [55:0] acr_sub [0:3];
    logic [55:0] info_sub [0:3];
    integer sample_index;

    // 使能、静音和增益通过两级触发器同步；音频数据使用异步FIFO跨域。
    always_ff @(posedge audio_pcm_clk or negedge audio_pcm_aresetn) begin
      if (!audio_pcm_aresetn) begin
        audio_enable_meta <= 1'b0;
        audio_enable_sync <= 1'b0;
        audio_enable_prev <= 1'b0;
      end else begin
        audio_enable_meta <= hdmi_audio_enable;
        audio_enable_sync <= audio_enable_meta;
        audio_enable_prev <= audio_enable_sync;
      end
    end

    always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
      if (!pixel_aresetn) begin
        pixel_enable_meta <= 1'b0;
        pixel_enable_sync <= 1'b0;
        pixel_enable_prev <= 1'b0;
        mute_meta <= 1'b0;
        mute_sync <= 1'b0;
        gain_meta <= 17'd32768;
        gain_sync <= 17'd32768;
        rd_flush_pending <= 1'b1;
      end else begin
        pixel_enable_meta <= hdmi_audio_enable;
        pixel_enable_sync <= pixel_enable_meta;
        pixel_enable_prev <= pixel_enable_sync;
        mute_meta <= audio_mute;
        mute_sync <= mute_meta;
        gain_meta <= audio_gain_q15;
        gain_sync <= gain_meta;

        if (pixel_enable_sync != pixel_enable_prev)
          rd_flush_pending <= 1'b1;
        else if (rd_flush_pending && !packet_active)
          rd_flush_pending <= 1'b0;
      end
    end

    assign wr_clear = (audio_enable_sync != audio_enable_prev);
    assign rd_clear = rd_flush_pending && !packet_active;
    assign audio_pcm_tready = !audio_enable_sync || (fifo_wr_ready && !wr_clear);
    assign audio_overflow_event = 1'b0;
    assign packet_cancel = !pixel_enable_sync && !packet_active;

    audio_pcm_async_fifo #(
      .DATA_WIDTH(32), .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_audio_fifo (
      .wr_clk(audio_pcm_clk), .wr_resetn(audio_pcm_aresetn), .wr_clear(wr_clear),
      .wr_data(audio_pcm_tdata), .wr_valid(audio_pcm_tvalid && audio_enable_sync && !wr_clear),
      .wr_ready(fifo_wr_ready), .wr_full(fifo_wr_full), .wr_level(fifo_wr_level),
      .rd_clk(pixel_clk), .rd_resetn(pixel_aresetn), .rd_clear(rd_clear),
      .rd_data(fifo_rd_data), .rd_valid(fifo_rd_valid),
      .rd_ready(fifo_rd_ready), .rd_empty(fifo_rd_empty), .rd_level(fifo_rd_level)
    );

    // 固定点节拍器按实际像素时钟平均产生48 kHz取样使能。
    always_comb begin
      sample_phase_sum = {1'b0, sample_phase} + 33'(AUDIO_SAMPLE_RATE_HZ);
      sample_due = sample_phase_sum >= 33'(PIXEL_CLOCK_HZ);
    end

    assign fifo_rd_ready = pixel_enable_sync && !rd_flush_pending &&
                           (buffered_sample_count < 3'd4);
    assign rd_fire = fifo_rd_valid && fifo_rd_ready;
    audio_gain_q15 u_gain_left (
      .sample_in($signed(fifo_rd_data[15:0])), .gain_q15(gain_sync),
      .mute(mute_sync), .sample_out(gained_left)
    );
    audio_gain_q15 u_gain_right (
      .sample_in($signed(fifo_rd_data[31:16])), .gain_q15(gain_sync),
      .mute(mute_sync), .sample_out(gained_right)
    );

    always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
      if (!pixel_aresetn) begin
        sample_phase <= '0;
        audio_started <= 1'b0;
        startup_sample_count <= 3'd0;
        sample_debt <= 5'd0;
        audio_underflow_event <= 1'b0;
      end else begin
        audio_underflow_event <= 1'b0;
        if (!pixel_enable_sync || rd_flush_pending) begin
          sample_phase <= '0;
          audio_started <= 1'b0;
          startup_sample_count <= 3'd0;
          sample_debt <= 5'd0;
        end else begin
          if (sample_due)
            sample_phase <= sample_phase_sum - 33'(PIXEL_CLOCK_HZ);
          else
            sample_phase <= sample_phase_sum[SAMPLE_PHASE_WIDTH-1:0];

          if (rd_fire) begin
            if (startup_sample_count < 3'd4)
              startup_sample_count <= startup_sample_count + 1'b1;
            if (startup_sample_count >= 3'd3)
              audio_started <= 1'b1;
            sample_debt <= 5'd0;
          end else if (sample_due && buffered_sample_count == 3'd0 &&
                       !fifo_rd_valid && audio_started && !mute_sync) begin
            if (sample_debt < 5'd2)
              sample_debt <= sample_debt + 1'b1;
            if (sample_debt >= 5'd2)
              audio_underflow_event <= 1'b1;
          end else if (sample_due && (buffered_sample_count != 3'd0 || fifo_rd_valid)) begin
            sample_debt <= 5'd0;
          end
        end
      end
    end

    always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
      if (!pixel_aresetn) begin
        buffered_sample_count <= 3'd0;
        next_frame_index <= 8'd0;
        first_buffer_frame_index <= 8'd0;
        for (sample_index = 0; sample_index < 4; sample_index = sample_index + 1)
          sample_buffer[sample_index] <= '0;
      end else begin
        if (rd_clear) begin
          buffered_sample_count <= 3'd0;
        end else begin
          case ({rd_fire, packet_sample_fire})
            2'b00: begin end
            2'b01: buffered_sample_count <= 3'd0;
            2'b10: begin
              if (buffered_sample_count == 3'd0)
                first_buffer_frame_index <= next_frame_index;
              if (buffered_sample_count < 3'd4) begin
                sample_buffer[buffered_sample_count] <= {gained_right, gained_left};
                buffered_sample_count <= buffered_sample_count + 1'b1;
              end
            end
            2'b11: begin
              // 包装入旧四帧时，恰好同时到达的新帧成为下一包的首帧。
              sample_buffer[0] <= {gained_right, gained_left};
              buffered_sample_count <= 3'd1;
              first_buffer_frame_index <= next_frame_index;
            end
          endcase
        end

        if (rd_fire) begin
          if (next_frame_index == 8'd191)
            next_frame_index <= 8'd0;
          else
            next_frame_index <= next_frame_index + 1'b1;
        end
      end
    end

    hdmi_audio_sample_packet u_sample_packet (
      .stereo_sample(sample_buffer), .sample_count(buffered_sample_count), .sample_flat(4'b0000),
      .first_frame_index(first_buffer_frame_index), .header(sample_header),
      .subpacket(sample_sub)
    );
    hdmi_acr_packet #(
      .PIXEL_CLOCK_HZ(PIXEL_CLOCK_HZ),
      .AUDIO_SAMPLE_RATE_HZ(AUDIO_SAMPLE_RATE_HZ)
    ) u_acr_packet (.header(acr_header), .subpacket(acr_sub));
    hdmi_audio_infoframe u_audio_infoframe (.header(info_header), .subpacket(info_sub));

    always_comb begin
      selected_packet = PACKET_NONE;
      if (acr_due)
        selected_packet = PACKET_ACR;
      else if (infoframe_due)
        selected_packet = PACKET_INFOFRAME;
      else if (buffered_sample_count != 3'd0)
        selected_packet = PACKET_SAMPLE;

      packet_valid = line_prepare && pixel_enable_sync && !rd_flush_pending &&
                     packet_ready && (selected_packet != PACKET_NONE);
      packet_header = 24'd0;
      packet_sub0 = 56'd0;
      packet_sub1 = 56'd0;
      packet_sub2 = 56'd0;
      packet_sub3 = 56'd0;
      case (selected_packet)
        PACKET_SAMPLE: begin
          packet_header = sample_header;
          packet_sub0 = sample_sub[0];
          packet_sub1 = sample_sub[1];
          packet_sub2 = sample_sub[2];
          packet_sub3 = sample_sub[3];
        end
        PACKET_ACR: begin
          packet_header = acr_header;
          packet_sub0 = acr_sub[0];
          packet_sub1 = acr_sub[1];
          packet_sub2 = acr_sub[2];
          packet_sub3 = acr_sub[3];
        end
        PACKET_INFOFRAME: begin
          packet_header = info_header;
          packet_sub0 = info_sub[0];
          packet_sub1 = info_sub[1];
          packet_sub2 = info_sub[2];
          packet_sub3 = info_sub[3];
        end
        default: begin end
      endcase
    end

    assign packet_sample_fire = packet_valid && (selected_packet == PACKET_SAMPLE);

    // ACR约每31条扫描行发送一次；Audio InfoFrame每525条扫描行至少发送一次。
    always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
      if (!pixel_aresetn) begin
        acr_due <= 1'b1;
        acr_line_counter <= 6'd0;
        infoframe_due <= 1'b1;
        frame_line_counter <= 10'd0;
      end else if (rd_clear) begin
        acr_due <= 1'b1;
        acr_line_counter <= 6'd0;
        infoframe_due <= 1'b1;
        frame_line_counter <= 10'd0;
      end else if (line_prepare) begin
        if (acr_line_counter == 6'd30) begin
          acr_line_counter <= 6'd0;
          acr_due <= 1'b1;
        end else begin
          acr_line_counter <= acr_line_counter + 1'b1;
        end

        if (frame_line_counter == 10'd524) begin
          frame_line_counter <= 10'd0;
          infoframe_due <= 1'b1;
        end else begin
          frame_line_counter <= frame_line_counter + 1'b1;
        end

        if (packet_valid && selected_packet == PACKET_ACR)
          acr_due <= 1'b0;
        if (packet_valid && selected_packet == PACKET_INFOFRAME)
          infoframe_due <= 1'b0;
      end
    end
  end else begin : g_hdmi_audio_disabled
    assign audio_pcm_tready = 1'b1;
    assign packet_valid = 1'b0;
    assign packet_cancel = 1'b0;
    assign packet_header = 24'd0;
    assign packet_sub0 = 56'd0;
    assign packet_sub1 = 56'd0;
    assign packet_sub2 = 56'd0;
    assign packet_sub3 = 56'd0;
    assign audio_underflow_event = 1'b0;
    assign audio_overflow_event = 1'b0;
  end endgenerate
endmodule
