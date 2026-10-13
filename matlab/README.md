# MATLAB: modelo de referencia, coeficientes y procesamiento

Entorno de MATLAB y Simulink con el modelo no ideal del convertidor buck, el generador de los coeficientes de la FPGA y el procesamiento de las capturas. Compara tres fuentes de la misma respuesta: el convertidor multipropósito del laboratorio (**CEuP**), el modelo simulado en Simulink (**Modelo**) y la plataforma en tiempo real (**OHSIM**).

## Contenido

| Archivo | Función |
|---|---|
| `cfg/buck_params.m` | Parámetros físicos y de ajuste del convertidor (V<sub>i</sub>, C, pérdidas, ley L(i<sub>L</sub>)) |
| `cfg/simulacion_cfg.m` | Solver, ventanas de tiempo y tabla de ensayos (ciclos de trabajo y cargas) |
| `cfg/medicion_cfg.m` | Rutas a los datos, pinza de corriente, escalas del DAC de OHSIM y alineación temporal |
| `cfg/colores.m` | Paleta común de las figuras |
| `func/` | Lectura de capturas, alineación, simulación, régimen periódico, métricas y suavizado |
| `buck_no_ideal.slx` | Modelo de Simulink del buck no ideal |
| `p1_inductancia.m` | Identificación de L(i<sub>L</sub>) a partir del ripple de corriente del CEuP |
| `p3_simular_modelo.m` | Barrido estático del modelo frente al cálculo teórico |
| `p4_comparar_fuentes.m` | Niveles de régimen, ripple y offset de cada fuente |
| `p4_2_comparar_fuentes_sin_offset.m` | Respuestas incrementales y métricas por par de fuentes |
| `p6_identificar_ft.m` | Identificación de la función de transferencia de 2.º orden δ → v<sub>o</sub> |
| `modelado_rtl/r3_parametros_verilog.m` | Generación de `buck_params.vh` (coeficientes Q32.22 de la FPGA) |

## Requisitos

- MATLAB R2024b y Simulink 24.2.
- System Identification Toolbox y Control System Toolbox (solo para `p6_identificar_ft.m`).

## Datos

Los scripts leen las capturas de [`../data/`](../data/). El repositorio publica el ensayo **E1a** (escalón de ciclo de trabajo 0,45 → 0,46 con R = 16,6 Ω) del CEuP y de OHSIM. `p4`, `p4_2` y `p6` procesan los ensayos de su lista que tengan capturas e informan cuáles omiten. Para procesar otros ensayos, copiar sus CSV con el nombre del ensayo (`E3a.csv`, etc.) a las carpetas indicadas en `cfg/medicion_cfg.m`.

`p1_inductancia.m` necesita los regímenes de todos los ensayos del CEuP para ajustar la recta 1/L(i<sub>L</sub>). Para los ensayos sin captura usa los puntos de `data/inductancia/puntos_L_ceup.csv`, que se obtuvieron con este mismo script sobre las capturas completas. Con E1a calcula sus dos puntos a partir de la captura y reproduce la recta del modelo.

## Uso

Con la carpeta `matlab/` como carpeta de trabajo de MATLAB:

```matlab
p1_inductancia                      % ley L(iL)
p3_simular_modelo                   % barrido estático del modelo
p4_comparar_fuentes                 % niveles de régimen
p4_2_comparar_fuentes_sin_offset    % respuestas incrementales y métricas
p6_identificar_ft                   % funciones de transferencia
```

Los resultados se escriben en `output/` (un CSV por tabla y una figura por ensayo). Conviene conservar los resultados de cada serie de capturas en una carpeta propia.

Para regenerar los coeficientes de la FPGA, ejecutar `r3_parametros_verilog` con `modelado_rtl/` como carpeta de trabajo. El script escribe `modelado_rtl/output/buck_params.vh`, que se copia a `fpga/rtl/buck_params.vh` (los pasos siguientes están en [`fpga/README.md`](../fpga/README.md#cambio-de-parámetros-del-modelo)). No hay que editar ese archivo a mano, para que el modelo de referencia, la FPGA y el procesamiento usen los mismos valores.

## Resultados esperados con E1a

| Script | Resultado |
|---|---|
| `p1_inductancia` | 1/L = 313,9 · i<sub>L</sub> + 883,4 [1/H] |
| `p4_2_comparar_fuentes_sin_offset` | Fit de v<sub>o</sub> / i<sub>L</sub>: Modelo–CEuP 78,5 / 81,7 %, OHSIM–CEuP 83,4 / 87,7 %, OHSIM–Modelo 93,5 / 91,4 % |
| `p6_identificar_ft` | Fit del ajuste de 2.º orden: Modelo 97,7 %, CEuP 97,2 %, OHSIM 97,1 % |
| `r3_parametros_verilog` | `KL0 = 741`, `KL_SLOPE = 263`, `KL_MIN = 839`, `VO_DAC_OFFSET_CODE = 29`, iguales a `fpga/rtl/buck_params.vh` |

Las métricas (fit tipo `compare`, RMSE y correlación) se calculan sobre las respuestas incrementales, después de restar a cada fuente su propio nivel previo al escalón.

## Notas

- L, R<sub>s</sub>, V<sub>sw</sub> y V<sub>d</sub> de `buck_params.m` son equivalentes de ajuste que reproducen lo observado en el CEuP, no todas mediciones directas. La resistencia medida de 0,16 Ω incluye los contactos de las borneras.
- La corriente del CEuP se midió con una pinza cuyo cero no se ajustó antes de la serie. `medicion_cfg.m` resta una compensación estimada de 0,172 A; con otra serie de capturas hay que calibrar la pinza (`func/calibrar_pinza.m`) y actualizar esos valores.
- El firmware del CEuP trunca el valor de comparación del PWM, por lo que el ciclo de trabajo efectivo puede diferir del nominal. En E3b, `simulacion_cfg.m` usa el ciclo medido (0,808383) en lugar del nominal 0,81.
