# FPGA: modelo del convertidor buck en tiempo real

Diseño para la FPGA Spartan-7 XC7S50 de OHSIM que ejecuta en tiempo real el modelo no ideal de un convertidor buck y presenta sus variables por los DAC de la placa. El modelo integra con Forward-Euler en punto fijo Q32.22 (32 bits con 22 fraccionarios) cada 200 ns (5 MHz, un paso cada seis ciclos del reloj de sistema de 30 MHz) e incluye las caídas del interruptor y del diodo, la resistencia serie y una inductancia dependiente de la corriente. El ciclo de trabajo llega como señal PWM desde la LaunchPad, que además dispara el ensayo y selecciona la carga en caliente.

## Contenido

```
rtl/          fuentes del diseño (buck_params.vh se genera desde MATLAB)
tb/           siete bancos de prueba y vectores de referencia (.mem)
constraints/  restricciones físicas (pines y reloj)
scripts/      creación del proyecto, simulación, compilación e ILA
```

| Módulo | Función |
|---|---|
| `buck_fpga_validation_phaseC_top.v` | Top: reset, sincronizadores, modelo, escalado y los dos DAC |
| `buck_model.v`, `buck_v1_0.v` | Modelo del buck: inductancia L(i) y núcleo numérico con pérdidas |
| `buck_params.vh` | Coeficientes Q32.22 del modelo y compensación de offset de Vo (generado) |
| `model_ce_gen.v` | Habilitación del modelo a 5 MHz |
| `pwm_sync.v`, `sync_2ff.v`, `edge_detect.v` | Sincronización de PWM, disparo y selección de carga |
| `r_select_gray.v` | Selección de la carga (16,6, 25 o 50 Ω) en código Gray |
| `dac_scaler.v`, `dac_scheduler.v`, `ad5328_driver.v` | Escalado a 12 bits, toma coherente de muestras y driver SPI del AD5328 |
| `status_leds.v` | LED de modelo en marcha y LED de actividad de PWM |

El proyecto de Vivado no se guarda en el repositorio: `scripts/create_project.tcl` lo recrea en `vivado_project/` cada vez que se lo necesita.

## Herramientas

- Vivado 2025.2 (dispositivo `xc7s50ftgb196-1`).
- Python 3, sin bibliotecas adicionales, para regenerar los vectores de referencia.
- Programador JTAG (se usó un Digilent JTAG-HS3) para programar la FPGA y descargar el ILA.

## Archivo de configuración utilizado en los ensayos

