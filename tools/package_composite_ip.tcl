if {$argc != 3} { error "用法：package_composite_ip.tcl 仓库根目录 IP仓库目录 Composite工程目录" }
set repo_root [file normalize [lindex $argv 0]]
set output_repo [file normalize [lindex $argv 1]]
set project_dir [file normalize [lindex $argv 2]]
set hdl_dir [file join $repo_root ip video_pipeline_1_0 hdl]
set third_party_dir [file join $repo_root third_party digilent-rgb2dvi]
set package_root [file join $output_repo panfpga embedded_video_ip]
file mkdir [file dirname $package_root]
file mkdir [file dirname $project_dir]
create_project -force embedded_video_ip_package $project_dir -part xc7z020clg400-1
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property ip_repo_paths [list [file join $repo_root ip_repo]] [current_project]
update_ip_catalog
foreach source [lsort [concat [glob -nocomplain -directory $hdl_dir *.sv] [glob -nocomplain -directory $hdl_dir *.v] [glob -nocomplain -directory $third_party_dir *.vhd]]] {
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
create_bd_design embedded_video_ip_video_out
set aclk [create_bd_port -dir I -type clk -freq_hz 100000000 aclk]
set_property CONFIG.FREQ_HZ 100000000 $aclk
set refclk [create_bd_port -dir I -type clk -freq_hz 50000000 hdmi_ref_clk]
set_property CONFIG.FREQ_HZ 50000000 $refclk
set resetn [create_bd_port -dir I -type rst aresetn]
set_property CONFIG.POLARITY ACTIVE_LOW $resetn
set pixel_clk_port [create_bd_port -dir O -type clk pixel_clk]
set_property CONFIG.FREQ_HZ 25178571 $pixel_clk_port
set serial_clk_port [create_bd_port -dir O -type clk serial_clk]
set_property CONFIG.FREQ_HZ 125892857 $serial_clk_port
set pixel_reset_port [create_bd_port -dir O -type rst pixel_aresetn]
set_property CONFIG.POLARITY ACTIVE_LOW $pixel_reset_port
set video_out [create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 video_out]
set_property CONFIG.C_HAS_ASYNC_CLK 1 $video_out
set vtc [create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:6.2 vtc]
set_property -dict [list CONFIG.HAS_AXI4_LITE {false} CONFIG.VIDEO_MODE {480p} CONFIG.enable_detection {false}] $vtc
set clk_wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz]
set_property -dict [list \
  CONFIG.CLKIN1_JITTER_PS {200.0} \
  CONFIG.CLKOUT1_JITTER {244.697} \
  CONFIG.CLKOUT1_PHASE_ERROR {150.123} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.175} \
  CONFIG.CLKOUT2_JITTER {163.801} \
  CONFIG.CLKOUT2_PHASE_ERROR {150.123} \
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.875} \
  CONFIG.CLKOUT2_USED {true} \
  CONFIG.MMCM_CLKFBOUT_MULT_F {17.625} \
  CONFIG.MMCM_CLKIN1_PERIOD {20.000} \
  CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
  CONFIG.MMCM_CLKOUT0_DIVIDE_F {35.000} \
  CONFIG.MMCM_CLKOUT1_DIVIDE {7} \
  CONFIG.MMCM_DIVCLK_DIVIDE {1} \
  CONFIG.NUM_OUT_CLKS {2} \
  CONFIG.RESET_PORT {resetn} \
  CONFIG.RESET_TYPE {ACTIVE_LOW} \
  CONFIG.USE_LOCKED {true} \
  CONFIG.USE_RESET {true} \
] $clk_wiz
set rst [create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 pixel_reset]
set inv [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 reset_invert]
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] $inv
set zero [create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 reset_zero]
set_property -dict [list CONFIG.CONST_WIDTH {1} CONFIG.CONST_VAL {0}] $zero
connect_bd_intf_net [get_bd_intf_pins $vtc/vtiming_out] [get_bd_intf_pins $video_out/vtiming_in]
connect_bd_net $aclk [get_bd_pins $video_out/aclk]
connect_bd_net $resetn [get_bd_pins $video_out/aresetn]
connect_bd_net $refclk [get_bd_pins $clk_wiz/clk_in1]
connect_bd_net $resetn [get_bd_pins $clk_wiz/resetn] [get_bd_pins $inv/Op1]
connect_bd_net [get_bd_pins $clk_wiz/clk_out1] [get_bd_pins $vtc/clk] [get_bd_pins $video_out/vid_io_out_clk] [get_bd_pins $rst/slowest_sync_clk]
connect_bd_net [get_bd_pins $clk_wiz/clk_out2] $serial_clk_port
connect_bd_net [get_bd_pins $clk_wiz/clk_out1] $pixel_clk_port
connect_bd_net [get_bd_pins $clk_wiz/locked] [get_bd_pins $video_out/aclken] [get_bd_pins $video_out/vid_io_out_ce] [get_bd_pins $vtc/clken] [get_bd_pins $rst/dcm_locked]
connect_bd_net [get_bd_pins $video_out/vtg_ce] [get_bd_pins $vtc/gen_clken]
connect_bd_net [get_bd_pins $inv/Res] [get_bd_pins $rst/ext_reset_in]
connect_bd_net [get_bd_pins $zero/dout] [get_bd_pins $rst/aux_reset_in] [get_bd_pins $rst/mb_debug_sys_rst] [get_bd_pins $video_out/fid]
connect_bd_net [get_bd_pins $rst/peripheral_aresetn] $pixel_reset_port [get_bd_pins $vtc/resetn]
connect_bd_net [get_bd_pins $rst/peripheral_reset] [get_bd_pins $video_out/vid_io_out_reset]
make_bd_intf_pins_external [get_bd_intf_pins $video_out/video_in]
set stream_ports [get_bd_intf_ports -quiet]
if {[llength $stream_ports] != 1} { error "Expected one external video AXI4-Stream interface" }
set_property name s_axis_video [lindex $stream_ports 0]
set video_rgb_port [create_bd_port -dir O -from 23 -to 0 video_rgb]
set video_de_port [create_bd_port -dir O video_de]
set video_hsync_port [create_bd_port -dir O video_hsync]
set video_vsync_port [create_bd_port -dir O video_vsync]
connect_bd_net [get_bd_pins $video_out/vid_data] $video_rgb_port
connect_bd_net [get_bd_pins $video_out/vid_active_video] $video_de_port
connect_bd_net [get_bd_pins $video_out/vid_hsync] $video_hsync_port
connect_bd_net [get_bd_pins $video_out/vid_vsync] $video_vsync_port
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
ipx::save_core $core
set third_party_notice [file join $third_party_dir NOTICE.md]
if {![file isfile $third_party_notice]} { error "Missing Digilent source notice: $third_party_notice" }
set packaged_notice_dir [file join $package_root third_party digilent-rgb2dvi]
file mkdir $packaged_notice_dir
file copy -force $third_party_notice [file join $packaged_notice_dir NOTICE.md]
close_project
puts "EMBEDDED_VIDEO_IP_PACKAGE_PASS: $package_root"
