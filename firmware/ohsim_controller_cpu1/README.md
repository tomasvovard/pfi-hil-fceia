# Proyecto de CCS: ohsim_controller_cpu1

Firmware 0.6.1 para la LAUNCHXL-F28379D, CPU1.

- `ccs/ohsim_controller_cpu1.projectspec`: especificación del proyecto para importar en CCS 12.8.1 (configuraciones `CPU1_RAM`, usada en los ensayos, y `CPU1_FLASH`).
- `src/`: aplicación. La versión se define en `src/app_config.h` y el firmware la informa como `FW=0.6.1` en las respuestas a `PING` e `INFO`. Las recetas de los ensayos están en `src/test_presets.c`.
- `vendor/ti/`: subconjunto de C2000Ware 5.04 con licencia de Texas Instruments (ver [`vendor/README.md`](vendor/README.md)).

Los pasos de importación y compilación están en el [README del firmware](../README.md). El workspace de CCS y las carpetas generadas (`CPU1_RAM`, `CPU1_FLASH`, `Debug`, `Release`) no se guardan en el repositorio.
