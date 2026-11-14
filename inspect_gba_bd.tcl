set_param general.maxThreads 4
open_project /home/pzy/Projects/Zynq-GBA_MisTer-Vivado/Zynq-GBA_MisTer-Vivado.xpr
set bd_file [get_files -all -quiet *zynq_gba_system.bd]
puts "BD=$bd_file"
open_bd_design $bd_file
puts "-- CELLS --"
foreach cell [lsort [get_bd_cells -hier]] {
    set name [get_property NAME $cell]
    if {[regexp -nocase {hdmi|vdma|video|rgb|gba_pl_top} $name]} {
        puts "CELL [get_property NAME $cell] [get_property VLNV $cell]"
    }
}
puts "-- STREAM NETS --"
foreach net [get_bd_intf_nets] {
    set pins [get_bd_intf_pins -of_objects $net]
    if {[regexp -nocase {hdmi|vdma|video|rgb|gba_pl_top} "$net $pins"]} {
        puts "NET [get_property NAME $net] $pins"
    }
}
close_project
exit
