`timescale 1ns/1ps
module axi_lite_video_regs #(
  parameter int unsigned ADDR_WIDTH = 6
) (
  input logic aclk, input logic aresetn,
  input logic [ADDR_WIDTH-1:0] s_axi_awaddr,
  input logic s_axi_awvalid, output logic s_axi_awready,
  input logic [31:0] s_axi_wdata, input logic [3:0] s_axi_wstrb,
  input logic s_axi_wvalid, output logic s_axi_wready,
  output logic [1:0] s_axi_bresp, output logic s_axi_bvalid,
  input logic s_axi_bready,
  input logic [ADDR_WIDTH-1:0] s_axi_araddr,
  input logic s_axi_arvalid, output logic s_axi_arready,
  output logic [31:0] s_axi_rdata, output logic [1:0] s_axi_rresp,
  output logic s_axi_rvalid, input logic s_axi_rready,
  output logic cfg_enable,
  output logic [1:0] cfg_source,
  output logic cfg_scale_enable,
  output logic cfg_stretch,
  output logic [1:0] cfg_format,
  output logic [15:0] cfg_width,
  output logic [15:0] cfg_height,
  output logic [31:0] cfg_stride_bytes,
  output logic [31:0] cfg_bram_base_word,
  output logic [9:0] cfg_active_width,
  output logic [9:0] cfg_active_height,
  output logic [9:0] cfg_x_offset,
  output logic [9:0] cfg_y_offset,
  output logic [9:0] cfg_source_x_origin,
  output logic [9:0] cfg_source_y_origin,
  output logic [9:0] cfg_x_step,
  output logic [9:0] cfg_x_rem,
  output logic [9:0] cfg_y_step,
  output logic [9:0] cfg_y_rem,
  output logic cfg_commit,
  output logic bram_start,
  output logic clear_errors,
  input logic busy, input logic bram_busy,
  input logic [1:0] active_source,
  input logic [9:0] active_width, input logic [9:0] active_height,
  input logic [31:0] frame_count,
  input logic [31:0] error_flags
);
  localparam logic [ADDR_WIDTH-1:0] REG_CTRL = 'h00;
  localparam logic [ADDR_WIDTH-1:0] REG_SIZE = 'h04;
  localparam logic [ADDR_WIDTH-1:0] REG_STRIDE = 'h08;
  localparam logic [ADDR_WIDTH-1:0] REG_BRAM_BASE = 'h0c;
  localparam logic [ADDR_WIDTH-1:0] REG_STATUS = 'h10;
  localparam logic [ADDR_WIDTH-1:0] REG_FRAME_COUNT = 'h14;
  localparam logic [ADDR_WIDTH-1:0] REG_ERRORS = 'h18;
  localparam logic [ADDR_WIDTH-1:0] REG_ACTIVE_CFG = 'h1c;
  localparam logic [ADDR_WIDTH-1:0] REG_OFFSETS = 'h20;
  localparam logic [ADDR_WIDTH-1:0] REG_ORIGIN = 'h24;
  localparam logic [ADDR_WIDTH-1:0] REG_X_RATIO = 'h28;
  localparam logic [ADDR_WIDTH-1:0] REG_Y_RATIO = 'h2c;
  localparam logic [ADDR_WIDTH-1:0] REG_ACTIVE_SIZE = 'h30;

  logic [31:0] ctrl_reg, size_reg, stride_reg, bram_base_reg;
  logic [31:0] active_cfg_reg, offsets_reg, origin_reg, x_ratio_reg, y_ratio_reg;
  logic aw_saved, w_saved;
  logic [ADDR_WIDTH-1:0] awaddr_saved;
  logic [31:0] wdata_saved;
  logic [3:0] wstrb_saved;
  logic aw_fire, w_fire, write_fire;
  logic [ADDR_WIDTH-1:0] write_addr;
  logic [31:0] write_data;
  logic [3:0] write_strb;
  logic [31:0] read_value;

  function automatic logic [31:0] merge_strb(
    input logic [31:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0] strobe
  );
    logic [31:0] result;
    integer k;
    begin
      result = old_value;
      for (k=0;k<4;k=k+1)
        if (strobe[k]) result[k*8 +: 8] = new_value[k*8 +: 8];
      merge_strb = result;
    end
  endfunction

  always_comb begin
    s_axi_awready = !aw_saved && !s_axi_bvalid;
    s_axi_wready = !w_saved && !s_axi_bvalid;
    aw_fire = s_axi_awvalid && s_axi_awready;
    w_fire = s_axi_wvalid && s_axi_wready;
    write_fire = (aw_saved || aw_fire) && (w_saved || w_fire) && !s_axi_bvalid;
    write_addr = aw_saved ? awaddr_saved : s_axi_awaddr;
    write_data = w_saved ? wdata_saved : s_axi_wdata;
    write_strb = w_saved ? wstrb_saved : s_axi_wstrb;

    s_axi_bresp = 2'b00;
    s_axi_arready = !s_axi_rvalid;
    s_axi_rresp = 2'b00;

    cfg_enable = ctrl_reg[0];
    cfg_source = ctrl_reg[2:1];
    cfg_scale_enable = ctrl_reg[3];
    cfg_stretch = ctrl_reg[4];
    cfg_format = ctrl_reg[6:5];
    cfg_width = size_reg[15:0];
    cfg_height = size_reg[31:16];
    cfg_stride_bytes = stride_reg;
    cfg_bram_base_word = bram_base_reg;
    cfg_active_width = active_cfg_reg[9:0];
    cfg_active_height = active_cfg_reg[25:16];
    cfg_x_offset = offsets_reg[9:0];
    cfg_y_offset = offsets_reg[25:16];
    cfg_source_x_origin = origin_reg[9:0];
    cfg_source_y_origin = origin_reg[25:16];
    cfg_x_step = x_ratio_reg[9:0];
    cfg_x_rem = x_ratio_reg[25:16];
    cfg_y_step = y_ratio_reg[9:0];
    cfg_y_rem = y_ratio_reg[25:16];

    case (s_axi_araddr)
      REG_CTRL: read_value = ctrl_reg;
      REG_SIZE: read_value = size_reg;
      REG_STRIDE: read_value = stride_reg;
      REG_BRAM_BASE: read_value = bram_base_reg;
      REG_STATUS: read_value = {24'd0, active_source, bram_busy, busy, 4'd0};
      REG_FRAME_COUNT: read_value = frame_count;
      REG_ERRORS: read_value = error_flags;
      REG_ACTIVE_CFG: read_value = active_cfg_reg;
      REG_OFFSETS: read_value = offsets_reg;
      REG_ORIGIN: read_value = origin_reg;
      REG_X_RATIO: read_value = x_ratio_reg;
      REG_Y_RATIO: read_value = y_ratio_reg;
      REG_ACTIVE_SIZE: read_value = {6'd0, active_height, 6'd0, active_width};
      default: read_value = 32'd0;
    endcase
  end

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      ctrl_reg <= 32'd0;
      size_reg <= {16'd240,16'd320};
      stride_reg <= 32'd640;
      bram_base_reg <= 32'd0;
      active_cfg_reg <= {6'd0,10'd240,6'd0,10'd320};
      offsets_reg <= {6'd0,10'd120,6'd0,10'd160};
      origin_reg <= 32'd0;
      x_ratio_reg <= 32'd1;
      y_ratio_reg <= 32'd1;
      aw_saved <= 1'b0; w_saved <= 1'b0;
      awaddr_saved <= '0; wdata_saved <= '0; wstrb_saved <= '0;
      s_axi_bvalid <= 1'b0; s_axi_rvalid <= 1'b0; s_axi_rdata <= 32'd0;
      cfg_commit <= 1'b0; bram_start <= 1'b0; clear_errors <= 1'b0;
    end else begin
      cfg_commit <= 1'b0;
      bram_start <= 1'b0;
      clear_errors <= 1'b0;

      if (aw_fire) begin awaddr_saved <= s_axi_awaddr; aw_saved <= 1'b1; end
      if (w_fire) begin
        wdata_saved <= s_axi_wdata; wstrb_saved <= s_axi_wstrb; w_saved <= 1'b1;
      end
      if (write_fire) begin
        aw_saved <= 1'b0;
        w_saved <= 1'b0;
        s_axi_bvalid <= 1'b1;
        case (write_addr)
          REG_CTRL: begin
            logic [31:0] merged;
            merged = merge_strb(ctrl_reg, write_data, write_strb);
            ctrl_reg <= {merged[31:11], 3'b000, merged[7:0]};
            if (write_strb[1] && write_data[8]) cfg_commit <= 1'b1;
            if (write_strb[1] && write_data[9]) bram_start <= 1'b1;
            if (write_strb[1] && write_data[10]) clear_errors <= 1'b1;
          end
          REG_SIZE: size_reg <= merge_strb(size_reg, write_data, write_strb);
          REG_STRIDE: stride_reg <= merge_strb(stride_reg, write_data, write_strb);
          REG_BRAM_BASE: bram_base_reg <= merge_strb(bram_base_reg, write_data, write_strb);
          REG_ACTIVE_CFG: active_cfg_reg <= merge_strb(active_cfg_reg, write_data, write_strb);
          REG_OFFSETS: offsets_reg <= merge_strb(offsets_reg, write_data, write_strb);
          REG_ORIGIN: origin_reg <= merge_strb(origin_reg, write_data, write_strb);
          REG_X_RATIO: x_ratio_reg <= merge_strb(x_ratio_reg, write_data, write_strb);
          REG_Y_RATIO: y_ratio_reg <= merge_strb(y_ratio_reg, write_data, write_strb);
          default: begin end
        endcase
      end
      if (s_axi_bvalid && s_axi_bready)
        s_axi_bvalid <= 1'b0;

      if (s_axi_arvalid && s_axi_arready) begin
        s_axi_rdata <= read_value;
        s_axi_rvalid <= 1'b1;
      end
      if (s_axi_rvalid && s_axi_rready)
        s_axi_rvalid <= 1'b0;
    end
  end
endmodule
