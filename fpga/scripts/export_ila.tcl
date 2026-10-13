# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#############################################################################
# export_ila.tcl
#
# Exporta a CSV una captura del ILA de buck_fpga_validation_phaseC_top,
# ya programado en la FPGA y con el cable JTAG conectado.
#
# Dos formas de disparar la captura:
#   (a) Automatico sobre el flanco de DIO_3 (recomendado para ensayos):
#       correr scripts/arm_ila_trigger.tcl en vez de este bloque de
#       "Disparo manual" de aca abajo -- ese script arma la condicion de
#       trigger y llama run_hw_ila. No espera ni sube datos. Despues de
#       que STATUS.CORE_STATUS sea FULL, segui desde "set ila_data...".
#   (b) Manual (equivalente al boton "Run Trigger" en la GUI, sin
#       condicion de trigger real -- dispara apenas se lo pide, util
#       para debug rapido sin esperar el estimulo externo): es lo que
#       hace este script de punta a punta, tal cual.
#
# Uso tipico (disparo manual, desde la consola Tcl de Vivado, con
# Hardware Manager accesible):
#   source scripts/export_ila.tcl
#############################################################################

open_hw_manager
connect_hw_server
open_hw_target

# Ajustar el nombre del device segun lo que reporte:
#   puts [get_hw_devices]
set HW_DEVICE [lindex [get_hw_devices] 0]
current_hw_device $HW_DEVICE
refresh_hw_device -update_hw_probes false $HW_DEVICE

set ila_core [get_hw_ilas -of_objects $HW_DEVICE]
if {[llength $ila_core] == 0} {
    error "No se encontro ningun core de ILA en el device. Verificar que\
           el bitstream+probes (.ltx) se hayan programado correctamente."
}

# Disparo manual (sin condicion real, dispara apenas se lo pide). Para
# disparo automatico sobre el estimulo del ensayo, usar
# scripts/arm_ila_trigger.tcl en su lugar y saltar estas dos lineas.
run_hw_ila $ila_core
puts "Esperando disparo del ILA..."
wait_on_hw_ila $ila_core

set ila_data [upload_hw_ila_data $ila_core]

set OUT_CSV "buck_ila_capture.csv"
write_hw_ila_data -csv_file $OUT_CSV -force $ila_data

puts "Captura exportada a $OUT_CSV"
puts ""
puts "Columnas (iC/iO no se capturan; se reconstruyen como"
puts "iO=Vo/R, iC=iL-iO):"
puts "  sample_counter[31:0], dbg_pwm_sync, dbg_model_ce,"
puts "  dbg_iL[31:0], dbg_Vo[31:0], dbg_trigger, dbg_rsel[1:0],"
puts "  dbg_dac0_start, dbg_dac0_busy, dbg_dac0_done"
puts ""
puts "Interpretacion en MATLAB de iL/Vo (signed Q32.22):"
puts "  1. Importar el CSV (el encabezado que exporta Vivado incluye el"
puts "     nombre de cada probe, p.ej. 'dbg_iL[31:0]')."
puts "  2. Cada valor ya viene interpretado como entero. Si Vivado lo"
puts "     exporta sin signo, convertir a signed de 32 bits primero:"
puts "       raw = readmatrix('buck_ila_capture.csv');"
puts "       code = int32(raw);  % reinterpreta como signed de 32 bits"
puts "  3. Pasar a unidades fisicas dividiendo por 2^22:"
puts "       iL_A = double(code) / 2^22;"
puts "  4. sample_counter (32 bits, sin signo) sirve como indice de"
puts "     muestra; multiplicado por Ts=0.2 us da el eje de tiempo:"
puts "       t_s = double(sample_counter_col) * 0.2e-6;"
puts "  5. dbg_rsel[1:0] es el codigo Gray de R activo en cada muestra"
puts "     (00=16.6ohm, 01=25ohm, 11=50ohm, 10=no deberia aparecer salvo"
puts "     un instante de desalineacion entre los dos GPIO externos)."
