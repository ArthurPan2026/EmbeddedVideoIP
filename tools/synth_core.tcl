# Usage: vivado -mode batch -source tools/synth_core.tcl -tclargs REPO_ROOT PART OUT_DIR ?PROFILE ?NAME=VALUE ...?
if {$argc < 3} { error "Usage: synth_core.tcl REPO_ROOT PART OUT_DIR ?PROFILE ?NAME=VALUE ...?" }
set repo_root [file normalize [lindex $argv 0]]
set part_name [lindex $argv 1]
set out_dir [file normalize [lindex $argv 2]]
set profile "generic"
set generic_values {}
if {$argc >= 4} {
  set profile [lindex $argv 3]
  set generic_values [lrange $argv 4 end]
}
if {[lsearch -exact {generic gba passthrough} $profile] < 0} {
  error "Unknown synthesis profile: $profile"
}
if {$profile eq "generic" && [llength $generic_values] != 0} {
  error "The generic profile does not accept parameter overrides."
}
if {$profile ne "generic" && [llength $generic_values] == 0} {
  error "Profile $profile requires explicit parameter overrides."
}
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
set synth_command [list synth_design -top video_pipeline_v1_0 -part $part_name -mode out_of_context]
foreach generic $generic_values {
  if {![regexp {^[A-Z][A-Z0-9_]*=[0-9]+$} $generic]} {
    error "Invalid synthesis generic: $generic"
  }
  # UG901 supports one -generic NAME=VALUE pair per top-level parameter.
  lappend synth_command -generic $generic
}
puts "VIDEO_SYNTH_PROFILE: $profile"
puts "VIDEO_SYNTH_ARGC: $argc"
puts "VIDEO_SYNTH_ARGV: $argv"
puts "VIDEO_SYNTH_GENERIC_VALUES: $generic_values"
puts "VIDEO_SYNTH_COMMAND: $synth_command"
# Vivado 2025.2.1's synth_design parser rejects repeated -generic options
# when this list is invoked with Tcl {*} expansion. eval reparses it as a
# regular Tcl command; every element is a validated option/value token.
eval $synth_command
create_clock -name aclk -period 10.000 [get_ports aclk]
report_utilization -file [file join $out_dir utilization.rpt]
report_timing_summary -delay_type max -file [file join $out_dir timing_summary.rpt]
write_checkpoint -force [file join $out_dir video_pipeline.dcp]
close_project
puts "VIDEO_SYNTH_PASS: profile=$profile part=$part_name"
