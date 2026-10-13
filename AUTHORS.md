# Autoría y procedencia

## Autor

**Tomás Vovard**: rediseño de la placa (esquemáticos 3.2, PCB 3.0), modelo no ideal del convertidor buck y su implementación en la FPGA, firmware de la LaunchPad, herramientas de ensayo, entorno de MATLAB, ensayos y análisis.

Proyecto Final de Ingeniería Electrónica, Facultad de Ciencias Exactas, Ingeniería y Agrimensura (FCEIA), Universidad Nacional de Rosario. Cátedra de Electrónica de Potencia.

## Diseño original de OHSIM

La plataforma OHSIM (*Open Hardware Simulator*) y su *Platform Board* (versión 0.1 en la serigrafía original) son diseño de **Pablo Trujillo** ([controlpaths.com](https://controlpaths.com/), [ohsim.tech](https://ohsim.tech/)), que los publicó como hardware abierto:

- Proyecto en Hackster, publicado bajo CERN-OHL (sin variante ni versión indicadas).
- Artículo [*Deploying a Buck-Boost model on a custom HIL platform*](https://controlpaths.com/2024/11/23/deploying-model-custom-platform/) (controlpaths.com).
- Repositorio original `github.com/controlpaths/sim_platform_board`, hoy no disponible; [captura de la Wayback Machine](http://web.archive.org/web/20250812080845/https://github.com/controlpaths/sim_platform_board).

Este repositorio contiene:

- `hardware/`: rediseño de la *Platform Board* (versión 3.0 en la serigrafía). El PCB lleva en la serigrafía inferior la leyenda "Basado en el diseño original de Pablo Trujillo (controlpaths.com)". Se distribuye bajo CERN-OHL-S-2.0, variante que admite como derivado un diseño publicado bajo cualquiera de las variantes de CERN-OHL v2.
- `fpga/rtl/buck_v1_0.v`: el núcleo numérico del modelo parte del modelo ideal de convertidor buck publicado por Pablo Trujillo y fue ampliado con las caídas del interruptor y del diodo, la resistencia serie, el bloqueo de la corriente inversa del diodo, la inductancia dependiente de la corriente, el escalado a los DAC y la selección de carga en caliente.

## Terceros

| Componente | Origen | Licencia |
|---|---|---|
| `firmware/ohsim_controller_cpu1/vendor/ti/` | Texas Instruments, C2000Ware 5.04 | Términos de TI (`C2000Ware_license.txt`) |
| `hardware/lib/` | Bibliotecas KiCad y modelos 3D de terceros, en su mayoría heredados del diseño original (ver [`hardware/README.md`](hardware/README.md#bibliotecas-de-terceros)) | La de cada autor |

## Agradecimientos

A Andrés Vazquez Sieber (director), Pablo Amoedo (asesor), Gustavo Garcia y Sergio Koatz, por su acompañamiento durante el proyecto.
