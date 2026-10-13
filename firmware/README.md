# Firmware de la LaunchPad y ejecución de ensayos

Firmware para la **TI LAUNCHXL-F28379D** (TMS320F28379D, CPU1) montada sobre OHSIM, y herramientas de la PC para ejecutar los ensayos. El firmware genera el PWM del convertidor modelado, selecciona la carga del modelo en la FPGA, emite un único pulso de disparo por ensayo y adquiere i<sub>L</sub> y v<sub>o</sub> con sus ADC como comprobación de consistencia. Las formas de onda definitivas se toman con el osciloscopio y el ILA de la FPGA.

Versión: **firmware 0.6.1**, protocolo UART 1. El firmware se ejecuta desde la RAM y queda listo para incorporar un controlador.

## Contenido

```
ohsim_controller_cpu1/  proyecto de CCS (src/, ccs/) y subconjunto de C2000Ware (vendor/ti/)
experiments/            matriz de ensayos (experiments.csv)
host/                   script de PowerShell, cliente de Python y sus pruebas
docs/                   arquitectura, conexionado, protocolo y procedimientos (en inglés)
```

| Documento | Contenido |
|---|---|
| [`docs/pinout.md`](docs/pinout.md) | Señales entre la LaunchPad y OHSIM |
| [`docs/power-sequence.md`](docs/power-sequence.md) | Secuencia de encendido y apagado |
| [`docs/protocol.md`](docs/protocol.md) | Protocolo UART completo y configuración de una terminal serie |
| [`docs/architecture.md`](docs/architecture.md) | Máquina de estados y ciclo de vida de un ensayo |
| [`docs/capture-procedure.md`](docs/capture-procedure.md) | Configuración del osciloscopio y nombres de archivo |

## Herramientas

- Code Composer Studio 12.8.1 con el compilador TI C2000 22.6.1 LTS.
- C2000Ware 5.04: el subconjunto necesario está incluido en `ohsim_controller_cpu1/vendor/ti`, con la licencia y los encabezados de Texas Instruments, de modo que no hace falta instalarlo ni configurar rutas locales.
- Windows PowerShell 5.1 para el script de ensayos (no requiere instalar nada).
- Opcional: Python 3 con `pyserial` para el cliente `ohsim_cli.py`.
- UART: SCIA por el puerto USB del XDS100 de la LaunchPad, 115200 8N1.

## Compilación y carga

1. Crear o elegir un workspace de CCS fuera del repositorio.
2. *File → Import → Code Composer Studio → CCS Projects* y seleccionar `ohsim_controller_cpu1/ccs/ohsim_controller_cpu1.projectspec`.
3. Seleccionar la configuración `CPU1_RAM`, compilar y cargar el firmware desde el debugger.
4. Verificar en la terminal serie el mensaje `!EVT STATE=IDLE FW=0.6.1`.

Como el firmware corre desde la RAM, hay que cargarlo cada vez que se alimenta la LaunchPad.

## Secuencia de encendido

1. Alimentar la LaunchPad con OHSIM apagada, cargar el firmware y comprobar que sus salidas (GPIO0, GPIO2, GPIO3 y GPIO4) estén en nivel bajo.
2. Alimentar y programar OHSIM.
3. Para apagar, seguir el orden inverso.

El PWM y los estímulos permanecen deshabilitados hasta recibir una orden. Si la comunicación USB se corta de forma intermitente, probar con otro puerto de la PC (en este trabajo, los puertos frontales del gabinete produjeron desconexiones).

## Ensayos

La matriz de [`experiments/experiments.csv`](experiments/experiments.csv) define los ocho ensayos, cada uno como una receta de fases (precondición de 1 s en el punto de operación inicial, 2 ms antes del escalón y mantenimiento de 332 o 600 ms):

| ID | Ensayo | Estímulo |
|---|---|---|
| 11 | E1a | Escalón de ciclo de trabajo 0,45 → 0,46, R = 16,6 Ω |
| 12 | E1b | Escalón de ciclo de trabajo 0,46 → 0,45, R = 16,6 Ω |
| 2 | E2 | Escalón de carga 25 → 16,6 Ω, δ = 0,30 |
| 31 | E3a | Escalón de ciclo de trabajo 0,80 → 0,81, R = 25 Ω |
| 32 | E3b | Escalón de ciclo de trabajo 0,81 → 0,80, R = 25 Ω |
| 41 | E4a | Escalón de carga 50 → 25 Ω, δ = 0,70 |
| 42 | E4b | Escalón de carga 25 → 16,6 Ω, δ = 0,70 |
| 5 | E5 | Escalón de carga 16,6 → 25 Ω, δ = 0,70 |

E1b y E5 son recetas de capturas que finalmente no se usaron en el análisis. `host/test_recipes.py` comprueba que las recetas compiladas en `test_presets.c` coincidan con la matriz.

Para ejecutar los ensayos, ver [`host/README.md`](host/README.md). Antes de cada ensayo hay que armar el ILA (ver [`fpga/README.md`](../fpga/README.md)) y el osciloscopio, con el canal 1 en el pulso de disparo (GPIO2), el canal 2 en TP-A03 (v<sub>o</sub>) y el canal 3 en TP-A02 (i<sub>L</sub>). La configuración del osciloscopio está en [`docs/capture-procedure.md`](docs/capture-procedure.md).

**Resultado esperado:** en `results.csv`, todos los ensayos aprobados, salvo la advertencia de corriente próxima a cero en E2.

## Operación manual

Cada orden se envía como una línea completa con un identificador decimal al comienzo. Un ensayo mínimo desde una terminal serie (PuTTY o la terminal de CCS) es:

```text
@1 PING
@2 SAFE
@3 CAL ZERO
@4 ADC READ
@5 PREPARE 11
@6 RUN
@7 RESULT
@8 SAFE
```

`CAL ZERO` se ejecuta con OHSIM alimentada, el modelo en su estado inicial y el PWM apagado. Antes de preparar un ensayo, `ADC READ` debe informar `ADC_OVF=0`. El protocolo completo está en [`docs/protocol.md`](docs/protocol.md).
