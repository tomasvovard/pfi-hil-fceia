# Herramientas de la PC para ejecutar ensayos

| Archivo | Función |
|---|---|
| `ohsim_run.ps1` | Ejecuta uno o los ocho ensayos con Windows PowerShell, sin instalar nada |
| `ohsim_cli.py` | Cliente equivalente en Python (requiere `pyserial`), con órdenes sueltas para diagnóstico |
| `verify_demo.py` | Audita la carpeta de una corrida completa (registro del firmware y capturas exportadas) |
| `test_*.py` | Pruebas de las herramientas y de la coincidencia entre `experiments.csv` y `test_presets.c` |

Ninguna de las herramientas transmite formas de onda: las capturas detalladas son las del osciloscopio y el ILA. Antes de usarlas, cerrar PuTTY o la terminal serie de CCS, porque un puerto COM solo puede estar abierto por un programa a la vez. Los ejemplos se ejecutan desde la carpeta `firmware/`.

## Ejecución con PowerShell

1. Identificar el puerto COM de la interfaz serie del XDS100 de la LaunchPad:

```powershell
powershell -ExecutionPolicy Bypass -File host\ohsim_run.ps1 -ListPorts
```

2. Ejecutar un ensayo (en el ejemplo, E1a), reemplazando `COMn` por el puerto identificado:

```powershell
powershell -ExecutionPolicy Bypass -File host\ohsim_run.ps1 -Port COMn -TestId 11 -ArmPrompt -OutputDir captures\E1a
```

3. Ejecutar los ocho ensayos:

```powershell
powershell -ExecutionPolicy Bypass -File host\ohsim_run.ps1 -Port COMn -All -ArmPrompt -OutputDir captures\corrida_completa
```

Al comenzar, el script fuerza `SAFE`, espera un segundo y ejecuta `CAL ZERO` para medir el cero de los conversores. Después lleva cada ensayo por `PREPARE`, `RUN`, `RESULT` y `SAFE`, y comprueba que el veredicto del evento y el del resultado coincidan. Con `-ArmPrompt` se detiene antes de `RUN`, para armar el ILA y el osciloscopio, y otra vez al terminar, para exportar las capturas antes del ensayo siguiente. Crea una subcarpeta por ensayo (`E1a` a `E5`) para guardar ahí las exportaciones, y registra la sesión completa en `transcript.jsonl` y el resumen en `results.csv`. Ante una falla intenta volver a `SAFE` antes de cerrar el puerto.

La opción `-ExecutionPolicy Bypass` afecta solo a esa invocación y no cambia la política de PowerShell del sistema.

**Resultado esperado:** todos los ensayos aprobados en `results.csv`, salvo la advertencia de corriente próxima a cero en E2.

## Cliente de Python

```powershell
py -m pip install -r host\requirements.txt
py host\ohsim_cli.py ports
py host\ohsim_cli.py --port COMn ping
py host\ohsim_cli.py --port COMn status
py host\ohsim_cli.py --port COMn adc-read
py host\ohsim_cli.py --port COMn cal-zero
py host\ohsim_cli.py --port COMn run 11 --arm-prompt --output captures\E1a
py host\ohsim_cli.py --port COMn run-all --arm-prompt --output captures\corrida_completa
```

`cal-zero` se ejecuta con OHSIM alimentada, el modelo en su estado inicial y el PWM apagado; promedia 256 muestras sincronizadas. En `run`, la pausa ocurre después de `ARMED`, de modo que el ILA y el osciloscopio quedan armados antes de la orden `RUN`. Todo intento termina con `SAFE`, incluso ante errores de protocolo.

## Auditoría de una corrida

Después de exportar las capturas de los instrumentos:

```powershell
py host\verify_demo.py captures\corrida_completa
```

Comprueba los ocho ensayos, la cantidad de muestras de cada uno, las banderas de desborde y críticas, el registro de la sesión, la presencia de las capturas del osciloscopio (un CSV combinado o los archivos CH1, CH2 y CH3 de cada ensayo) y, como mínimo, la captura del ILA de E1a. Escribe `evidence_report.md` en la carpeta de la corrida y termina con un código distinto de cero si falta alguna evidencia. Con `--no-waveforms` revisa solo el registro del firmware.

## Pruebas

```powershell
py -m unittest discover -s host
```

No necesitan la LaunchPad conectada.
