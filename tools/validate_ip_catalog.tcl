if {$argc < 2 || $argc > 3} { error "Usage: validate_ip_catalog.tcl REPO_ROOT IP_REPO ?OUTPUT_DIR?" }
set repo_root [file normalize [lindex $argv 0]]
set ip_repo [file normalize [lindex $argv 1]]
if {$argc == 3} {
  set validation_dir [file normalize [lindex $argv 2]]
} else {
  set validation_dir [file join $repo_root out ip_catalog_validation]
}
file mkdir [file dirname $validation_dir]
create_project -force video_ip_validation $validation_dir -part xc7z020clg400-1
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog
set definitions [get_ipdefs -all panfpga.org:video:video_pipeline:1.0]
if {[llength $definitions] == 0} { error "Video pipeline IP not found in IP catalog." }
create_bd_design video_pipeline_ip_validation
create_bd_cell -type ip -vlnv panfpga.org:video:video_pipeline:1.0 video_pipeline_0
set clk_port [create_bd_port -dir I -type clk -freq_hz 100000000 aclk]
set_property CONFIG.FREQ_HZ 100000000 $clk_port
set rst_port [create_bd_port -dir I -type rst aresetn]
set_property CONFIG.POLARITY ACTIVE_LOW $rst_port
connect_bd_net $clk_port [get_bd_pins video_pipeline_0/aclk]
connect_bd_net $rst_port [get_bd_pins video_pipeline_0/aresetn]
foreach intf {s_axi s_axis_hls s_axis_vdma m_axis_video} {
  make_bd_intf_pins_external [get_bd_intf_pins video_pipeline_0/$intf]
}
foreach pin {bram_en bram_addr bram_dout bram_busy bram_frame_done} {
  make_bd_pins_external [get_bd_pins video_pipeline_0/$pin]
}
# This isolated catalog check has no PS master. Exclude the exported slave segment;
# downgrade the corresponding validation-fixture diagnostics, not design DRC checks.
set_msg_config -id {BD 41-1630} -new_severity {INFO}
set_msg_config -id {BD 41-1629} -new_severity {INFO}
set register_segment [get_bd_addr_segs -quiet video_pipeline_0/s_axi/reg0]
if {[llength $register_segment] > 0} {
  set register_space [get_bd_addr_spaces -quiet /s_axi_0]
  if {[llength $register_space] > 0} {
    exclude_bd_addr_seg -target_address_space $register_space $register_segment
  }
}
validate_bd_design
# Re-customize the same catalog instance with the concrete GBA static profile.
set_property -dict [list \
  CONFIG.ENABLE_BRAM_SOURCE {0} \
  CONFIG.ENABLE_HLS_SOURCE {0} \
  CONFIG.ENABLE_VDMA_SOURCE {1} \
  CONFIG.SOURCE_SELECT_MODE {1} \
  CONFIG.FIXED_SOURCE {2} \
  CONFIG.FORMAT_SELECT_MODE {1} \
  CONFIG.FIXED_FORMAT {2} \
  CONFIG.MAX_SCALER_INPUT_WIDTH {240} \
  CONFIG.MAX_SCALER_INPUT_HEIGHT {160} \
  CONFIG.ENABLE_SCALER {1} \
] [get_bd_cells video_pipeline_0]
if {[get_property CONFIG.MAX_SCALER_INPUT_WIDTH [get_bd_cells video_pipeline_0]] != 240 ||
    [get_property CONFIG.MAX_SCALER_INPUT_HEIGHT [get_bd_cells video_pipeline_0]] != 160} {
  error "IP catalog did not retain GBA scaler buffer limits"
}
validate_bd_design
save_bd_design
puts "VIDEO_IP_CATALOG_PASS: [get_property VLNV [lindex $definitions 0]]"
close_project