El archivo de configuración (`.bit`), el de sondas del ILA (`.ltx`), el `buck_params.vh` con que se generaron, los informes de temporización, utilización y reglas de diseño y sus sumas SHA-256 están publicados como *release* del repositorio (`candidate-2026-09-11`). Para usar OHSIM sin recompilar alcanza con descargar esos archivos y programarlos (ver [Programación y captura con el ILA](#programación-y-captura-con-el-ila)). Antes de programar, comprobar las sumas:

```
sha256sum -c SHA256SUMS.txt
```

## Simulación de los bancos de prueba

Desde la carpeta `fpga/`, con Vivado en modo batch:

```
vivado -mode batch -source scripts/validate_all.tcl
```

El script recrea el proyecto y corre los siete bancos de prueba (`buck_variable_l_tb`, `dac_offset_tb`, `dac_scaler_tb`, `buck_zero_hold_tb`, `r_select_gray_tb`, `ad5328_driver_param_tb` y `buck_fpga_validation_phaseC_tb`). Se detiene con un error si alguno no informa `PASS`.

Como alternativa, `scripts/simular_bancos_xsim.sh` compila y simula los mismos bancos llamando directamente a `xvlog` y `xelab`, sin crear el proyecto (útil desde Git Bash en Windows o en Linux):

```
VIVADO=/c/AMDDesignTools/2025.2/Vivado bash scripts/simular_bancos_xsim.sh
```

**Resultado esperado:** `PASS` en los siete bancos. El banco de integración termina con `Errores totales detectados: 0` y `RESULTADO GLOBAL: PASS`, después de comparar bit a bit 750 muestras de arranque en frío contra los vectores de referencia.

## Compilación

```
vivado -mode batch -source scripts/build_bitstream.tcl
```

Si `vivado_project/` no existe, crearlo antes con `vivado -mode batch -source scripts/create_project.tcl`. El script sintetiza el diseño, inserta el ILA (`scripts/insert_ila.tcl`), lo implementa y genera el archivo de configuración, el de sondas y los informes en `reports/`.

**Resultado esperado:** márgenes de setup y de hold positivos en el informe de temporización (en la compilación de los ensayos, WNS = +6,479 ns y WHS = +0,034 ns) y ningún error de DRC. El diseño usa 32 de los 120 bloques DSP48E1 del dispositivo.

## Cambio de parámetros del modelo

Los coeficientes no se escriben a mano. Ante un cambio de parámetros:

1. Modificar `matlab/cfg/buck_params.m` y comprobar con `p3_simular_modelo.m` que el modelo de referencia reproduce el comportamiento buscado (ver [`matlab/`](../matlab/)).
2. Ejecutar `matlab/modelado_rtl/r3_parametros_verilog.m`, que escribe `matlab/modelado_rtl/output/buck_params.vh`, y copiarlo a `fpga/rtl/buck_params.vh`.
3. Ejecutar `python scripts/generate_reference.py`, que recalcula con aritmética entera los vectores de referencia de los bancos de prueba a partir del nuevo encabezado.
4. Simular los bancos de prueba y compilar.

Un cambio en las escalas del DAC o en la compensación de la salida exige además actualizar las escalas del procesamiento en `matlab/cfg/medicion_cfg.m`.

## Salidas analógicas

| DAC | Canal | Punto de prueba | Señal | Rango |
|---|---|---|---|---|
| DAC0 (U5) | C | TP-A02 | i<sub>L</sub> | 0 a 2,5 A → 0 a 3 V |
| DAC0 (U5) | D | TP-A03 | v<sub>o</sub> | 0 a 40 V → 0 a 3 V |
| DAC1 (U13) | A a F | | V<sub>i</sub>, v<sub>L</sub>, i<sub>o</sub>, i<sub>i</sub>, i<sub>C</sub>, v<sub>C</sub> | ver `dac_scaler.v` |

DAC0 envía solo dos canales: cada actualización dura 75 ciclos del reloj de sistema (2,50 µs) y el planificador agrega dos antes de la siguiente, de modo que el período efectivo es de 77 ciclos (2,57 µs, 39 actualizaciones por período de conmutación). DAC1 envía seis canales en 222 ciclos, con un período efectivo de 224 ciclos (7,47 µs), con un driver independiente que no reduce la tasa de DAC0. Para cambiar qué señal va a cada canal o cuántos canales envía cada driver, modificar las conexiones `code_chN` de `u_dac_scheduler_0/1` y los parámetros `FIRST_CHANNEL` y `N_CHANNELS` de `u_dac0_driver/u_dac1_driver` en el top. Una señal asignada a un canal fuera de ese rango deja de transmitirse.

## Conexión con la LaunchPad

| Señal | Pin de la FPGA | LaunchPad | Función |
|---|---|---|---|
| `pwm_in` | A2 (PWM1A) | ePWM | Comando de conmutación del modelo |
| `dio_trigger_in` | A4 (PWM2A) | GPIO2 (J4_8) | Pulso de disparo del ensayo y del ILA |
| `dio_rsel_b0_in` | A5 (PWM2B) | GPIO3 (J4_7) | Selección de carga, bit 0 |
| `dio_rsel_b1_in` | B5 (PWM3A) | GPIO4 (J4_6) | Selección de carga, bit 1 |

Los tres pines de entrada tienen pull-down interno, de modo que quedan en nivel bajo mientras la LaunchPad no los maneje. La carga activa según `{b1, b0}` es `00` = 16,6 Ω, `01` = 25 Ω y `11` = 50 Ω; el código `10` no se usa y retiene el último valor válido. El archivo de restricciones incluye comentada una alternativa con puentes manuales a GND en el conector J2 (pines M2, N1 y P2, con pull-up).

## Programación y captura con el ILA

1. Conectar el programador JTAG a la plataforma alimentada y abrir el Hardware Manager de Vivado.
2. Programar la FPGA con el archivo de configuración y el de sondas **de una misma compilación**. Si provienen de compilaciones distintas, el ILA puede presentar las señales con nombres o anchos equivocados sin advertirlo.
3. Para conservar la configuración después de apagar la placa, generar desde el mismo `.bit` una imagen para la memoria flash de configuración y grabarla desde el Hardware Manager.
4. Antes de cada ensayo, ejecutar en la consola Tcl del Hardware Manager `source scripts/arm_ila_trigger.tcl`, que arma el disparo en el flanco ascendente del pulso de la LaunchPad.
5. Después del ensayo, comprobar que `get_property STATUS.CORE_STATUS [get_hw_ilas]` devuelva `FULL` y exportar la captura (16.384 muestras a 30 MHz, unos 546 µs) con:

```tcl
set ila_data [upload_hw_ila_data [lindex [get_hw_ilas] 0]]
write_hw_ila_data -csv_file E1a_ILA.csv -force $ila_data
```

`scripts/export_ila.tcl` hace lo mismo con un disparo manual inmediato, útil para comprobar el ILA sin esperar el estímulo. Las sondas son `sample_counter`, `dbg_pwm_sync`, `dbg_model_ce`, `dbg_iL` y `dbg_Vo` (Q32.22 con signo; valor físico = código / 2<sup>22</sup>), `dbg_trigger`, `dbg_rsel` y el estado del driver de DAC0. i<sub>o</sub> e i<sub>C</sub> no se capturan y se reconstruyen como i<sub>o</sub> = v<sub>o</sub>/R e i<sub>C</sub> = i<sub>L</sub> − i<sub>o</sub>.

## Problemas conocidos

- El `.xdc` del proyecto generado contiene comandos `create_debug_core` que no están en `constraints/`: los agrega `insert_ila.tcl` en una copia, y no deben copiarse al archivo fuente.
- Si `implement_debug_core` informa "Spawn failed" en Windows, comprobar con `get_debug_cores` que el núcleo se haya creado; en las compilaciones de este trabajo el mensaje no correspondió a una falla real.
- La simulación lanzada desde Vivado puede fallar en entornos que no permiten ejecutar los `.bat` de XSim; en ese caso usar `scripts/simular_bancos_xsim.sh`.
