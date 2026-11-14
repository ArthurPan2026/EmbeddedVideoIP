open_project /home/pzy/Projects/Zynq-GBA_MisTer-Vivado/Zynq-GBA_MisTer-Vivado.xpr
open_bd_design [get_files -all -quiet *zynq_gba_system.bd]
set ic [get_bd_cells axi_ctrl_ic]
foreach prop [list_property $ic] {
    if {[regexp {CONFIG\.(NUM_MI|.*PROTOCOL|.*WIDTH|.*CLOCK)} $prop]} {
        catch {puts "$prop=[get_property $prop $ic]"}
    }
}
close_project
exit
