# Usage: vivado -mode batch -source tools/synth_core.tcl -tclargs REPO_ROOT PART OUT_DIR
if {$argc < 3} { error "Usage: synth_core.tcl REPO_ROOT PART OUT_DIR" }
set repo_root [file normalize [lindex $argv 0]]
set part_name [lindex $argv 1]
set out_dir [file normalize [lindex $argv 2]]
file mkdir $out_dir
set proj_dir [file join $out_dir project]
create_project -force video_core_synth $proj_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set hdl_dir [file join $repo_root ip video_pipeline_1_0 hdl]
foreach name {
  axis_video_nn_scaler.sv
  axis_rgb888.sv
  axis_video_mux3.sv
  video_bram_rgb565_reader.sv
  axi_lite_video_regs.sv
  video_pipeline_v1_0.sv
} {
  set source [file join $hdl_dir $name]
  if {![file isfile $source]} { error "Missing source: $source" }
  add_files -norecurse $source
}
set_property top video_pipeline_v1_0 [current_fileset]
update_compile_order -fileset sources_1
synth_design -top video_pipeline_v1_0 -part $part_name -mode out_of_context
create_clock -name aclk -period 10.000 [get_ports aclk]
report_utilization -file [file join $out_dir utilization.rpt]
report_timing_summary -delay_type max -file [file join $out_dir timing_summary.rpt]
write_checkpoint -force [file join $out_dir video_pipeline.dcp]
close_project
puts "VIDEO_SYNTH_PASS: part=$part_name"
