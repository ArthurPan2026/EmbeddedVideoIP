if {$argc != 3} { error "用法：package_composite_ip.tcl 仓库根目录 IP仓库目录 Composite工程目录" }
set repo_root [file normalize [lindex $argv 0]]
set output_repo [file normalize [lindex $argv 1]]
set project_dir [file normalize [lindex $argv 2]]
set hdl_dir [file join $repo_root ip video_pipeline_1_0 hdl]
set package_root [file join $output_repo panfpga embedded_video_ip]
file mkdir [file dirname $package_root]
file mkdir [file dirname $project_dir]
create_project -force embedded_video_ip_package $project_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]
set_property ip_repo_paths [list [file join $repo_root ip_repo]] [current_project]
update_ip_catalog
foreach source [lsort [concat [glob -nocomplain -directory $hdl_dir *.sv] [glob -nocomplain -directory $hdl_dir *.v]]] {
  if {![file isfile $source]} { error "缺少 HDL 源文件： $source" }
  add_files -norecurse $source
}
set cdc_xdc [file join $repo_root ip video_pipeline_1_0 constraints embedded_video_ip_clocks.xdc]
if {![file isfile $cdc_xdc]} { error "缺少 EmbeddedVideoIP CDC XDC： $cdc_xdc" }
add_files -norecurse $cdc_xdc
set cdc_xdc_file [get_files -quiet $cdc_xdc]
if {[llength $cdc_xdc_file] != 1} { error "CDC XDC 未加入打包工程" }
set_property SCOPED_TO_REF embedded_video_ip_top $cdc_xdc_file
set_property PROCESSING_ORDER LATE $cdc_xdc_file
set_property USED_IN_SYNTHESIS true $cdc_xdc_file
set_property USED_IN_IMPLEMENTATION true $cdc_xdc_file
create_bd_design embedded_video_ip_video_out
set aclk [create_bd_port -dir I -type clk -freq_hz 100000000 aclk]
set_property CONFIG.FREQ_HZ 100000000 $aclk
set refclk [create_bd_port -dir I -type clk -freq_hz 50000000 hdmi_ref_clk]
set_property CONFIG.FREQ_HZ 50000000 $refclk
set resetn [create_bd_port -dir I -type rst aresetn]
set_property CONFIG.POLARITY ACTIVE_LOW $resetn
set pixel_clk_port [create_bd_port -dir O -type clk pixel_clk]
# Vivado's static interface metadata describes the VGA boot profile; runtime selection
# changes this clock to the shared HD profile (74.21875 MHz / 371.09375 MHz).
set_property CONFIG.FREQ_HZ 25178571 $pixel_clk_port
set serial_clk_port [create_bd_port -dir O -type clk serial_clk]
set_property CONFIG.FREQ_HZ 125892857 $serial_clk_port
set pixel_reset_port [create_bd_port -dir O -type rst pixel_aresetn]
set_property CONFIG.POLARITY ACTIVE_LOW $pixel_reset_port
set pixel_locked_port [create_bd_port -dir O hdmi_mmcm_locked]
set pixel_reset_ext_port [create_bd_port -dir O pixel_reset_ext_asserted]
set clock_profile_sel_port [create_bd_port -dir I clock_profile_sel]
set timing_profile_port [create_bd_port -dir I -from 1 -to 0 timing_profile]
set pixel_reset_hold_port [create_bd_port -dir I pixel_reset_hold]
set locked_profiles_port [create_bd_port -dir O -from 1 -to 0 locked_profiles]
set video_out [create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 video_out]
set_property CONFIG.C_HAS_ASYNC_CLK 1 $video_out
set_property CONFIG.C_VTG_MASTER_SLAVE 1 $video_out

# Independent VGA and HD clock syntheses; the HD outputs retain the required 5:1 TMDS ratio.
set clk_wiz_vga [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_vga]
set_property -dict [list CONFIG.PRIM_IN_FREQ {50.000} CONFIG.CLKIN1_JITTER_PS {200.0} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.178571} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.892857} CONFIG.CLKOUT2_USED {true} CONFIG.NUM_OUT_CLKS {2} CONFIG.RESET_PORT {resetn} CONFIG.RESET_TYPE {ACTIVE_LOW} CONFIG.USE_LOCKED {true} CONFIG.USE_RESET {true}] $clk_wiz_vga
set clk_wiz_hd [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_hd]
set_property -dict [list CONFIG.PRIM_IN_FREQ {50.000} CONFIG.CLKIN1_JITTER_PS {200.0} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {74.21875} CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {371.09375} CONFIG.CLKOUT2_USED {true} CONFIG.NUM_OUT_CLKS {2} CONFIG.RESET_PORT {resetn} CONFIG.RESET_TYPE {ACTIVE_LOW} CONFIG.USE_LOCKED {true} CONFIG.USE_RESET {true}] $clk_wiz_hd

