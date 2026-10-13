# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

## buck_fpga_validation_phaseC.xdc
## Constraints para buck_fpga_validation_phaseC_top (Spartan-7
## xc7s50ftgb196-1, Platform Board OHSIM).
##
## IMPORTANTE: este archivo contiene SOLO constraints fisicos (pines,
## clock). NO tiene comandos de debug core (create_debug_core, etc.) --
## esos los agrega scripts/insert_ila.tcl DESPUES de la sintesis, y
## quedan volcados en el .xdc dentro de vivado_project/ al correr
## save_constraints (paso que ya hace el propio script). Si al abrir el
## proyecto generado ves esas lineas en el .xdc de adentro del proyecto,
## es esperado -- no las copies de vuelta a este archivo fuente, se
## regeneran solas cada vez que se corre insert_ila.tcl.

## ---------------------------------------------------------------------
## Clock del sistema: 30 MHz, 50% duty cycle
## ---------------------------------------------------------------------
set_property -dict {PACKAGE_PIN G4 IOSTANDARD LVCMOS33} [get_ports sys_clk]
create_clock -period 33.333 -name sys_clk_pin [get_ports sys_clk]

## ---------------------------------------------------------------------
## Tension del banco de configuracion 0 (DRC CFGBVS-1). Sin esto Vivado
## no puede determinar el soporte de I/O del banco 0 -- la placa usa
## 3.3V, VCCO como referencia (LVCMOS33 en todos los pines de este XDC).
## ---------------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## ---------------------------------------------------------------------
## Entrada PWM
## ---------------------------------------------------------------------
set_property -dict {PACKAGE_PIN A2 IOSTANDARD LVCMOS33} [get_ports pwm_in]
set_false_path -from [get_ports pwm_in]

## ---------------------------------------------------------------------
## LEDs de estado
## ---------------------------------------------------------------------
set_property -dict {PACKAGE_PIN P12 IOSTANDARD LVCMOS33} [get_ports model_running_led]
set_property -dict {PACKAGE_PIN P13 IOSTANDARD LVCMOS33} [get_ports comm_led]

## ---------------------------------------------------------------------
## DAC0 (AD5328 U5)
## ---------------------------------------------------------------------
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS33} [get_ports dac0_din]
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports dac0_ldac]
set_property -dict {PACKAGE_PIN E13 IOSTANDARD LVCMOS33} [get_ports dac0_sync]
set_property -dict {PACKAGE_PIN D14 IOSTANDARD LVCMOS33} [get_ports dac0_sclk]

## ---------------------------------------------------------------------
## DAC1 (AD5328 U13)
## ---------------------------------------------------------------------
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33} [get_ports dac1_din]
set_property -dict {PACKAGE_PIN L14 IOSTANDARD LVCMOS33} [get_ports dac1_ldac]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports dac1_sync]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33} [get_ports dac1_sclk]

## ---------------------------------------------------------------------
## DIO 0-2: PWM/Vsw/Vx, salidas
## ---------------------------------------------------------------------
set_property -dict {PACKAGE_PIN L1 IOSTANDARD LVCMOS33} [get_ports dio_pwm_sync]
set_property -dict {PACKAGE_PIN L2 IOSTANDARD LVCMOS33} [get_ports dio_vsw]
set_property -dict {PACKAGE_PIN M1 IOSTANDARD LVCMOS33} [get_ports dio_vx]

## ---------------------------------------------------------------------
## Disparo del ensayo + seleccion de R (codigo Gray): DOS opciones de
## cableado, mutuamente excluyentes -- dejar UNA activa y la otra
## comentada segun cómo esté armado el banco en cada momento. Cambiar de
## opcion es edicion de este archivo nada mas, no toca el top ni el
## testbench (los 3 puertos logicos -- dio_trigger_in, dio_rsel_b0_in,
## dio_rsel_b1_in -- son los mismos en las dos opciones, el XDC es
## exactamente la capa que abstrae a qué pin fisico apuntan).
## ---------------------------------------------------------------------

## --- OPCION A (comentada): jumpers manuales a GND por el conector J2 ---
## Pines DIO del conector J2 (M2/N1/P2). Pull-UP: el conector J2 solo
## expone GND hacia afuera, asi que un jumper pasivo solo puede forzar un
## 0 -- con pull-up el reposo ya es 1 y el jumper es lo que efectivamente
## controla el pin (el disparo es "conectar y SACAR" el jumper).
# set_property -dict {PACKAGE_PIN M2 IOSTANDARD LVCMOS33} [get_ports dio_trigger_in]
# set_property -dict {PACKAGE_PIN N1 IOSTANDARD LVCMOS33} [get_ports dio_rsel_b0_in]
# set_property -dict {PACKAGE_PIN P2 IOSTANDARD LVCMOS33} [get_ports dio_rsel_b1_in]
# set_property PULLTYPE PULLUP [get_ports dio_trigger_in]
# set_property PULLTYPE PULLUP [get_ports dio_rsel_b0_in]
# set_property PULLTYPE PULLUP [get_ports dio_rsel_b1_in]

## --- OPCION B (ACTIVA): controlado por la Launchpad F28379D, por
## pines YA cableados a ella (PWM2A/PWM2B/PWM3A -- sobran, solo PWM1A se
## usa como pwm_in) -- evita el cable suelto de la Opcion A. Pull-DOWN,
## no pull-up: FPGA y Launchpad tienen fuentes independientes, comparten
## solo GND -- con pull-up, un GPIO de la Launchpad sin inicializar (o
## la placa apagada) recibiria 3.3V del propio riel de la FPGA por esa
## linea, "retroalimentando" un dominio de alimentacion ajeno. Pull-down
## solo referencia GND, que las dos placas comparten siempre, esten o no
## alimentadas -- no hay ruta para que una empuje corriente al riel de
## la otra. Con esto el reposo pasa a ser 0 (no 1): la Launchpad
## simplemente mantiene el pin en 0 y pulsa a 1, sin la vuelta de
## "conectar y soltar" que hacia falta con el jumper pasivo de la Opcion A.
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports dio_trigger_in]  ; # PWM2A
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports dio_rsel_b0_in]  ; # PWM2B
set_property -dict {PACKAGE_PIN B5 IOSTANDARD LVCMOS33} [get_ports dio_rsel_b1_in]  ; # PWM3A
set_property PULLTYPE PULLDOWN [get_ports dio_trigger_in]
set_property PULLTYPE PULLDOWN [get_ports dio_rsel_b0_in]
set_property PULLTYPE PULLDOWN [get_ports dio_rsel_b1_in]

## Comun a las dos opciones: asincronos respecto de sys_clk (van directo
## a sync_2ff.v adentro del top), false_path desde el pin de entrada por
## el mismo motivo que pwm_in.
set_false_path -from [get_ports dio_trigger_in]
set_false_path -from [get_ports dio_rsel_b0_in]
set_false_path -from [get_ports dio_rsel_b1_in]
