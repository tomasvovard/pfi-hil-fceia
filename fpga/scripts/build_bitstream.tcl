# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#############################################################################
# Sintesis, insercion ILA, implementacion, bitstream y reportes reproducibles.
#############################################################################
set ROOT_DIR [file normalize [file dirname [info script]]/..]
set XPR "$ROOT_DIR/vivado_project/buck_fpga_validation_phaseC.xpr"
set REPORT_DIR "$ROOT_DIR/reports"
file mkdir $REPORT_DIR

open_project $XPR
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] != "synth_design Complete!"} {
    error "Sintesis no termino correctamente: [get_property STATUS [get_runs synth_1]]"
}

source "$ROOT_DIR/scripts/insert_ila.tcl"
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] != "write_bitstream Complete!"} {
    error "Implementacion/bitstream incompleto: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1

report_timing_summary -max_paths 10 -file "$REPORT_DIR/timing_summary.rpt"
report_bus_skew -warn_on_violation -file "$REPORT_DIR/bus_skew.rpt"
report_drc -file "$REPORT_DIR/drc.rpt"
report_utilization -file "$REPORT_DIR/utilization.rpt"
set worst [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
set wns [get_property SLACK $worst]
set hold_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
set whs [get_property SLACK $hold_path]
puts "============================================================"
puts " BUILD FPGA COMPLETO"
puts " WNS: $wns ns"
puts " WHS: $whs ns"
puts " BIT: [get_property DIRECTORY [get_runs impl_1]]/buck_fpga_validation_phaseC_top.bit"
puts " LTX: [get_property DIRECTORY [current_project]]/debug_probes.ltx"
puts "============================================================"
if {$wns < 0} { error "Timing incumplido: WNS=$wns ns" }
if {$whs < 0} { error "Timing hold incumplido: WHS=$whs ns" }
close_project
exit
