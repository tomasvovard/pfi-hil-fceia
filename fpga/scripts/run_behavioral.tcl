# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#############################################################################
# Ejecuta el testbench de integracion desde un proyecto recien creado.
#############################################################################
set ROOT_DIR [file normalize [file dirname [info script]]/..]
set XPR "$ROOT_DIR/vivado_project/buck_fpga_validation_phaseC.xpr"
open_project $XPR
if {[llength $argv] > 0} {
    set SIM_TOP [lindex $argv 0]
} else {
    set SIM_TOP buck_fpga_validation_phaseC_tb
}
puts "Ejecutando testbench: $SIM_TOP"
set_property top $SIM_TOP [get_filesets sim_1]
set_property xsim.simulate.runtime {all} [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
close_sim -force
close_project
exit
