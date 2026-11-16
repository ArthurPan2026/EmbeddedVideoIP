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
puts "EMBEDDED_VIDEO_IP_PACKAGE_STAGE_PASS: $output_repo"