set clock_mux [create_bd_cell -type module -reference embedded_video_ip_clock_profile_mux_wrapper clock_profile_mux]
set timing_gen [create_bd_cell -type module -reference embedded_video_ip_timing_gen_wrapper timing_gen]
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 pixel_reset]
# External reset assertion and controlled mode-transition hold share the reset synchronizer.
set_property -dict [list CONFIG.C_EXT_RESET_HIGH {1} CONFIG.C_AUX_RESET_HIGH {1}] $rst
set inv [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 reset_invert]
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $inv
set reset_or [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 reset_or_mode_hold]
set_property -dict [list CONFIG.C_OPERATION {or} CONFIG.C_SIZE {1}] $reset_or
set aclken_invert [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 video_out_aclken_invert]
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $aclken_invert
set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 reset_zero]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $zero
set video_out_pixel_ce_one [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 video_out_pixel_ce_one]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {1}] $video_out_pixel_ce_one

connect_bd_intf_net [get_bd_intf_pins $timing_gen/video_timing] [get_bd_intf_pins $video_out/vtiming_in]
connect_bd_net $aclk [get_bd_pins $video_out/aclk]
connect_bd_net $resetn [get_bd_pins $video_out/aresetn]
connect_bd_net $refclk [get_bd_pins $clk_wiz_vga/clk_in1] [get_bd_pins $clk_wiz_hd/clk_in1]
connect_bd_net $resetn [get_bd_pins $clk_wiz_vga/resetn] [get_bd_pins $clk_wiz_hd/resetn] [get_bd_pins $inv/Op1]
connect_bd_net [get_bd_pins $clk_wiz_vga/clk_out1] [get_bd_pins $clock_mux/vga_pixel_clk]
connect_bd_net [get_bd_pins $clk_wiz_vga/clk_out2] [get_bd_pins $clock_mux/vga_serial_clk]
connect_bd_net [get_bd_pins $clk_wiz_vga/locked] [get_bd_pins $clock_mux/vga_locked]
connect_bd_net [get_bd_pins $clk_wiz_hd/clk_out1] [get_bd_pins $clock_mux/hd_pixel_clk]
connect_bd_net [get_bd_pins $clk_wiz_hd/clk_out2] [get_bd_pins $clock_mux/hd_serial_clk]
connect_bd_net [get_bd_pins $clk_wiz_hd/locked] [get_bd_pins $clock_mux/hd_locked]
connect_bd_net $clock_profile_sel_port [get_bd_pins $clock_mux/clock_profile_sel]
connect_bd_net [get_bd_pins $clock_mux/pixel_clk] $pixel_clk_port [get_bd_pins $timing_gen/pixel_clk] [get_bd_pins $video_out/vid_io_out_clk] [get_bd_pins $rst/slowest_sync_clk]
connect_bd_net [get_bd_pins $clock_mux/serial_clk] $serial_clk_port
connect_bd_net [get_bd_pins $clock_mux/locked_profiles] $locked_profiles_port
connect_bd_net [get_bd_pins $clock_mux/selected_locked] $pixel_locked_port [get_bd_pins $rst/dcm_locked]
connect_bd_net $pixel_reset_hold_port [get_bd_pins $aclken_invert/Op1]
connect_bd_net [get_bd_pins $aclken_invert/Res] [get_bd_pins $video_out/aclken]
connect_bd_net [get_bd_pins $video_out_pixel_ce_one/dout] [get_bd_pins $video_out/vid_io_out_ce]
connect_bd_net $timing_profile_port [get_bd_pins $timing_gen/timing_profile]
connect_bd_net [get_bd_pins $video_out_pixel_ce_one/dout] [get_bd_pins $timing_gen/enable]
connect_bd_net [get_bd_pins $inv/Res] [get_bd_pins $reset_or/Op1]
connect_bd_net $pixel_reset_hold_port [get_bd_pins $reset_or/Op2]
connect_bd_net [get_bd_pins $reset_or/Res] $pixel_reset_ext_port [get_bd_pins $rst/ext_reset_in]
connect_bd_net [get_bd_pins $zero/dout] [get_bd_pins $rst/aux_reset_in] [get_bd_pins $rst/mb_debug_sys_rst] [get_bd_pins $video_out/fid]
connect_bd_net [get_bd_pins $rst/peripheral_aresetn] $pixel_reset_port [get_bd_pins $timing_gen/resetn]
connect_bd_net [get_bd_pins $rst/peripheral_reset] [get_bd_pins $video_out/vid_io_out_reset]

