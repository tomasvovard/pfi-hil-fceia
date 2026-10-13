# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#############################################################################
# arm_ila_trigger.tcl
#
# Configura la condicion de disparo del ILA (flanco de subida de
# dbg_trigger, ver LaunchPad GPIO2 / FPGA A4) y arma la captura.
#
# A diferencia de insert_ila.tcl (que corre UNA VEZ, antes de generar el
# bitstream, y hornea que probes existen), esto corre CADA VEZ que se
# quiere armar una captura nueva, DESPUES de programar la FPGA, en la
# consola Tcl de Hardware Manager (Window > Tcl Console). La condicion de
# trigger no queda grabada en el bitstream -- hay que rearmarla despues
# de cada power-cycle o reprogramacion. Este script solo arma la captura:
# no espera, no sube los datos y no abre automaticamente la forma de onda.
#
# Requisito: ya tenes que tener el Hardware Manager conectado al target y
# el hw_ila reconocido (equivalente a haber hecho This te lo hace
# automaticamente el propio Hardware Manager al conectar despues de
# programar; si estas corriendo esto desde cero sin la GUI, descomenta
# las 4 lineas de conexion de aca abajo).
#############################################################################

# open_hw_manager
# connect_hw_server
# open_hw_target
# set_property PROGRAM.FILE {ruta/al/bitstream.bit} [lindex [get_hw_devices] 0]
# program_hw_devices [lindex [get_hw_devices] 0]

refresh_hw_device [lindex [get_hw_devices] 0]

set hw_ila [get_hw_ilas -quiet]
if {[llength $hw_ila] != 1} {
    error "No se encontro un unico hw_ila (encontrados: [llength $hw_ila]). Revisa que el bitstream con el ILA este programado y el device refrescado."
}

set probe_trigger [get_hw_probes -quiet -of_objects $hw_ila -filter {NAME =~ "*dbg_trigger*"}]
if {[llength $probe_trigger] != 1} {
    error "No se encontro el probe dbg_trigger de forma unica (encontrados: [llength $probe_trigger])."
}

# Disparo sobre flanco de subida: comparar contra 1 con capacidad de
# trigger "R" (rising edge), no un simple "igual a 1" (que tambien
# dispararia si la señal arranca en 1 y nunca hay un flanco real).
set_property TRIGGER_COMPARE_VALUE eq1'bR $probe_trigger

run_hw_ila $hw_ila

puts ""
puts "============================================================"
puts " ILA ARMADO: disparo sobre flanco de subida de dbg_trigger"
puts " (LaunchPad GPIO2, FPGA PACKAGE_PIN A4)"
puts ""
puts " Pulsar/generar el flanco externo ahora. Para ver el estado:"
puts {   get_property STATUS.CORE_STATUS [get_hw_ilas]}
puts " FULL significa que la captura ya esta completa. Para subirla:"
# Usar llaves evita que Tcl ejecute los corchetes mientras arma el mensaje.
puts {   set ila_data [upload_hw_ila_data [lindex [get_hw_ilas] 0]]}
puts {   display_hw_ila_data $ila_data}
puts "============================================================"
puts ""
