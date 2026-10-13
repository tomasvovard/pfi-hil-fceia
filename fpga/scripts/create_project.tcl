# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#############################################################################
# create_project.tcl
# Crea el proyecto de Vivado en vivado_project/ con las fuentes, las
# restricciones y los bancos de prueba. Las rutas se pasan como listas
# Tcl para admitir espacios.
#############################################################################

set PROJ_NAME   "buck_fpga_validation_phaseC"
set PART        "xc7s50ftgb196-1"

set ROOT_DIR [file normalize [file dirname [info script]]/..]
set PROJ_DIR  "$ROOT_DIR/vivado_project"

create_project $PROJ_NAME $PROJ_DIR -part $PART -force

# RTL. Orden: nucleo, modulos de sincronizacion,
# wrapper del modelo, DAC, top.
add_files -norecurse [list \
    "$ROOT_DIR/rtl/buck_params.vh" \
    "$ROOT_DIR/rtl/buck_v1_0.v" \
    "$ROOT_DIR/rtl/pwm_sync.v" \
    "$ROOT_DIR/rtl/sync_2ff.v" \
    "$ROOT_DIR/rtl/edge_detect.v" \
    "$ROOT_DIR/rtl/r_select_gray.v" \
    "$ROOT_DIR/rtl/model_ce_gen.v" \
    "$ROOT_DIR/rtl/buck_model.v" \
    "$ROOT_DIR/rtl/status_leds.v" \
    "$ROOT_DIR/rtl/ad5328_driver.v" \
    "$ROOT_DIR/rtl/dac_scaler.v" \
    "$ROOT_DIR/rtl/dac_scheduler.v" \
    "$ROOT_DIR/rtl/buck_fpga_validation_phaseC_top.v" \
]
set_property file_type {Verilog Header} [get_files buck_params.vh]
set_property is_global_include true [get_files buck_params.vh]
set_property top buck_fpga_validation_phaseC_top [current_fileset]

# Constraints. El ILA agrega comandos al XDC mediante save_constraints; por eso
# el proyecto usa una copia generada y nunca el archivo fuente versionado.
set PROJECT_XDC "$PROJ_DIR/buck_fpga_validation_phaseC.xdc"
file copy -force "$ROOT_DIR/constraints/buck_fpga_validation_phaseC.xdc" $PROJECT_XDC
add_files -fileset constrs_1 -norecurse [list $PROJECT_XDC]

# Simulation
add_files -fileset sim_1 -norecurse [list \
    "$ROOT_DIR/tb/buck_variable_l_tb.sv" \
    "$ROOT_DIR/tb/dac_offset_tb.sv" \
    "$ROOT_DIR/tb/dac_scaler_tb.sv" \
    "$ROOT_DIR/tb/ad5328_driver_param_tb.sv" \
    "$ROOT_DIR/tb/r_select_gray_tb.sv" \
    "$ROOT_DIR/tb/buck_zero_hold_tb.sv" \
    "$ROOT_DIR/tb/buck_fpga_validation_phaseC_tb.sv" \
]
set_property top buck_fpga_validation_phaseC_tb [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property SOURCE_SET sources_1 [get_filesets sim_1]

# Memory reference files. Add using [list ...] so paths containing spaces
# are never parsed as multiple arguments.
foreach memfile [glob -nocomplain -directory "$ROOT_DIR/tb" *.mem] {
    add_files -fileset sim_1 -norecurse [list "$memfile"]
}

set mem_objs [get_files -of_objects [get_filesets sim_1] -filter {FILE_TYPE =~ "*Memory*" || NAME =~ "*.mem"}]
if {[llength $mem_objs] > 0} {
    set_property file_type "Memory Initialization Files" $mem_objs
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "============================================================"
puts " Proyecto creado"
puts " Root: $ROOT_DIR"
puts " Top sintesis: buck_fpga_validation_phaseC_top"
puts " Top sim:      buck_fpga_validation_phaseC_tb"
puts " MEM agregados: [llength $mem_objs]"
puts "============================================================"
puts ""
