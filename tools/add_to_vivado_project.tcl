# Usage: source <EmbeddedVideoIP>/tools/add_to_vivado_project.tcl
# The target Vivado project must already be open.
if {[llength [get_projects -quiet]] == 0} {
  error "Open a Vivado project before registering the EmbeddedVideoIP catalog."
}
set script_path [file normalize [info script]]
set repo_root [file normalize [file join [file dirname $script_path] ..]]
set ip_repo [file join $repo_root ip_repo]
set component [file join $ip_repo panfpga video_pipeline component.xml]
if {![file isfile $component]} {
  error "Packaged video_pipeline IP is missing: $component. Run tools/video_flow.py package first."
}
set current_repos [get_property ip_repo_paths [current_project]]
if {[lsearch -exact $current_repos $ip_repo] < 0} {
  lappend current_repos $ip_repo
  set_property ip_repo_paths $current_repos [current_project]
}
update_ip_catalog -rebuild
set matches [get_ipdefs -all -filter {VLNV =~ panfpga.org:video:video_pipeline:*}]
if {[llength $matches] == 0} {
  error "Vivado did not find panfpga.org:video:video_pipeline in the refreshed catalog."
}
puts "VIDEO_IP_PROJECT_INSTALL_PASS: [get_property VLNV [lindex $matches 0]]"
