# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

"""Regenera los vectores de arranque desde el header RTL, con enteros exactos.
Uso: python scripts/generate_reference.py (sin dependencias externas).
No modifica el estimulo PWM ni los parametros.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parent.parent
header = (root / 'rtl/buck_params.vh').read_text()
codes = {k: int(v) for k, v in re.findall(r"`define BUCK_(\w+)\s+32'sd(-?\d+)", header)}

def wrap(x):
    return (x + (1 << 31)) % (1 << 32) - (1 << 31)

def mul(a, b):
    return wrap((a * b) >> 22)

pwm = [int(x) for x in (root / 'tb/coldstart_pwm.mem').read_text().split()]
out = {name: [] for name in ('iL', 'vO', 'iC', 'iO')}
i = v = 0
for on in pwm:
    io = mul(v, codes['KR_25_Q'])
    ic = wrap(i - io)
    for name, val in zip(out, (i, v, ic, io)):
        out[name].append(f'{val & 0xffffffff:08x}\n')
    kl = max(codes['KL_MIN_Q'], wrap(codes['KL0_Q'] + mul(i, codes['KL_SLOPE_Q'])))
    vl = wrap((codes['VIN_Q'] - codes['VSW_Q'] if on else -codes['VD_Q']) - v - mul(i, codes['RL_Q']))
    ni = wrap(i + mul(vl, kl))
    i = max(0, ni) if not on else ni
    v = wrap(v + mul(ic, codes['KC_Q']))
for name, lines in out.items():
    (root / f'tb/coldstart_exp_{name}.mem').write_text(''.join(lines), encoding='ascii')
print(f'Regenerated {len(pwm)} exact integer samples from buck_params.vh')
