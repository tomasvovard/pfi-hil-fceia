# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#############################################################################
# insert_ila.tcl
# Inserta el ILA sobre el diseno sintetizado (create_debug_core crea
# clk/probe0; save_constraints -force va ANTES de implement_debug_core).
#
#   - iC/iO no se capturan: se reconstruyen como iO=Vo/R, iC=iL-iO.
#   - profundidad 16384 muestras (100 bits de probes).
#   - dbg_trigger queda ademas como probe de TRIGGER real (no solo
#     DATA_AND_TRIGGER declarativo): ver scripts/arm_ila_trigger.tcl para
#     la condicion de disparo en si, que se configura en Hardware
#     Manager, no aca (la condicion de trigger no se hornea en el
#     bitstream, se arma en runtime).
#
# Probes:
#   0  sample_counter[31:0]
#   1  dbg_pwm_sync
#   2  dbg_model_ce
#   3  dbg_iL[31:0]
#   4  dbg_Vo[31:0]
#   5  dbg_trigger
#   6  dbg_rsel[1:0]
#   7  dbg_dac0_start
#   8  dbg_dac0_busy
#   9  dbg_dac0_done
#############################################################################

open_run synth_1 -name synth_1

if {[llength [get_debug_cores -quiet u_ila_0]] > 0} {
    puts "Eliminando u_ila_0 existente/parcial..."
    delete_debug_core [get_debug_cores u_ila_0]
}

set ILA_DEPTH 16384

create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH $ILA_DEPTH [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]

set_property port_width 1 [get_debug_ports u_ila_0/clk]

set ila_clk_net [get_nets -quiet sys_clk_IBUF_BUFG]
if {[llength $ila_clk_net] == 0} {
    set ila_clk_net [get_nets -hier -quiet -filter {NAME =~ *sys_clk*BUFG*}]
}
if {[llength $ila_clk_net] != 1} {
    puts "Candidatos *sys_clk*:"
    puts [get_nets -hier -quiet -filter {NAME =~ *sys_clk*}]
    error "No se pudo identificar de forma univoca el clock del ILA."
}
puts "Clock ILA: $ila_clk_net"
connect_debug_port u_ila_0/clk $ila_clk_net

proc find_scalar_net {leaf} {
    set re [format {(^|.*/)%s$} $leaf]
    set n [get_nets -hier -quiet -regexp $re]
    if {[llength $n] != 1} {
        error "No se encontro de forma unica la red $leaf. Matches: $n"
    }
    return $n
}

proc find_bus_nets {leaf width} {
    set result [list]
    for {set i 0} {$i < $width} {incr i} {
        set re [format {(^|.*/)%s\[%d\]$} $leaf $i]
        set n [get_nets -hier -quiet -regexp $re]
        if {[llength $n] != 1} {
            error "No se encontro de forma unica $leaf\[$i\]. Matches: $n"
        }
        lappend result [lindex $n 0]
    }
    return $result
}

set_property port_width 32 [get_debug_ports u_ila_0/probe0]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [find_bus_nets sample_counter 32]

proc add_scalar_probe {core idx leaf} {
    create_debug_port $core probe
    set p "$core/probe$idx"
    set_property port_width 1 [get_debug_ports $p]
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports $p]
    connect_debug_port $p [find_scalar_net $leaf]
}

proc add_bus_probe {core idx leaf width} {
    create_debug_port $core probe
    set p "$core/probe$idx"
    set_property port_width $width [get_debug_ports $p]
    set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports $p]
    connect_debug_port $p [find_bus_nets $leaf $width]
}

add_scalar_probe u_ila_0 1 dbg_pwm_sync
add_scalar_probe u_ila_0 2 dbg_model_ce
add_bus_probe    u_ila_0 3 dbg_iL 32
add_bus_probe    u_ila_0 4 dbg_Vo 32
add_scalar_probe u_ila_0 5 dbg_trigger
add_bus_probe    u_ila_0 6 dbg_rsel 2
add_scalar_probe u_ila_0 7 dbg_dac0_start
add_scalar_probe u_ila_0 8 dbg_dac0_busy
add_scalar_probe u_ila_0 9 dbg_dac0_done

save_constraints -force

implement_debug_core

set ltx_path [file normalize [get_property DIRECTORY [current_project]]/debug_probes.ltx]
write_debug_probes -force $ltx_path

puts ""
puts "============================================================"
puts " ILA INSERTADO CORRECTAMENTE"
puts " Profundidad: $ILA_DEPTH ([expr {$ILA_DEPTH*1000/30000}] us a 30MHz)"
puts " Clock:       $ila_clk_net"
puts " Probes: 10 (sin iC/iO, con trigger + r_select)"
puts " LTX:         $ltx_path"
puts ""
puts " Para armar el disparo automatico: correr"
puts " scripts/arm_ila_trigger.tcl en la consola Tcl de Hardware Manager"
puts " (Window > Tcl Console), DESPUES de programar el bitstream."
puts "============================================================"
puts ""
