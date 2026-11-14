# Usage: vivado -mode batch -source tools/package_ip.tcl -tclargs REPO_ROOT OUTPUT_IP_REPO
if {$argc < 2} { error "Usage: package_ip.tcl REPO_ROOT OUTPUT_IP_REPO" }
set repo_root [file normalize [lindex $argv 0]]
set output_repo [file normalize [lindex $argv 1]]
set source_dir [file join $repo_root ip video_pipeline_1_0 hdl]
set package_root [file join $output_repo panfpga video_pipeline]
file mkdir $package_root
if {[info exists ::env(VIDEO_IP_PACKAGE_WORK_DIR)] &&
    ($::env(VIDEO_IP_PACKAGE_WORK_DIR) ne "")} {
  set temp_dir [file normalize $::env(VIDEO_IP_PACKAGE_WORK_DIR)]
} else {
  set temp_dir [file join $repo_root out package_project]
}
file mkdir [file dirname $temp_dir]
create_project -force video_pipeline_package $temp_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]
foreach name {
  axis_video_nn_scaler.sv
  axis_rgb888.sv
  axis_video_mux3.sv
  video_bram_rgb565_reader.sv
  axi_lite_video_regs.sv
  video_pipeline_v1_0.sv
  video_pipeline_v1_0_wrapper.v
} {
  set source [file join $source_dir $name]
  if {![file isfile $source]} { error "Missing IP source: $source" }
  add_files -norecurse $source
}
set_property top video_pipeline_v1_0_wrapper [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $package_root -vendor panfpga.org -library video -taxonomy /Video -import_files -force
set core [ipx::current_core]
set_property name video_pipeline $core
set_property display_name {Embedded Video Pipeline} $core
set_property description {Portable AXI4-Stream RGB888 scaler with BRAM, HLS, and VDMA source adapters.} $core
set_property version 1.0 $core
set_property vendor_display_name {Personal FPGA IP} $core
set supported {}
foreach family {artix7 kintex7 virtex7 spartan7 zynq kintexu virtexu artixuplus kintexuplus virtexuplus zynquplus versal} {
  lappend supported $family Production
}
set_property supported_families $supported $core
set clock_if [ipx::get_bus_interfaces aclk -of_objects $core]
if {[llength $clock_if] > 0} {
  set assoc [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clock_if]
  if {[llength $assoc] > 0} {
    set_property value {m_axis_video:s_axis_hls:s_axis_vdma:s_axi} $assoc
  }
  set freq [ipx::get_bus_parameters FREQ_HZ -of_objects $clock_if]
  if {[llength $freq] == 0} {
    set freq [ipx::add_bus_parameter FREQ_HZ $clock_if]
  }
  set_property value 100000000 $freq
  set_property value_format long $freq
  set_property value_resolve_type user $freq
}
foreach {param value} {
  MAX_INPUT_WIDTH 640
  MAX_INPUT_HEIGHT 480
  OUTPUT_WIDTH 640
  OUTPUT_HEIGHT 480
  BRAM_ADDR_WIDTH 18
  AXI_ADDR_WIDTH 6
  ENABLE_BRAM_SOURCE 1
  ENABLE_HLS_SOURCE 1
  ENABLE_VDMA_SOURCE 1
  SOURCE_SELECT_MODE 0
  FIXED_SOURCE 2
  FORMAT_SELECT_MODE 0
  FIXED_FORMAT 2
  MAX_SCALER_INPUT_WIDTH 640
  MAX_SCALER_INPUT_HEIGHT 480
  ENABLE_SCALER 1
  LINE_BUFFER_IMPLEMENTATION 0
} {
  set iparam [ipx::get_user_parameters $param -of_objects $core]
  if {[llength $iparam] > 0} { set_property value $value $iparam }
}
set xgui_path [file join $package_root xgui video_pipeline_v1_0_wrapper_v1_0.tcl]
set xgui_fd [open $xgui_path r]
set xgui_text [read $xgui_fd]
close $xgui_fd
set xgui_extensions {
proc update_PARAM_VALUE.MAX_SCALER_INPUT_WIDTH { PARAM_VALUE.MAX_SCALER_INPUT_WIDTH PARAM_VALUE.MAX_INPUT_WIDTH } {
  set_property value [get_property value ${PARAM_VALUE.MAX_INPUT_WIDTH}] ${PARAM_VALUE.MAX_SCALER_INPUT_WIDTH}
}
proc update_PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT { PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT PARAM_VALUE.MAX_INPUT_HEIGHT } {
  set_property value [get_property value ${PARAM_VALUE.MAX_INPUT_HEIGHT}] ${PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT}
}
}
append xgui_text "\n[string trim $xgui_extensions]\n"
set xgui_fd [open $xgui_path w]
puts -nonewline $xgui_fd $xgui_text
close $xgui_fd

ipx::save_core $core
# Refresh the XGUI CHECKSUM marker after adding the dependency update procedures.
set xgui_crc [format %08x [zlib crc32 $xgui_text]]
set component_path [file join $package_root component.xml]
set component_fd [open $component_path r]
set component_text [read $component_fd]
close $component_fd
set xgui_marker "<spirit:name>xgui/video_pipeline_v1_0_wrapper_v1_0.tcl</spirit:name>"
set xgui_pos [string first $xgui_marker $component_text]
if {$xgui_pos < 0} { error "Packaged component.xml has no XGUI file entry" }
set checksum_start [string first "<spirit:userFileType>CHECKSUM_" $component_text $xgui_pos]
set checksum_end [string first "</spirit:userFileType>" $component_text $checksum_start]
if {$checksum_start < 0 || $checksum_end < 0} { error "Packaged XGUI checksum marker is missing" }
set checksum_xml "<spirit:userFileType>CHECKSUM_$xgui_crc</spirit:userFileType>"
set component_text [string replace $component_text $checksum_start [expr {$checksum_end + [string length "</spirit:userFileType>"] - 1}] $checksum_xml]
set component_fd [open $component_path w]
puts -nonewline $component_fd $component_text
close $component_fd
close_project
puts "VIDEO_IP_PACKAGE_PASS: $package_root"
