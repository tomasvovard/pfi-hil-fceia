# OHSIM to LaunchPad pinout

## Digital control

| Function | LaunchPad header | MCU peripheral | FPGA pin | Idle |
|---|---|---|---|---|
| Buck PWM | J4-10 | GPIO0 / ePWM1A | A2 | Low |
| Acquisition trigger | J4-8 | GPIO2 / ePWM2A | A4 | Low |
| Load selector b0 | J4-7 | GPIO3 | A5 | Low |
| Load selector b1 | J4-6 | GPIO4 | B5 | Low |

The FPGA XDC has LaunchPad Option B active on A4/A5/B5, with input
pull-downs. This mapping was validated in hardware with the PWM, one-shot
trigger, and all three load codes.

## Analog feedback

| Signal | OHSIM source | LaunchPad header/input | Meaning |
|---|---|---|---|
| `iL` | DAC0 AOUT2 | J3-4 / ADCINC3 | Unipolar inductor current |
| `Vo` | DAC0 AOUT3 | J3-3 / ADCIN14 | Unipolar output voltage |

Both DAC and ADC paths are 12-bit. The board netlist connects both AD5328
reference banks to the 3.0 V output of U16 (`REF2030`); U6 buffers AOUT2/AOUT3
at unity DC gain before the LaunchPad inputs. The F28379D ADC nominal full
scale is 3.3 V, so the ideal first-order conversion (before measured offset and
gain correction) is:

```text
ADC_raw ~= physical/full_scale * 4095 * 3.0/3.3
iL_A    ~= (ADC_raw-iL_zero) * 2.5*3.3/(4095*3.0)
Vo_V    ~= (ADC_raw-Vo_zero) * 40*3.3/(4095*3.0)
```

Calibration parameters must still include the measured zero offset and gain
for each complete DAC-to-ADC path; the nominal formula is a wiring sanity
check, not the final metrology calibration.

## Load code

| b1 b0 | Numerical resistance |
|---|---:|
| `00` | 16.6 ohm |
| `01` | 25 ohm |
| `11` | 50 ohm |
| `10` | Retain previous valid value |

All planned transitions use adjacent valid codes (`00 <-> 01 <-> 11`). GPIO3
and GPIO4 are updated together before the associated trigger.

## UART

The LaunchPad XDS100v2 USB serial bridge uses SCIA on GPIO42 (TX) and GPIO43
(RX). Initial protocol configuration is 115200 baud, 8 data bits, no parity,
one stop bit.

