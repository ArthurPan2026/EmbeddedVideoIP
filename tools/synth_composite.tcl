if {$argc < 5} {
  error "用法：synth_composite.tcl 仓库根目录 IP仓库目录 器件 输出目录 profile ?名称=数值 ...?"
}
set repo_root [file normalize [lindex $argv 0]]
set ip_repo [file normalize [lindex $argv 1]]
set part_name [lindex $argv 2]
set out_dir [file normalize [lindex $argv 3]]
set profile [lindex $argv 4]
set generic_values [lrange $argv 5 end]
if {$profile ni {composite_audio_off composite_audio_on}} {
  error "未知的 Composite 综合 profile： $profile"
}
file mkdir $out_dir
set project_dir [file join $out_dir project]
create_project -force embedded_video_ip_synth $project_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog
set_msg_config -id {BD 41-1356} -new_severity INFO
create_bd_design embedded_video_ip_synth
create_bd_cell -type ip -vlnv panfpga.org:video:embedded_video_ip:1.0 embedded_video_ip_0
set cell [get_bd_cells embedded_video_ip_0]
set config {}
foreach generic $generic_values {
  if {![regexp {^([A-Z][A-Z0-9_]*)=([0-9]+)$} $generic -> name value]} {
    error "综合参数格式无效： $generic"
  }
  lappend config CONFIG.$name $value
}
if {[llength $config] > 0} {
  set_property -dict $config $cell
}
set expected_audio [expr {$profile eq "composite_audio_on" ? "1" : "0"}]
if {[get_property CONFIG.ENABLE_HDMI_AUDIO $cell] ne $expected_audio} {
  error "音频静态参数与综合 profile 不一致"
}
foreach name {s_axi s_axis_vdma s_axis_hls s_axis_audio_pcm} {
  set intf [get_bd_intf_pins -quiet $cell/$name]
  if {[llength $intf] != 1} { error "缺少必需的 AXI 接口： $name" }
  make_bd_intf_pins_external -name $name $intf
}
foreach name {aclk aresetn hdmi_ref_clk audio_pcm_clk bram_en bram_addr bram_dout bram_busy bram_frame_done tmds_tx_clk_p tmds_tx_clk_n tmds_tx_data_p tmds_tx_data_n} {
  set pin [get_bd_pins -quiet $cell/$name]
  if {[llength $pin] != 1} { error "缺少必需的顶层端口： $name" }
  make_bd_pins_external -name $name $pin
}
validate_bd_design
save_bd_design
set bd_file [get_files -quiet embedded_video_ip_synth.bd]
if {[llength $bd_file] != 1} { error "综合 BD 未保存" }
generate_target all $bd_file
set wrapper_file [make_wrapper -files $bd_file -top]
if {![file isfile $wrapper_file]} { error "未生成 Composite 综合 wrapper" }
add_files -norecurse $wrapper_file
set_property top embedded_video_ip_synth_wrapper [current_fileset]
update_compile_order -fileset sources_1
# The packaged clock bus interfaces carry FREQ_HZ metadata; use those clocks
# instead of overriding scoped IP clocks with a duplicate OOC create_clock.
set synth_run [get_runs -quiet synth_1]
if {[llength $synth_run] == 0} {
  create_run synth_1 -flow {Vivado Synthesis 2025} -constrset constrs_1
  set synth_run [get_runs synth_1]
}
set_property strategy Flow_PerfOptimized_high $synth_run
puts "EMBEDDED_VIDEO_IP_SYNTH_PROFILE: $profile"
puts "EMBEDDED_VIDEO_IP_SYNTH_PARAMETERS: $generic_values"
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS $synth_run]
puts "EMBEDDED_VIDEO_IP_SYNTH_STATUS: $synth_status"
if {![string match "*Complete*" $synth_status]} {
  error "Vivado synth_1 未成功： $synth_status"
}
set ooc_run [get_runs -quiet embedded_video_ip_synth_embedded_video_ip_0_0_synth_1]
if {[llength $ooc_run] != 1} { error "未找到EmbeddedVideoIP的OOC综合run" }
if {![string match "*Complete*" [get_property STATUS $ooc_run]]} {
  error "EmbeddedVideoIP的OOC综合run未成功： [get_property STATUS $ooc_run]"
}
open_run $ooc_run
# The composite top's XDC is scoped to the IP in the catalog project. Apply
# the same CDC policy explicitly to this opened OOC run before reporting PPA.
set cdc_xdc [file join $repo_root ip video_pipeline_1_0 constraints embedded_video_ip_clocks.xdc]
if {![file isfile $cdc_xdc]} { error "缺少 EmbeddedVideoIP CDC XDC： $cdc_xdc" }
source $cdc_xdc
set axi_clock_group [get_clocks -quiet -include_generated_clocks *aclk*]
set pcm_clock_group [get_clocks -quiet -include_generated_clocks *audio_pcm_clk*]
set hdmi_clock_group [get_clocks -quiet -include_generated_clocks *hdmi_ref_clk*]
puts "EMBEDDED_VIDEO_IP_CLOCK_GROUP_MATCH: aclk=[llength $axi_clock_group] audio_pcm_clk=[llength $pcm_clock_group] hdmi_ref_with_generated=[llength $hdmi_clock_group]"
if {[llength $axi_clock_group] == 0 ||
    [llength $pcm_clock_group] == 0 ||
    [llength $hdmi_clock_group] == 0} {
  error "OOC综合未找到完整的异步时钟组"
}
report_clock_interaction -file [file join $out_dir clock_interaction.rpt]
report_exceptions -ignored_objects -file [file join $out_dir ignored_timing_exceptions.rpt]
report_methodology -file [file join $out_dir methodology.rpt]
report_cdc -details -file [file join $out_dir cdc.rpt]
report_bus_skew -warn_on_violation -file [file join $out_dir bus_skew.rpt]
report_utilization -file [file join $out_dir utilization.rpt]
report_timing_summary -delay_type min_max -file [file join $out_dir timing_summary.rpt]
write_checkpoint -force [file join $out_dir embedded_video_ip.dcp]
close_design
close_project
puts "EMBEDDED_VIDEO_IP_SYNTH_PASS: profile=$profile part=$part_name"
