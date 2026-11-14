# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "AXI_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BRAM_ADDR_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ENABLE_BRAM_SOURCE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ENABLE_HLS_SOURCE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ENABLE_SCALER" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ENABLE_VDMA_SOURCE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FIXED_FORMAT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FIXED_SOURCE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "FORMAT_SELECT_MODE" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_INPUT_HEIGHT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_INPUT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_SCALER_INPUT_HEIGHT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "MAX_SCALER_INPUT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "OUTPUT_HEIGHT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "OUTPUT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "SOURCE_SELECT_MODE" -parent ${Page_0}


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

proc update_PARAM_VALUE.ENABLE_BRAM_SOURCE { PARAM_VALUE.ENABLE_BRAM_SOURCE } {
	# Procedure called to update ENABLE_BRAM_SOURCE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ENABLE_BRAM_SOURCE { PARAM_VALUE.ENABLE_BRAM_SOURCE } {
	# Procedure called to validate ENABLE_BRAM_SOURCE
	return true
}

proc update_PARAM_VALUE.ENABLE_HLS_SOURCE { PARAM_VALUE.ENABLE_HLS_SOURCE } {
	# Procedure called to update ENABLE_HLS_SOURCE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ENABLE_HLS_SOURCE { PARAM_VALUE.ENABLE_HLS_SOURCE } {
	# Procedure called to validate ENABLE_HLS_SOURCE
	return true
}

proc update_PARAM_VALUE.ENABLE_SCALER { PARAM_VALUE.ENABLE_SCALER } {
	# Procedure called to update ENABLE_SCALER when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ENABLE_SCALER { PARAM_VALUE.ENABLE_SCALER } {
	# Procedure called to validate ENABLE_SCALER
	return true
}

proc update_PARAM_VALUE.ENABLE_VDMA_SOURCE { PARAM_VALUE.ENABLE_VDMA_SOURCE } {
	# Procedure called to update ENABLE_VDMA_SOURCE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ENABLE_VDMA_SOURCE { PARAM_VALUE.ENABLE_VDMA_SOURCE } {
	# Procedure called to validate ENABLE_VDMA_SOURCE
	return true
}

proc update_PARAM_VALUE.FIXED_FORMAT { PARAM_VALUE.FIXED_FORMAT } {
	# Procedure called to update FIXED_FORMAT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FIXED_FORMAT { PARAM_VALUE.FIXED_FORMAT } {
	# Procedure called to validate FIXED_FORMAT
	return true
}

proc update_PARAM_VALUE.FIXED_SOURCE { PARAM_VALUE.FIXED_SOURCE } {
	# Procedure called to update FIXED_SOURCE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FIXED_SOURCE { PARAM_VALUE.FIXED_SOURCE } {
	# Procedure called to validate FIXED_SOURCE
	return true
}

proc update_PARAM_VALUE.FORMAT_SELECT_MODE { PARAM_VALUE.FORMAT_SELECT_MODE } {
	# Procedure called to update FORMAT_SELECT_MODE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.FORMAT_SELECT_MODE { PARAM_VALUE.FORMAT_SELECT_MODE } {
	# Procedure called to validate FORMAT_SELECT_MODE
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

proc update_PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT { PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT } {
	# Procedure called to update MAX_SCALER_INPUT_HEIGHT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT { PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT } {
	# Procedure called to validate MAX_SCALER_INPUT_HEIGHT
	return true
}

proc update_PARAM_VALUE.MAX_SCALER_INPUT_WIDTH { PARAM_VALUE.MAX_SCALER_INPUT_WIDTH } {
	# Procedure called to update MAX_SCALER_INPUT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.MAX_SCALER_INPUT_WIDTH { PARAM_VALUE.MAX_SCALER_INPUT_WIDTH } {
	# Procedure called to validate MAX_SCALER_INPUT_WIDTH
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

proc update_PARAM_VALUE.SOURCE_SELECT_MODE { PARAM_VALUE.SOURCE_SELECT_MODE } {
	# Procedure called to update SOURCE_SELECT_MODE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.SOURCE_SELECT_MODE { PARAM_VALUE.SOURCE_SELECT_MODE } {
	# Procedure called to validate SOURCE_SELECT_MODE
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

proc update_MODELPARAM_VALUE.ENABLE_BRAM_SOURCE { MODELPARAM_VALUE.ENABLE_BRAM_SOURCE PARAM_VALUE.ENABLE_BRAM_SOURCE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ENABLE_BRAM_SOURCE}] ${MODELPARAM_VALUE.ENABLE_BRAM_SOURCE}
}

proc update_MODELPARAM_VALUE.ENABLE_HLS_SOURCE { MODELPARAM_VALUE.ENABLE_HLS_SOURCE PARAM_VALUE.ENABLE_HLS_SOURCE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ENABLE_HLS_SOURCE}] ${MODELPARAM_VALUE.ENABLE_HLS_SOURCE}
}

