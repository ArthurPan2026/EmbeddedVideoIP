`timescale 1ns/1ps
// 将48 kHz立体声PCM整理为HDMI音频包，并提供ACR与Audio InfoFrame。
module hdmi_pcm_packet_source #(
  parameter bit ENABLE_HDMI_AUDIO = 1'b1,
  parameter integer PIXEL_CLOCK_HZ = 25_178_571,
  parameter integer AUDIO_SAMPLE_RATE_HZ = 48_000,
  parameter integer FIFO_ADDR_WIDTH = 4,
  parameter integer ACR_N = 6144,
  parameter integer H_TOTAL = 800
) (
  input  logic        pixel_clk,
  input  logic        audio_pcm_clk,
  input  logic        pixel_aresetn,
  input  logic        audio_pcm_aresetn,
  input  logic        hdmi_mode_active,
  input  logic        vsync,
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
  output logic        packet_cancel_link,
  output logic [23:0] packet_header,
  output logic [55:0] packet_sub0,
  output logic [55:0] packet_sub1,
  output logic [55:0] packet_sub2,
  output logic [55:0] packet_sub3,
  output logic        audio_underflow_event,
  output logic        audio_overflow_event
);
  generate if (ENABLE_HDMI_AUDIO) begin : g_hdmi_audio_enabled
    localparam logic [2:0] PACKET_NONE = 3'd0;
    localparam logic [2:0] PACKET_SAMPLE = 3'd1;
    localparam logic [2:0] PACKET_ACR = 3'd2;
    localparam logic [2:0] PACKET_INFOFRAME = 3'd3;
    localparam logic [2:0] PACKET_AVI = 3'd5;
    localparam integer SAMPLE_PHASE_WIDTH = (PIXEL_CLOCK_HZ > 1) ? $clog2(PIXEL_CLOCK_HZ) : 1;
    localparam integer SAMPLE_PHASE_SUM_WIDTH = SAMPLE_PHASE_WIDTH + 1;
    localparam integer ACR_PHASE_WIDTH = (PIXEL_CLOCK_HZ > 1) ? $clog2(PIXEL_CLOCK_HZ) : 1;
    localparam integer ACR_PHASE_SUM_WIDTH = ACR_PHASE_WIDTH + 1;
    localparam integer ACR_PACKET_RATE_HZ = (128 * AUDIO_SAMPLE_RATE_HZ) / ACR_N;
    localparam integer ACR_LINE_PHASE_INCREMENT = ACR_PACKET_RATE_HZ * H_TOTAL;

    (* ASYNC_REG = "TRUE" *) logic audio_enable_meta, audio_enable_sync;
    (* ASYNC_REG = "TRUE" *) logic audio_link_meta, audio_link_sync;
    logic audio_enable_prev;
    (* ASYNC_REG = "TRUE" *) logic pixel_enable_meta, pixel_enable_sync;
    logic pixel_enable_prev;
    (* ASYNC_REG = "TRUE" *) logic mute_meta, mute_sync;
    logic pixel_audio_enable, audio_run_enable;
    logic wr_clear, rd_clear;
    logic rd_flush_pending;
    logic [31:0] fifo_rd_data;
    logic fifo_wr_ready, fifo_rd_valid, fifo_rd_ready;
    logic fifo_wr_full, fifo_rd_empty;
    logic [FIFO_ADDR_WIDTH:0] fifo_wr_level, fifo_rd_level;
    logic [SAMPLE_PHASE_WIDTH-1:0] sample_phase;
    logic [SAMPLE_PHASE_SUM_WIDTH-1:0] sample_phase_sum;
    logic sample_due;
    logic [ACR_PHASE_WIDTH-1:0] acr_line_phase;
    logic [ACR_PHASE_SUM_WIDTH-1:0] acr_line_phase_sum;
    logic acr_line_tick;
    logic rd_fire;
    logic audio_started;
    logic [2:0] startup_sample_count;
    logic [4:0] sample_debt;
    logic [2:0] buffered_sample_count;
    logic [31:0] sample_buffer [0:3];
    logic [7:0] next_frame_index;
    logic [7:0] first_buffer_frame_index;
    logic signed [15:0] gained_left, gained_right;
    logic [2:0] selected_packet;
    logic packet_sample_fire;
    logic acr_due;
    logic infoframe_due;
    logic avi_due;
    logic vsync_q;
    logic vsync_rise;
    logic [23:0] sample_header, acr_header, info_header, avi_header;
    logic [55:0] sample_sub [0:3];
    logic [55:0] acr_sub [0:3];
    logic [55:0] info_sub [0:3];
    logic [55:0] avi_sub [0:3];
    integer sample_index;

    // HDMI 请求分别同步到 PCM 与像素时钟域，再与像素域的实际链路状态组合。
    assign pixel_audio_enable = pixel_enable_sync && hdmi_mode_active;
    assign audio_run_enable = audio_enable_sync && audio_link_sync;

    always_ff @(posedge audio_pcm_clk or negedge audio_pcm_aresetn) begin
      if (!audio_pcm_aresetn) begin
        audio_enable_meta <= 1'b0;
        audio_enable_sync <= 1'b0;
        audio_link_meta <= 1'b0;
        audio_link_sync <= 1'b0;
        audio_enable_prev <= 1'b0;
      end else begin
        audio_enable_meta <= hdmi_audio_enable;
        audio_enable_sync <= audio_enable_meta;
        audio_link_meta <= hdmi_mode_active;
        audio_link_sync <= audio_link_meta;
        audio_enable_prev <= audio_run_enable;
      end
    end

    always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
      if (!pixel_aresetn) begin
        pixel_enable_meta <= 1'b0;
        pixel_enable_sync <= 1'b0;
        pixel_enable_prev <= 1'b0;
        mute_meta <= 1'b0;
        mute_sync <= 1'b0;
        rd_flush_pending <= 1'b1;
      end else begin
        pixel_enable_meta <= hdmi_audio_enable;
        pixel_enable_sync <= pixel_enable_meta;
        pixel_enable_prev <= pixel_audio_enable;
        mute_meta <= audio_mute;
        mute_sync <= mute_meta;

        if (pixel_audio_enable != pixel_enable_prev)
          rd_flush_pending <= 1'b1;
        else if (rd_flush_pending && !packet_active)
          rd_flush_pending <= 1'b0;
      end
    end

    assign wr_clear = (audio_run_enable != audio_enable_prev);
    assign rd_clear = rd_flush_pending && !packet_active;
    assign audio_pcm_tready = !audio_run_enable || (fifo_wr_ready && !wr_clear);
    assign audio_overflow_event = 1'b0;
    // A pending packet may be discarded only after the link has safely selected DVI.
    // Audio disable stops future audio packets; a loaded packet completes at its boundary.
    assign packet_cancel = !pixel_audio_enable && !packet_active;
    assign packet_cancel_link = !hdmi_mode_active && !packet_active;

    audio_pcm_async_fifo #(
      .DATA_WIDTH(32), .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) u_audio_fifo (
      .wr_clk(audio_pcm_clk), .wr_resetn(audio_pcm_aresetn), .wr_clear(wr_clear),
      .wr_data(audio_pcm_tdata), .wr_valid(audio_pcm_tvalid && audio_run_enable && !wr_clear),
      .wr_ready(fifo_wr_ready), .wr_full(fifo_wr_full), .wr_level(fifo_wr_level),
      .rd_clk(pixel_clk), .rd_resetn(pixel_aresetn), .rd_clear(rd_clear),
      .rd_data(fifo_rd_data), .rd_valid(fifo_rd_valid),
      .rd_ready(fifo_rd_ready), .rd_empty(fifo_rd_empty), .rd_level(fifo_rd_level)
    );

    // 固定点节拍器按实际像素时钟平均产生48 kHz取样使能。
    always_comb begin
      sample_phase_sum = {1'b0, sample_phase} + SAMPLE_PHASE_SUM_WIDTH'(AUDIO_SAMPLE_RATE_HZ);
      sample_due = sample_phase_sum >= SAMPLE_PHASE_SUM_WIDTH'(PIXEL_CLOCK_HZ);
      acr_line_phase_sum = {1'b0, acr_line_phase} + ACR_PHASE_SUM_WIDTH'(ACR_LINE_PHASE_INCREMENT);
      acr_line_tick = acr_line_phase_sum >= ACR_PHASE_SUM_WIDTH'(PIXEL_CLOCK_HZ);
    end

    assign fifo_rd_ready = pixel_audio_enable && !rd_flush_pending &&
                           (buffered_sample_count < 3'd4);
    assign rd_fire = fifo_rd_valid && fifo_rd_ready;
    assign vsync_rise = vsync && !vsync_q;
    audio_gain_q15 u_gain_left (
      .sample_in($signed(fifo_rd_data[15:0])), .gain_q15(audio_gain_q15),
      .mute(mute_sync), .sample_out(gained_left)
    );
    audio_gain_q15 u_gain_right (
      .sample_in($signed(fifo_rd_data[31:16])), .gain_q15(audio_gain_q15),
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
        if (!pixel_audio_enable || rd_flush_pending) begin
          sample_phase <= '0;
          audio_started <= 1'b0;
          startup_sample_count <= 3'd0;
          sample_debt <= 5'd0;
        end else begin
          if (sample_due)
            sample_phase <= sample_phase_sum - SAMPLE_PHASE_SUM_WIDTH'(PIXEL_CLOCK_HZ);
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
    hdmi_avi_infoframe u_avi_infoframe (.header(avi_header), .subpacket(avi_sub));

    always_comb begin
      selected_packet = PACKET_NONE;
      if (pixel_audio_enable && !rd_flush_pending &&
          (acr_due || acr_line_tick)) begin
        selected_packet = PACKET_ACR;
      end else if (hdmi_mode_active && avi_due) begin
        selected_packet = PACKET_AVI;
      end else if (pixel_audio_enable && !rd_flush_pending) begin
        if (infoframe_due)
          selected_packet = PACKET_INFOFRAME;
        else if (buffered_sample_count != 3'd0)
          selected_packet = PACKET_SAMPLE;
      end
      packet_valid = line_prepare && hdmi_mode_active && packet_ready &&
                     (selected_packet != PACKET_NONE);
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
        PACKET_AVI: begin
          packet_header = avi_header;
          packet_sub0 = avi_sub[0];
          packet_sub1 = avi_sub[1];
          packet_sub2 = avi_sub[2];
          packet_sub3 = avi_sub[3];
        end
        default: begin end
      endcase
    end

    assign packet_sample_fire = packet_valid && (selected_packet == PACKET_SAMPLE);

    // CTS 7-29 checks the long-term ACR update interval. Use a fractional
    // line accumulator rather than a fixed 31-line interval.
    always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
      if (!pixel_aresetn) begin
        acr_due <= 1'b1;
        acr_line_phase <= '0;
        infoframe_due <= 1'b1;
        avi_due <= 1'b1;
        vsync_q <= 1'b0;
      end else if (rd_clear) begin
        acr_due <= 1'b1;
        acr_line_phase <= '0;
        infoframe_due <= 1'b1;
        avi_due <= 1'b1;
        vsync_q <= vsync;
      end else begin
        vsync_q <= vsync;

        if (!hdmi_mode_active) begin
          infoframe_due <= 1'b1;
          avi_due <= 1'b1;
        end

        if (!pixel_audio_enable || rd_flush_pending) begin
          acr_due <= 1'b1;
          acr_line_phase <= '0;
          if (!pixel_audio_enable || rd_flush_pending)
            infoframe_due <= 1'b1;
        end else if (line_prepare) begin
          if (packet_valid && packet_ready && selected_packet == PACKET_ACR) begin
            // Start the next interval at the actual ACR packet line. Preserve
            // fractional overshoot only when this packet lands on the phase tick.
            acr_due <= 1'b0;
            if (acr_line_tick)
              acr_line_phase <= acr_line_phase_sum - ACR_PHASE_SUM_WIDTH'(PIXEL_CLOCK_HZ);
            else
              acr_line_phase <= '0;
          end else if (acr_due) begin
            // A due packet is waiting for a free island slot; hold its phase.
          end else if (acr_line_tick) begin
            acr_line_phase <= acr_line_phase_sum - ACR_PHASE_SUM_WIDTH'(PIXEL_CLOCK_HZ);
            acr_due <= 1'b1;
          end else begin
            acr_line_phase <= acr_line_phase_sum[ACR_PHASE_WIDTH-1:0];
          end
        end

        if (line_prepare) begin
          if (packet_valid && packet_ready && selected_packet == PACKET_INFOFRAME)
            infoframe_due <= 1'b0;
          if (packet_valid && packet_ready && selected_packet == PACKET_AVI)
            avi_due <= 1'b0;
        end

        // Use the actual frame marker instead of a duplicate line counter.
        if (vsync_rise) begin
          infoframe_due <= 1'b1;
          avi_due <= 1'b1;
        end
      end
    end

    initial begin
      if (ACR_N <= 0 || ACR_PACKET_RATE_HZ <= 0)
        $error("ACR_N must produce a positive HDMI 1.4b CTS update rate");
      if (ACR_LINE_PHASE_INCREMENT >= PIXEL_CLOCK_HZ)
        $error("ACR update rate must be below the pixel-line rate");
      if (H_TOTAL <= 0)
        $error("HDMI timing profile totals must be positive");
    end
  end else begin : g_hdmi_audio_disabled
    logic vsync_q;
    logic vsync_rise;
    logic avi_due;
    logic [23:0] avi_header;
    logic [55:0] avi_sub [0:3];
    hdmi_avi_infoframe u_avi_infoframe (.header(avi_header), .subpacket(avi_sub));
    assign vsync_rise = vsync && !vsync_q;
    assign audio_pcm_tready = 1'b1;
    assign packet_valid = hdmi_mode_active && line_prepare && packet_ready && avi_due;
    assign packet_cancel = 1'b0;
    assign packet_cancel_link = !hdmi_mode_active && !packet_active;
    always_comb begin
      // The STATIC_AVI_ONLY assembler consumes this constant payload directly.
      packet_header = avi_header;
      packet_sub0 = avi_sub[0];
      packet_sub1 = avi_sub[1];
      packet_sub2 = avi_sub[2];
      packet_sub3 = avi_sub[3];
    end
    assign audio_underflow_event = 1'b0;
    assign audio_overflow_event = 1'b0;

    always_ff @(posedge pixel_clk or negedge pixel_aresetn) begin
      if (!pixel_aresetn) begin
        vsync_q <= 1'b0;
        avi_due <= 1'b1;
      end else begin
        vsync_q <= vsync;
        if (!hdmi_mode_active) begin
          avi_due <= 1'b1;
        end else if (line_prepare) begin
          if (packet_valid && packet_ready && avi_due)
            avi_due <= 1'b0;
        end
        if (vsync_rise) begin
          avi_due <= 1'b1;
        end
      end
    end
  end endgenerate
endmodule
