#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

# Compila y ejecuta los siete bancos de prueba con xvlog/xelab de XSim, sin
# crear el proyecto de Vivado. Alternativa a validate_all.tcl cuando el
# lanzador de simulacion de Vivado no esta disponible (por ejemplo, desde
# Git Bash en Windows).
#
# Uso (desde cualquier carpeta):
#   VIVADO=/c/AMDDesignTools/2025.2/Vivado bash scripts/simular_bancos_xsim.sh
# Variables opcionales:
#   VIVADO  carpeta de instalacion de Vivado (por defecto, la de 2025.2 en
#           C:\AMDDesignTools); en Linux alcanza con tener xvlog en el PATH
#           (source settings64.sh).
#   TBS     lista de bancos a correr (por defecto, los siete).
#   SIM_DIR carpeta de trabajo (por defecto, sim_xsim/ junto a rtl/).
# Sale con codigo 1 si algun banco no informa PASS.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIM_DIR=${SIM_DIR:-$ROOT/sim_xsim}
TBS=${TBS:-buck_variable_l_tb dac_offset_tb dac_scaler_tb buck_zero_hold_tb r_select_gray_tb ad5328_driver_param_tb buck_fpga_validation_phaseC_tb}

if ! command -v xvlog >/dev/null 2>&1; then
    # Windows: los ejecutables "unwrapped" necesitan el entorno que arma
    # normalmente vivado.bat.
    V=${VIVADO:-/c/AMDDesignTools/2025.2/Vivado}
    [ -d "$V" ] || { echo "No se encontro Vivado en $V (definir VIVADO)"; exit 2; }
    VW=$(cygpath -m "$V")
    export XILINX_VIVADO="$VW"
    export RDI_APPROOT="$VW"
    export RDI_BASEROOT=$(cygpath -m "$V/..")
    export RDI_DATADIR="$VW/data"
    export RDI_LIBDIR="$VW/lib/win64.o"
    export RDI_BINDIR="$VW/bin"
    export RDI_PLATFORM=win64
    export RDI_OPT_EXT=.o
    export TCL_LIBRARY="$VW/tps/tcl/tcl8.6"
    export PATH="$V/bin/unwrapped/win64.o:$V/lib/win64.o:$V/tps/win64:$PATH"
    XVLOG=xvlog.exe; XELAB=xelab.exe
else
    XVLOG=xvlog; XELAB=xelab
fi

mkdir -p "$SIM_DIR" && cd "$SIM_DIR" || exit 2
cp "$ROOT"/tb/*.mem .

echo "== Compilando fuentes"
if ! "$XVLOG" -i "$ROOT/rtl" "$ROOT"/rtl/*.v > xvlog_rtl.log 2>&1 ||
   ! "$XVLOG" -sv -i "$ROOT/rtl" "$ROOT"/tb/*.sv > xvlog_tb.log 2>&1; then
    echo "Error de compilacion (ver $SIM_DIR/xvlog_*.log)"; exit 1
fi

fallas=0
for t in $TBS; do
    if ! "$XELAB" --relax --debug off --standalone -R -s "snap_$t" "work.$t" > "sim_$t.log" 2>&1; then
        echo "FAIL  $t (error de elaboracion, ver sim_$t.log)"; fallas=$((fallas+1)); continue
    fi
    if grep -q "PASS" "sim_$t.log" && ! grep -qiE "FAIL|FATAL:|ERROR:" "sim_$t.log"; then
        echo "PASS  $t"
    else
        echo "FAIL  $t (ver $SIM_DIR/sim_$t.log)"; fallas=$((fallas+1))
    fi
done

[ "$fallas" -eq 0 ] && echo "== Los bancos de prueba pasaron" || echo "== $fallas banco(s) con falla"
[ "$fallas" -eq 0 ]
