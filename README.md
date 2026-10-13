# OHSIM: simulación en tiempo real de un convertidor buck

Repositorio del Proyecto Final de Ingeniería Electrónica (FCEIA, Universidad Nacional de Rosario) sobre la puesta en marcha de la plataforma de *hardware-in-the-loop* **OHSIM** y su validación con un modelo de convertidor buck.

OHSIM es una placa con una FPGA AMD Spartan-7 XC7S50 y DAC de 12 bits, diseñada originalmente por Pablo Trujillo, que ejecuta en tiempo real el modelo de un convertidor de potencia y presenta sus variables como tensiones analógicas. En este trabajo se rediseñó y fabricó la placa, se implementó en la FPGA un modelo no ideal del buck (pérdidas e inductancia dependiente de la corriente, paso de 200 ns), se automatizaron los ensayos con una LaunchPad F28379D y se comparó la respuesta de OHSIM con la del modelo simulado en Simulink y con la del convertidor real del laboratorio (CEuP). En el ensayo E1a, el fit de v<sub>o</sub> entre OHSIM y el modelo es de 93,5 %, y entre OHSIM y el convertidor real, de 83,4 %.

## Contenido

| Carpeta | Contenido | Herramientas |
|---|---|---|
| [`hardware/`](hardware/) | Proyecto KiCad de la placa (esquemáticos 3.2, PCB 3.0) y salidas de fabricación | KiCad 9.0 |
| [`fpga/`](fpga/) | Modelo del buck en Verilog, bancos de prueba, restricciones y scripts de Vivado | Vivado 2025.2, Python 3 |
| [`firmware/`](firmware/) | Firmware de la LaunchPad que genera el PWM y ejecuta los ensayos, y herramientas de la PC | CCS 12.8.1, compilador C2000 22.6.1, PowerShell |
| [`matlab/`](matlab/) | Modelo de referencia en Simulink, generador de coeficientes y procesamiento de capturas | MATLAB R2024b, Simulink 24.2 |
| [`data/`](data/) | Capturas del ensayo E1a (CEuP y OHSIM) | |

Cada carpeta tiene su README con el contenido, los pasos de uso y el resultado esperado.

El archivo de configuración de la FPGA utilizado en los ensayos (`.bit`), el archivo de sondas del ILA (`.ltx`), los informes de compilación y sus sumas SHA-256 están en el *release* **candidate-2026-09-11**.

## Herramientas y versiones

| Herramienta | Uso |
|---|---|
| KiCad 9.0 | Esquemáticos y PCB |
| Vivado 2025.2 | Simulación, síntesis, implementación, programación de la FPGA e ILA |
| Python 3, sin bibliotecas adicionales | Vectores de referencia de los bancos de prueba y pruebas del host |
| Code Composer Studio 12.8.1, compilador C2000 22.6.1 LTS | Firmware de la LaunchPad (el subconjunto necesario de C2000Ware 5.04 está incluido) |
| Windows PowerShell 5.1 | Ejecución de los ensayos |
| MATLAB R2024b, Simulink 24.2 | Modelo de referencia, coeficientes y procesamiento |
| System Identification Toolbox, Control System Toolbox | Identificación de funciones de transferencia |
| Programador JTAG (Digilent JTAG-HS3) | Programación de la FPGA y descarga del ILA |
| Osciloscopio de cuatro canales | Captura de las salidas de OHSIM y del CEuP |

Una versión distinta puede funcionar, pero conviene verificarla con los bancos de prueba y con el ensayo E1a antes de comparar resultados.

## Inicio rápido

Sin hardware, se puede comprobar el diseño y reproducir el procesamiento:

1. **FPGA**: desde `fpga/`, `vivado -mode batch -source scripts/validate_all.tcl` corre los siete bancos de prueba, que deben informar `PASS`.
2. **MATLAB**: con `matlab/` como carpeta de trabajo, ejecutar `p4_2_comparar_fuentes_sin_offset` y `p6_identificar_ft` sobre las capturas de E1a y comparar con los resultados esperados de [`matlab/README.md`](matlab/README.md#resultados-esperados-con-e1a).
3. **Host**: desde `firmware/`, `py -m unittest discover -s host`.

Con la plataforma, el orden de trabajo es programar la FPGA con el archivo del *release* ([`fpga/`](fpga/README.md#programación-y-captura-con-el-ila)), cargar el firmware en la LaunchPad respetando la secuencia de encendido ([`firmware/`](firmware/README.md)), ejecutar los ensayos con `host/ohsim_run.ps1` y procesar las capturas en [`matlab/`](matlab/).

## Clonar una sola parte

Para descargar solo una carpeta (por ejemplo, `fpga/`) sin el resto del repositorio:

```
git clone --filter=blob:none --sparse https://github.com/tomasvovard/pfi-hil-fceia.git
cd pfi-hil-fceia
git sparse-checkout set fpga
```

Para agregar otra carpeta más tarde, `git sparse-checkout add matlab data`. Sin Git, cada carpeta puede descargarse desde la página del repositorio.

## Autoría y licencias

Autor: Tomás Vovard. El diseño original de OHSIM es de Pablo Trujillo ([controlpaths.com](https://controlpaths.com/)); la procedencia de cada parte y los agradecimientos están en [`AUTHORS.md`](AUTHORS.md).

- Software, scripts, documentación y datos: [MIT](LICENSE).
- Hardware (`hardware/`): [CERN-OHL-S-2.0](hardware/LICENSE).
- Archivos de terceros (C2000Ware de Texas Instruments y bibliotecas de KiCad en `hardware/lib/`): su licencia original.
