`timescale 1ns/1ps
module tb_hdmi_video_encoder;
  logic pixel_clk = 1'b0;
  logic resetn = 1'b1;
  logic [23:0] video_rgb_rbg = 24'd0;
  logic video_de = 1'b0, hsync = 1'b0, vsync = 1'b0;
  logic [9:0] lane0, lane1, lane2;

  logic [23:0] color_601_limited, color_601_full;
  logic [23:0] color_709_limited, color_709_full;
  logic [9:0] expected_lane0 [0:2];
  logic [9:0] expected_lane1 [0:2];
  logic [9:0] expected_lane2 [0:2];
  integer rd_lane0 = 0, rd_lane1 = 0, rd_lane2 = 0;
  integer pixel_cycles = 0;
  integer vector_index;
  integer color_vectors = 0;
  integer encoder_vectors = 0;
  logic [15:0] model_lane0, model_lane1, model_lane2;

  always #5 pixel_clk = ~pixel_clk;

  hdmi_tmds_video_encoder dut (
    .pixel_clk(pixel_clk), .serial_clk(1'b0), .aresetn(resetn),
    .video_rgb_rbg(video_rgb_rbg), .video_de(video_de), .hsync(hsync), .vsync(vsync),
    .lane0_blue_symbol(lane0), .lane1_green_symbol(lane1), .lane2_red_symbol(lane2)
  );

  hdmi_rgb_to_ycbcr444 #(.COLORIMETRY(0), .YCC_RANGE(0)) u_601_limited (
    .rgb_rbg(video_rgb_rbg), .ycbcr_rbg(color_601_limited)
  );
  hdmi_rgb_to_ycbcr444 #(.COLORIMETRY(0), .YCC_RANGE(1)) u_601_full (
    .rgb_rbg(video_rgb_rbg), .ycbcr_rbg(color_601_full)
  );
  hdmi_rgb_to_ycbcr444 #(.COLORIMETRY(1), .YCC_RANGE(0)) u_709_limited (
    .rgb_rbg(video_rgb_rbg), .ycbcr_rbg(color_709_limited)
  );
  hdmi_rgb_to_ycbcr444 #(.COLORIMETRY(1), .YCC_RANGE(1)) u_709_full (
    .rgb_rbg(video_rgb_rbg), .ycbcr_rbg(color_709_full)
  );

  function automatic logic [9:0] ref_control_symbol(input logic [1:0] ctl);
    case (ctl)
      2'b00: ref_control_symbol = 10'b1101010100;
      2'b01: ref_control_symbol = 10'b0010101011;
      2'b10: ref_control_symbol = 10'b0101010100;
      default: ref_control_symbol = 10'b1010101011;
    endcase
  endfunction

  // Independent testbench model for DVI 1.0 Figure 3-5. The upper six bits
  // return the next running disparity; the lower ten bits are the TMDS symbol.
  function automatic logic [15:0] ref_encode(
    input logic [7:0] din,
    input logic       de,
    input logic [1:0] ctl,
    input integer     rd_in
  );
    logic [8:0] q_m;
    logic use_xnor;
    logic [9:0] encoded;
    integer n1_input;
    integer n1_qm;
    integer dc_bias;
    integer rd_next;
    integer i;
    begin
      if (!de) begin
        encoded = ref_control_symbol(ctl);
        rd_next = 0;
      end else begin
        n1_input = 0;
        for (i=0; i<8; i=i+1)
          n1_input = n1_input + din[i];
        use_xnor = (n1_input > 4) || ((n1_input == 4) && !din[0]);
        q_m = '0;
        q_m[0] = din[0];
        for (i=1; i<8; i=i+1)
          q_m[i] = use_xnor ? ~(q_m[i-1] ^ din[i]) : (q_m[i-1] ^ din[i]);
        q_m[8] = !use_xnor;
        n1_qm = 0;
        for (i=0; i<8; i=i+1)
          n1_qm = n1_qm + q_m[i];
        dc_bias = 8 - 2*n1_qm;
        rd_next = rd_in;

        if ((rd_in == 0) || (n1_qm == 4)) begin
          if (!q_m[8]) begin
            encoded = {1'b1, 1'b0, ~q_m[7:0]};
            rd_next = rd_next + dc_bias;
          end else begin
            encoded = {1'b0, 1'b1, q_m[7:0]};
            rd_next = rd_next - dc_bias;
          end
        end else if (((rd_in > 0) && (n1_qm > 4)) || ((rd_in < 0) && (n1_qm < 4))) begin
          encoded = {1'b1, q_m[8], ~q_m[7:0]};
          rd_next = rd_next + (q_m[8] ? 2 : 0) + dc_bias;
        end else begin
          encoded = {1'b0, q_m[8], q_m[7:0]};
          rd_next = rd_next - (q_m[8] ? 0 : 2) - dc_bias;
        end
      end
      ref_encode = {rd_next[5:0], encoded};
    end
  endfunction

  always @(posedge pixel_clk or negedge resetn) begin
    if (!resetn) begin
      expected_lane0[0] <= 10'b1101010100;
      expected_lane0[1] <= 10'b1101010100;
      expected_lane0[2] <= 10'b1101010100;
      expected_lane1[0] <= 10'b1101010100;
      expected_lane1[1] <= 10'b1101010100;
      expected_lane1[2] <= 10'b1101010100;
      expected_lane2[0] <= 10'b1101010100;
      expected_lane2[1] <= 10'b1101010100;
      expected_lane2[2] <= 10'b1101010100;
      rd_lane0 <= 0;
      rd_lane1 <= 0;
      rd_lane2 <= 0;
      pixel_cycles <= 0;
    end else begin
      model_lane0 = ref_encode(video_rgb_rbg[15:8], video_de, {vsync,hsync}, rd_lane0);
      model_lane1 = ref_encode(video_rgb_rbg[7:0], video_de, 2'b00, rd_lane1);
      model_lane2 = ref_encode(video_rgb_rbg[23:16], video_de, 2'b00, rd_lane2);
      rd_lane0 = $signed(model_lane0[15:10]);
      rd_lane1 = $signed(model_lane1[15:10]);
      rd_lane2 = $signed(model_lane2[15:10]);
      expected_lane0[0] <= model_lane0[9:0];
      expected_lane0[1] <= expected_lane0[0];
      expected_lane0[2] <= expected_lane0[1];
      expected_lane1[0] <= model_lane1[9:0];
      expected_lane1[1] <= expected_lane1[0];
      expected_lane1[2] <= expected_lane1[1];
      expected_lane2[0] <= model_lane2[9:0];
      expected_lane2[1] <= expected_lane2[0];
      expected_lane2[2] <= expected_lane2[1];
      pixel_cycles <= pixel_cycles + 1;
      #1;
      if (pixel_cycles >= 3) begin
        if ((lane0 !== expected_lane0[2]) || (lane1 !== expected_lane1[2]) ||
            (lane2 !== expected_lane2[2]))
          $fatal(1, "TMDS encoder mismatch at sample %0d: got %03h/%03h/%03h expected %03h/%03h/%03h",
                 pixel_cycles, lane0, lane1, lane2,
                 expected_lane0[2], expected_lane1[2], expected_lane2[2]);
        encoder_vectors = encoder_vectors + 1;
      end
    end
  end

  task automatic check_color(
    input logic [23:0] rgb,
    input logic [23:0] exp601_limited,
    input logic [23:0] exp601_full,
    input logic [23:0] exp709_limited,
    input logic [23:0] exp709_full
  );
    begin
      video_rgb_rbg = rgb;
      #1;
      if ((color_601_limited !== exp601_limited) || (color_601_full !== exp601_full) ||
          (color_709_limited !== exp709_limited) || (color_709_full !== exp709_full))
        $fatal(1, "YCbCr matrix/range mismatch for RBG %06h: 601 L/F=%06h/%06h, 709 L/F=%06h/%06h",
               rgb, color_601_limited, color_601_full, color_709_limited, color_709_full);
      color_vectors = color_vectors + 1;
    end
  endtask

  initial begin
    // Assert reset asynchronously before starting. The encoder must expose
    // a legal control symbol during reset and return its disparity to zero.
    #1 resetn = 1'b0;
    video_de = 1'b1;
    video_rgb_rbg = 24'hFF0000;
    #1;
    if ({lane2,lane1,lane0} !== {10'b1101010100,10'b1101010100,10'b1101010100})
      $fatal(1, "TMDS outputs must be known control symbols during reset");

    // RGB channel mapping is RBG in this project: R[23:16], B[15:8], G[7:0].
    check_color(24'h000000, 24'h808010, 24'h808000, 24'h808010, 24'h808000);
    check_color(24'hFFFFFF, 24'h8080EB, 24'h8080FF, 24'h8080EB, 24'h8080FF);
    check_color(24'hFF0000, 24'hF05A52, 24'hFF554D, 24'hF0663F, 24'hFF6336);
    check_color(24'h0000FF, 24'h223690, 24'h152B95, 24'h1A2AAC, 24'h0C1DB6);
    check_color(24'h00FF00, 24'h6EF029, 24'h6BFF1D, 24'h76F020, 24'h74FF13);
    check_color(24'h808080, 24'h80807E, 24'h808080, 24'h80807E, 24'h808080);

    repeat (3) @(posedge pixel_clk);
    @(negedge pixel_clk);
    resetn = 1'b1;

    // Exercise all four control tokens, then every byte value on all channels.
    for (vector_index = 0; vector_index < 4; vector_index = vector_index + 1) begin
      @(negedge pixel_clk);
      video_de = 1'b0;
      hsync = vector_index[0];
      vsync = vector_index[1];
      video_rgb_rbg = 24'hA55A3C;
    end
    for (vector_index = 0; vector_index < 256; vector_index = vector_index + 1) begin
      @(negedge pixel_clk);
      video_de = 1'b1;
      hsync = 1'b0;
      vsync = 1'b0;
      video_rgb_rbg = {vector_index[7:0], (8'hFF-vector_index[7:0]), (vector_index[7:0]^8'hA5)};
    end

    // Reassert reset in the middle of active video. No old symbol/disparity
    // state may leak across the reset boundary.
    @(negedge pixel_clk);
    resetn = 1'b0;
    video_de = 1'b1;
    video_rgb_rbg = 24'h00FF00;
    #1;
    if ({lane2,lane1,lane0} !== {10'b1101010100,10'b1101010100,10'b1101010100})
      $fatal(1, "TMDS reset boundary did not clear output symbols");
    repeat (3) @(posedge pixel_clk);
    @(negedge pixel_clk);
    resetn = 1'b1;
    for (vector_index = 0; vector_index < 24; vector_index = vector_index + 1) begin
      @(negedge pixel_clk);
      video_de = 1'b1;
      video_rgb_rbg = (vector_index % 2) ? 24'hFF0000 : 24'h0000FF;
    end

    repeat (4) @(posedge pixel_clk);
    #1;
    if (encoder_vectors < 250)
      $fatal(1, "Insufficient TMDS vector coverage: %0d", encoder_vectors);
    $display("TEST_PASS: hdmi_video_encoder_sv color_vectors=%0d encoder_vectors=%0d",
             color_vectors, encoder_vectors);
    $finish;
  end
endmodule