make_bd_intf_pins_external [get_bd_intf_pins $video_out/video_in]
set stream_ports [get_bd_intf_ports -quiet]
if {[llength $stream_ports] != 1} { error "Expected one external video AXI4-Stream interface" }
set_property name s_axis_video [lindex $stream_ports 0]
set video_rgb_port [create_bd_port -dir O -from 23 -to 0 video_rgb]
set video_de_port [create_bd_port -dir O video_de]
set video_hsync_port [create_bd_port -dir O video_hsync]
set video_vsync_port [create_bd_port -dir O video_vsync]
set video_vsync_raw_port [create_bd_port -dir O video_vsync_raw]
connect_bd_net [get_bd_pins $video_out/vid_data] $video_rgb_port
connect_bd_net [get_bd_pins $video_out/vid_active_video] $video_de_port
connect_bd_net [get_bd_pins $video_out/vid_hsync] $video_hsync_port
connect_bd_net [get_bd_pins $video_out/vid_vsync] $video_vsync_port
connect_bd_net [get_bd_pins $timing_gen/VSYNC] $video_vsync_raw_port
validate_bd_design
save_bd_design
set bd_file [get_files -quiet embedded_video_ip_video_out.bd]
if {[llength $bd_file] != 1} { error "视频输出 BD 数量应为 1" }
generate_target all $bd_file
set wrapper_file [make_wrapper -files $bd_file -top]
if {![file isfile $wrapper_file]} { error "缺少生成的视频输出 wrapper" }
add_files -norecurse $wrapper_file
set_property top embedded_video_ip_video_out_wrapper [current_fileset]
update_compile_order -fileset sources_1
set_property top embedded_video_ip_top [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $package_root -vendor panfpga.org -library video -taxonomy /Video -import_files -force
set core [ipx::current_core]
set_property core_revision 3 $core
set version_fd [open [file join $repo_root VERSION] r]
set product_version [string trim [read $version_fd]]
close $version_fd
set_property name embedded_video_ip $core
set_property display_name "EmbeddedVideoIP $product_version" $core
set_property description "EmbeddedVideoIP product release $product_version; composite 7-series HDMI video with optional audio." $core
set_property version 1.0 $core
set_property vendor_display_name {Personal FPGA IP} $core
set supported {}
foreach family {zynq} {
  lappend supported $family Production
}
set_property supported_families $supported $core
ipx::infer_bus_interfaces {{xilinx.com:interface:axis:1.0} {xilinx.com:interface:aximm_rtl:1.0} {xilinx.com:signal:clock_rtl:1.0} {xilinx.com:signal:reset_rtl:1.0}} $core
ipx::remove_bus_interface tmds_tx_clk_p $core
ipx::remove_bus_interface tmds_tx_clk_n $core

# Group the differential clock and data lanes as the EmbeddedVideoIP TMDS I/O interface.
# The RTL ports stay unchanged so board XDC pin names and lane order are stable.
set tmds_if [ipx::add_bus_interface tmds_tx $core]
set_property bus_type_vlnv {panfpga.org:interface:tmds:1.0} $tmds_if
set_property abstraction_type_vlnv {panfpga.org:interface:tmds_rtl:1.0} $tmds_if
set_property interface_mode {master} $tmds_if
foreach {logical physical} {
  CLK_P tmds_tx_clk_p
  CLK_N tmds_tx_clk_n
  DATA_P tmds_tx_data_p
  DATA_N tmds_tx_data_n
} {
  set port_map [ipx::add_port_map $logical $tmds_if]
  set_property logical_name $logical $port_map
  set_property physical_name $physical $port_map
}
foreach {clock_name frequency bus_list} {
  aclk 100000000 {S_AXI S_AXIS_HLS S_AXIS_VDMA}
  audio_pcm_clk 100000000 {S_AXIS_AUDIO_PCM}
  hdmi_ref_clk 50000000 {}
} {
  set clock_if [ipx::get_bus_interfaces $clock_name -of_objects $core]
  if {[llength $clock_if] == 0} { error "缺少时钟接口： $clock_name" }
  set freq [ipx::get_bus_parameters FREQ_HZ -of_objects $clock_if]
  if {[llength $freq] == 0} { set freq [ipx::add_bus_parameter FREQ_HZ $clock_if] }
  set_property value $frequency $freq
  set_property value_format long $freq
  set_property value_resolve_type user $freq
  if {[llength $bus_list] > 0} {
    set assoc [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $clock_if]
    if {[llength $assoc] == 0} { set assoc [ipx::add_bus_parameter ASSOCIATED_BUSIF $clock_if] }
    set_property value [join $bus_list :] $assoc
  }
  if {$clock_name eq "aclk"} {
    set assoc_reset [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $clock_if]
    if {[llength $assoc_reset] == 0} { set assoc_reset [ipx::add_bus_parameter ASSOCIATED_RESET $clock_if] }
    set_property value aresetn $assoc_reset
  }
}
set reset_if [ipx::get_bus_interfaces aresetn -of_objects $core]
if {[llength $reset_if] > 0} {
  set polarity [ipx::get_bus_parameters POLARITY -of_objects $reset_if]
  if {[llength $polarity] == 0} { set polarity [ipx::add_bus_parameter POLARITY $reset_if] }
  set_property value ACTIVE_LOW $polarity
}
foreach {param value} {
  ENABLE_HDMI_AUDIO 0
  AUDIO_SAMPLE_RATE_HZ 48000
  OUTPUT_COLOR_MODE 0
  COLORIMETRY 0
  YCC_RANGE 0
  OUTPUT_COLOR_DEPTH 8
  MAX_INPUT_WIDTH 1280
  MAX_INPUT_HEIGHT 720
  OUTPUT_WIDTH 1920
  OUTPUT_HEIGHT 1080
  BRAM_ADDR_WIDTH 18
  AXI_ADDR_WIDTH 6
  ENABLE_BRAM_SOURCE 1
  ENABLE_HLS_SOURCE 1
  ENABLE_VDMA_SOURCE 1
  SOURCE_SELECT_MODE 0
  FIXED_SOURCE 2
  FORMAT_SELECT_MODE 0
  FIXED_FORMAT 2
  MAX_SCALER_INPUT_WIDTH 1280
  MAX_SCALER_INPUT_HEIGHT 720
  ENABLE_SCALER 1
  LINE_BUFFER_IMPLEMENTATION 1
} {
  set iparam [ipx::get_user_parameters $param -of_objects $core]
  if {[llength $iparam] > 0} { set_property value $value $iparam }
}
ipx::save_core $core

# Mark the scoped CDC XDC for both implementation and synthesis. IPX imports
# user XDC files as out-of-context-only unless these usage flags are explicit.
set component_xml [file join $package_root component.xml]
set component_fd [open $component_xml r]
set component_text [read $component_fd]
close $component_fd
if {[regexp {<spirit:name>[^<]+\.vhd</spirit:name>} $component_text]} {
  error "Composite HDMI TX package must contain only SystemVerilog/Verilog sources"
}
set xdc_marker {<spirit:name>src/embedded_video_ip_clocks.xdc</spirit:name>
        <spirit:userFileType>xdc</spirit:userFileType>
        <spirit:userFileType>IMPORTED_FILE</spirit:userFileType>}
if {[string first $xdc_marker $component_text] < 0} {
  error "Composite IP component.xml is missing its CDC XDC file entry"
}
set xdc_replacement "$xdc_marker
        <spirit:userFileType>USED_IN_synthesis</spirit:userFileType>
        <spirit:userFileType>USED_IN_implementation</spirit:userFileType>"
set component_text [string map [list $xdc_marker $xdc_replacement] $component_text]
set component_fd [open $component_xml w]
puts -nonewline $component_fd $component_text
close $component_fd
# Publish the project-owned TMDS interface definitions with the packaged IP.
set stale_third_party_dir [file join $package_root third_party]
if {[file exists $stale_third_party_dir]} { file delete -force $stale_third_party_dir }
set packaged_tmds_dir [file join $output_repo if tmds_v1_0]
file mkdir $packaged_tmds_dir
foreach interface_file {tmds.xml tmds_rtl.xml} {
  set source_file [file join $repo_root ip_repo if tmds_v1_0 $interface_file]
  if {![file isfile $source_file]} { error "Missing project TMDS interface definition: $source_file" }
  file copy -force $source_file [file join $packaged_tmds_dir $interface_file]
}

close_project
puts "EMBEDDED_VIDEO_IP_PACKAGE_PASS: $package_root"
