# Datos de ejemplo

Capturas del ensayo **E1a**: escalón de ciclo de trabajo de 0,45 a 0,46 con carga de 16,6 Ω, V<sub>i</sub> = 40 V y PWM de 10 kHz. Son las que procesan los scripts de [`matlab/`](../matlab/) y permiten reproducir los resultados de E1a del trabajo.

```
E1a/ceup/E1a.csv                 convertidor multipropósito del laboratorio (CEuP)
E1a/ohsim/E1a.csv                OHSIM, salidas del DAC0
inductancia/puntos_L_ceup.csv    puntos (iL, L) de todos los ensayos del CEuP, para p1_inductancia.m
```

## Formato de las capturas

Ambas capturas se tomaron con un osciloscopio Rigol MHO934 y se exportaron como un único CSV con todos los canales. La primera línea indica el tiempo inicial (`t0`, unos 20 ms antes del escalón) y el intervalo entre muestras (`tInc` = 200 ns, 5 MS/s). Le siguen 1.000.000 de filas con una columna por canal, en volts. `matlab/func/leer_csv_rigol.m` lee este formato.

| Captura | CH1 | CH2 | CH3 |
|---|---|---|---|
| CEuP | Nodo de conmutación v<sub>sw</sub> | v<sub>o</sub> | Pinza de corriente (i<sub>L</sub>) |
| OHSIM | Pulso de disparo de la LaunchPad | v<sub>o</sub> del DAC (TP-A03) | i<sub>L</sub> del DAC (TP-A02) |

Las conversiones a magnitudes físicas están en `matlab/cfg/medicion_cfg.m`. En el CEuP, la pinza se usó con 0,100 V/A y cinco vueltas, y el canal quedó configurado con factor de sonda ×10, de modo que la ganancia resultante es de 5 V/A; el cero de la pinza no se ajustó antes de la serie y se compensa en el procesamiento. En OHSIM, el canal de v<sub>o</sub> cubre 0 a 40 V con 0 a 3 V y el de i<sub>L</sub>, 0 a 2,5 A con 0 a 3 V.

La captura de OHSIM se tomó con el archivo de configuración de la FPGA publicado en el *release* `candidate-2026-09-11` y el firmware 0.6.1 de la LaunchPad.
