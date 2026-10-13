# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

set ROOT_DIR [file normalize [file dirname [info script]]/..]
source "$ROOT_DIR/scripts/create_project.tcl"
foreach sim_top {buck_variable_l_tb dac_offset_tb dac_scaler_tb buck_zero_hold_tb r_select_gray_tb ad5328_driver_param_tb buck_fpga_validation_phaseC_tb} {
    puts "VALIDATING $sim_top"
    set_property top $sim_top [get_filesets sim_1]
    set_property xsim.simulate.runtime all [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    close_sim -force
    set log_path "$ROOT_DIR/vivado_project/buck_fpga_validation_phaseC.sim/sim_1/behav/xsim/simulate.log"
    set fd [open $log_path r]
    set result [read $fd]
    close $fd
    if {![regexp {PASS} $result] || [regexp -nocase {FAIL|FATAL:|ERROR:} $result]} {
        error "Validacion fallida o sin PASS: $sim_top. Revisar $log_path"
    }
}
close_project
exit
