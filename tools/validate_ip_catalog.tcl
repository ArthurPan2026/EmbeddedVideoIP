if {$argc != 3} { error "用法：validate_ip_catalog.tcl 仓库根目录 IP仓库目录 输出目录" }
set repo_root [file normalize [lindex $argv 0]]
set ip_repo [file normalize [lindex $argv 1]]
set validation_dir [file normalize [lindex $argv 2]]
file mkdir [file dirname $validation_dir]
create_project -force embedded_video_ip_catalog_validation $validation_dir -part xc7z020clg400-1
set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog
set_msg_config -id {BD 41-1356} -new_severity INFO
set definitions [get_ipdefs -all panfpga.org:video:embedded_video_ip:1.0]
if {[llength $definitions] != 1} { error "Catalog 中应只有一个 EmbeddedVideoIP VLNV" }
create_bd_design embedded_video_ip_catalog_validation
create_bd_cell -type ip -vlnv panfpga.org:video:embedded_video_ip:1.0 embedded_video_ip_0
set cell [get_bd_cells embedded_video_ip_0]
foreach name {s_axi s_axis_vdma s_axis_hls s_axis_audio_pcm tmds_tx} {
  set intf [get_bd_intf_pins -quiet $cell/$name]
  if {[llength $intf] != 1} { error "缺少必需的接口： $name" }
  make_bd_intf_pins_external $intf
}
foreach name {aclk aresetn hdmi_ref_clk audio_pcm_clk bram_en bram_addr bram_dout bram_busy bram_frame_done} {
  set pin [get_bd_pins -quiet $cell/$name]
  if {[llength $pin] != 1} { error "缺少必需的端口： $name" }
  make_bd_pins_external $pin
}
foreach forbidden {hdmi_tx_hpd HDMI_DDC_IIC ac_bclk ac_mclk ac_pbdat ac_pblrc ac_muten} {
  if {[llength [get_bd_pins -quiet $cell/$forbidden]] > 0 ||
      [llength [get_bd_intf_pins -quiet $cell/$forbidden]] > 0} {
    error "EmbeddedVideoIP 不得包含外部系统专属或 I2S 接口： $forbidden"
  }
}
set_property -dict [list CONFIG.ENABLE_HDMI_AUDIO {0}] $cell
if {[get_property CONFIG.ENABLE_HDMI_AUDIO $cell] ne "0"} { error "未能保留音频关闭参数" }
validate_bd_design
set_property -dict [list CONFIG.ENABLE_HDMI_AUDIO {1}] $cell
if {[get_property CONFIG.ENABLE_HDMI_AUDIO $cell] ne "1"} { error "未能保留音频开启参数" }
validate_bd_design
save_bd_design
set bd_file [get_files -quiet embedded_video_ip_catalog_validation.bd]
if {[llength $bd_file] != 1} { error "Catalog 验证 BD 未保存" }
set cell_vlnv [get_property VLNV $cell]
if {$cell_vlnv ne "panfpga.org:video:embedded_video_ip:1.0"} { error "Composite IP VLNV 不符合预期： $cell_vlnv" }
puts "EMBEDDED_VIDEO_IP_CATALOG_PASS: $cell_vlnv audio_off=0 audio_on=1"
close_project
