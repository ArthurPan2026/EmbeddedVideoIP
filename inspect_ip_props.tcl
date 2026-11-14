open_project /home/pzy/Projects/Zynq-GBA_MisTer-Vivado/Zynq-GBA_MisTer-Vivado.xpr
open_bd_design [get_files -all -quiet *zynq_gba_system.bd]
set ic [get_bd_cells -quiet axi_ctrl_ic]
puts "INTERCONNECT_NUM_MI=[get_property CONFIG.NUM_MI $ic]"
puts "INTERCONNECT_PINS=[get_bd_pins -quiet -of_objects $ic]"
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_clock_converter:2.1 inspect_clock_converter
set cc [get_bd_cells inspect_clock_converter]
puts "CLOCK_CONV_CONFIG=[list_property $cc]"
puts "CLOCK_CONV_INTF=[get_bd_intf_pins -quiet -of_objects $cc]"
puts "CLOCK_CONV_PINS=[get_bd_pins -quiet -of_objects $cc]"
close_project
exit
