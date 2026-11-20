if {$argc != 3} { error "用法：package_all.tcl 仓库根目录 IP仓库目录 Composite工程目录" }
set repo_root [file normalize [lindex $argv 0]]
set output_repo [file normalize [lindex $argv 1]]
set project_dir [file normalize [lindex $argv 2]]
set argc 2
set argv [list $repo_root $output_repo]
source [file join $repo_root tools package_ip.tcl]
set argc 3
set argv [list $repo_root $output_repo $project_dir]
source [file join $repo_root tools package_composite_ip.tcl]
set metadata_python [auto_execok python3]
if {$metadata_python eq ""} { set metadata_python [auto_execok python] }
if {$metadata_python eq ""} { error "Python is required to write package metadata." }
if {[catch {exec $metadata_python [file join $repo_root tools generate_package_metadata.py] --root $repo_root --package [file join $output_repo panfpga embedded_video_ip] --vivado-version [version -short]} metadata_error]} {
    error "Package metadata generation failed: $metadata_error"
}
puts "EMBEDDED_VIDEO_IP_PACKAGE_STAGE_PASS: $output_repo"
