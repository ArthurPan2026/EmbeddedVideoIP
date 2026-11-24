if {$argc != 3} { error "用法：package_composite_ip.tcl 仓库根目录 IP仓库目录 Composite工程目录" }
set repo_root [file normalize [lindex $argv 0]]
set output_repo [file normalize [lindex $argv 1]]
set project_dir [file normalize [lindex $argv 2]]
set hdl_dir [file join $repo_root ip video_pipeline_1_0 hdl]
set package_root [file join $output_repo panfpga embedded_video_ip]
if {[file exists $package_root]} { file delete -force $package_root }
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
set resetn [create_bd_port -dir I -type rst aresetn]
set_property CONFIG.POLARITY ACTIVE_LOW $resetn

# Keep only the AXI4S-to-video subcore. VGA and HD clock generation,
# timing and pixel reset are canonical synthesizable RTL.
set video_out [create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 video_out]
set_property CONFIG.C_HAS_ASYNC_CLK 1 $video_out
set_property CONFIG.C_VTG_MASTER_SLAVE 1 $video_out
set aclk [create_bd_port -dir I -type clk -freq_hz 100000000 aclk]
set_property CONFIG.FREQ_HZ 100000000 $aclk
connect_bd_net $aclk [get_bd_pins $video_out/aclk]
connect_bd_net $resetn [get_bd_pins $video_out/aresetn]
make_bd_intf_pins_external [get_bd_intf_pins $video_out/video_in]
set stream_ports [get_bd_intf_ports -quiet]
if {[llength $stream_ports] != 1} { error "Expected one external video AXI4-Stream interface" }
set_property name s_axis_video [lindex $stream_ports 0]
make_bd_intf_pins_external [get_bd_intf_pins $video_out/vtiming_in]
foreach pin_name {vid_io_out_clk vid_io_out_reset aclken vid_io_out_ce fid} {
  make_bd_pins_external [get_bd_pins $video_out/$pin_name]
}
foreach pin_name {vid_data vid_active_video vid_hsync vid_vsync} {
  make_bd_pins_external [get_bd_pins $video_out/$pin_name]
}
validate_bd_design
save_bd_design
set bd_file [get_files -quiet embedded_video_ip_video_out.bd]
if {[llength $bd_file] != 1} { error "Expected one embedded_video_ip_video_out BD" }
generate_target all $bd_file
# The canonical video-out wrapper instantiates the BD-generated child wrapper
# directly. Package both that wrapper and the generated Xilinx subcore HDL so
# consumers do not depend on files hidden under the disposable .gen directory.
set generated_bd_root [file join $project_dir embedded_video_ip_package.gen sources_1 bd embedded_video_ip_video_out]
set video_out_wrapper [file join $generated_bd_root ip embedded_video_ip_video_out_video_out_0 synth embedded_video_ip_video_out_video_out_0.v]
if {![file isfile $video_out_wrapper]} {
  error "Missing generated v_axi4s_vid_out wrapper: $video_out_wrapper"
}
set video_out_impl_matches [glob -nocomplain -directory [file join $generated_bd_root ipshared] */hdl/v_axi4s_vid_out_v4_0_vl_rfs.v]
if {[llength $video_out_impl_matches] != 1} {
  error "Expected exactly one generated v_axi4s_vid_out implementation, found [llength $video_out_impl_matches]"
}
set video_out_impl [lindex $video_out_impl_matches 0]
# Use the canonical source wrapper, not a generated duplicate BD wrapper.
set_property top embedded_video_ip_top [current_fileset]
update_compile_order -fileset sources_1
ipx::package_project -root_dir $package_root -vendor panfpga.org -library video -taxonomy /Video -import_files -force
set core [ipx::current_core]
# The parent wrapper instantiates this generated child wrapper by module name;
# the child wrapper in turn instantiates v_axi4s_vid_out_v4_0_20. Keep both
# project-local in the package and register them for synthesis and simulation.
set package_vout_wrapper_relative src/embedded_video_ip_video_out_video_out_0.v
set package_vout_impl_relative src/v_axi4s_vid_out_v4_0_vl_rfs.v
file copy -force $video_out_wrapper [file join $package_root $package_vout_wrapper_relative]
file copy -force $video_out_impl [file join $package_root $package_vout_impl_relative]
set synth_group [ipx::get_file_groups xilinx_anylanguagesynthesis -of_objects $core]
set sim_group [ipx::get_file_groups xilinx_anylanguagebehavioralsimulation -of_objects $core]
if {[llength $synth_group] != 1 || [llength $sim_group] != 1} {
  error "Composite package synthesis or simulation file group is missing"
}
foreach relative_file [list $package_vout_wrapper_relative $package_vout_impl_relative] {
  ipx::add_file $relative_file $synth_group
  ipx::add_file $relative_file $sim_group
  set synth_file [ipx::get_files $relative_file -of_objects $synth_group]
  set sim_file [ipx::get_files $relative_file -of_objects $sim_group]
  if {[llength $synth_file] != 1 || [llength $sim_file] != 1} {
    error "Generated video-out source was not registered in package file groups: $relative_file"
  }
  set_property type verilogSource $synth_file
  set_property type verilogSource $sim_file
}
set_property core_revision 7 $core
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