proc update_MODELPARAM_VALUE.ENABLE_VDMA_SOURCE { MODELPARAM_VALUE.ENABLE_VDMA_SOURCE PARAM_VALUE.ENABLE_VDMA_SOURCE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ENABLE_VDMA_SOURCE}] ${MODELPARAM_VALUE.ENABLE_VDMA_SOURCE}
}

proc update_MODELPARAM_VALUE.SOURCE_SELECT_MODE { MODELPARAM_VALUE.SOURCE_SELECT_MODE PARAM_VALUE.SOURCE_SELECT_MODE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.SOURCE_SELECT_MODE}] ${MODELPARAM_VALUE.SOURCE_SELECT_MODE}
}

proc update_MODELPARAM_VALUE.FIXED_SOURCE { MODELPARAM_VALUE.FIXED_SOURCE PARAM_VALUE.FIXED_SOURCE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FIXED_SOURCE}] ${MODELPARAM_VALUE.FIXED_SOURCE}
}

proc update_MODELPARAM_VALUE.FORMAT_SELECT_MODE { MODELPARAM_VALUE.FORMAT_SELECT_MODE PARAM_VALUE.FORMAT_SELECT_MODE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FORMAT_SELECT_MODE}] ${MODELPARAM_VALUE.FORMAT_SELECT_MODE}
}

proc update_MODELPARAM_VALUE.FIXED_FORMAT { MODELPARAM_VALUE.FIXED_FORMAT PARAM_VALUE.FIXED_FORMAT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.FIXED_FORMAT}] ${MODELPARAM_VALUE.FIXED_FORMAT}
}

proc update_MODELPARAM_VALUE.MAX_SCALER_INPUT_WIDTH { MODELPARAM_VALUE.MAX_SCALER_INPUT_WIDTH PARAM_VALUE.MAX_SCALER_INPUT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAX_SCALER_INPUT_WIDTH}] ${MODELPARAM_VALUE.MAX_SCALER_INPUT_WIDTH}
}

proc update_MODELPARAM_VALUE.MAX_SCALER_INPUT_HEIGHT { MODELPARAM_VALUE.MAX_SCALER_INPUT_HEIGHT PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT}] ${MODELPARAM_VALUE.MAX_SCALER_INPUT_HEIGHT}
}

proc update_MODELPARAM_VALUE.ENABLE_SCALER { MODELPARAM_VALUE.ENABLE_SCALER PARAM_VALUE.ENABLE_SCALER } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ENABLE_SCALER}] ${MODELPARAM_VALUE.ENABLE_SCALER}
}


proc update_PARAM_VALUE.MAX_SCALER_INPUT_WIDTH { PARAM_VALUE.MAX_SCALER_INPUT_WIDTH PARAM_VALUE.MAX_INPUT_WIDTH } {
  set_property value [get_property value ${PARAM_VALUE.MAX_INPUT_WIDTH}] ${PARAM_VALUE.MAX_SCALER_INPUT_WIDTH}
}
proc update_PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT { PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT PARAM_VALUE.MAX_INPUT_HEIGHT } {
  set_property value [get_property value ${PARAM_VALUE.MAX_INPUT_HEIGHT}] ${PARAM_VALUE.MAX_SCALER_INPUT_HEIGHT}
}
