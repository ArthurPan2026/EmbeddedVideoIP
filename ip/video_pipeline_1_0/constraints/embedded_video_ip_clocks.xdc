# EmbeddedVideoIP 内部 AXI、PCM 与 HDMI 时钟域的跨域路径约束。
# 通过接口端口查询时钟，兼容消费工程对时钟对象的实际命名。
set_clock_groups -asynchronous \
  -group [get_clocks -quiet -of_objects [get_ports -quiet aclk]] \
  -group [get_clocks -quiet -of_objects [get_ports -quiet audio_pcm_clk]] \
  -group [get_clocks -quiet -include_generated_clocks -of_objects [get_ports -quiet hdmi_ref_clk]]
