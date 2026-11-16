# EmbeddedVideoIP 内部 AXI、PCM 与 HDMI 时钟域互为异步。
set evip_aclk [get_clocks -quiet -include_generated_clocks *aclk*]
set evip_pcm_clk [get_clocks -quiet -include_generated_clocks *audio_pcm_clk*]
set evip_hdmi_clks [get_clocks -quiet -include_generated_clocks *hdmi_ref_clk*]
set_clock_groups -asynchronous \
  -group $evip_aclk \
  -group $evip_pcm_clk \
  -group $evip_hdmi_clks
