# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "AXI_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BRAM_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_INPUT_HEIGHT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_INPUT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "OUTPUT_HEIGHT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "OUTPUT_WIDTH" -parent ${Page_0}


}

proc update_PARAM_VALUE.AXI_ADDR_WIDTH { PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to update AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.AXI_ADDR_WIDTH { PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to validate AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.BRAM_ADDR_WIDTH { PARAM_VALUE.BRAM_ADDR_WIDTH } {
	# Procedure called to update BRAM_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BRAM_ADDR_WIDTH { PARAM_VALUE.BRAM_ADDR_WIDTH } {
	# Procedure called to validate BRAM_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.MAX_INPUT_HEIGHT { PARAM_VALUE.MAX_INPUT_HEIGHT } {
	# Procedure called to update MAX_INPUT_HEIGHT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAX_INPUT_HEIGHT { PARAM_VALUE.MAX_INPUT_HEIGHT } {
	# Procedure called to validate MAX_INPUT_HEIGHT
	return true
}

proc update_PARAM_VALUE.MAX_INPUT_WIDTH { PARAM_VALUE.MAX_INPUT_WIDTH } {
	# Procedure called to update MAX_INPUT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAX_INPUT_WIDTH { PARAM_VALUE.MAX_INPUT_WIDTH } {
	# Procedure called to validate MAX_INPUT_WIDTH
	return true
}

proc update_PARAM_VALUE.OUTPUT_HEIGHT { PARAM_VALUE.OUTPUT_HEIGHT } {
	# Procedure called to update OUTPUT_HEIGHT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.OUTPUT_HEIGHT { PARAM_VALUE.OUTPUT_HEIGHT } {
	# Procedure called to validate OUTPUT_HEIGHT
	return true
}

proc update_PARAM_VALUE.OUTPUT_WIDTH { PARAM_VALUE.OUTPUT_WIDTH } {
	# Procedure called to update OUTPUT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.OUTPUT_WIDTH { PARAM_VALUE.OUTPUT_WIDTH } {
	# Procedure called to validate OUTPUT_WIDTH
	return true
}


proc update_MODELPARAM_VALUE.MAX_INPUT_WIDTH { MODELPARAM_VALUE.MAX_INPUT_WIDTH PARAM_VALUE.MAX_INPUT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAX_INPUT_WIDTH}] ${MODELPARAM_VALUE.MAX_INPUT_WIDTH}
}

proc update_MODELPARAM_VALUE.MAX_INPUT_HEIGHT { MODELPARAM_VALUE.MAX_INPUT_HEIGHT PARAM_VALUE.MAX_INPUT_HEIGHT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAX_INPUT_HEIGHT}] ${MODELPARAM_VALUE.MAX_INPUT_HEIGHT}
}

proc update_MODELPARAM_VALUE.OUTPUT_WIDTH { MODELPARAM_VALUE.OUTPUT_WIDTH PARAM_VALUE.OUTPUT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.OUTPUT_WIDTH}] ${MODELPARAM_VALUE.OUTPUT_WIDTH}
}

proc update_MODELPARAM_VALUE.OUTPUT_HEIGHT { MODELPARAM_VALUE.OUTPUT_HEIGHT PARAM_VALUE.OUTPUT_HEIGHT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.OUTPUT_HEIGHT}] ${MODELPARAM_VALUE.OUTPUT_HEIGHT}
}

proc update_MODELPARAM_VALUE.BRAM_ADDR_WIDTH { MODELPARAM_VALUE.BRAM_ADDR_WIDTH PARAM_VALUE.BRAM_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BRAM_ADDR_WIDTH}] ${MODELPARAM_VALUE.BRAM_ADDR_WIDTH}
}

proc update_MODELPARAM_VALUE.AXI_ADDR_WIDTH { MODELPARAM_VALUE.AXI_ADDR_WIDTH PARAM_VALUE.AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.AXI_ADDR_WIDTH}
}
