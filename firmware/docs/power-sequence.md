# Power and safe-state sequence

The current OHSIM netlist shows:

- LaunchPad 3.3 V header supply is not connected;
- LaunchPad 5 V header supply is not connected;
- LaunchPad and OHSIM grounds are connected;
- control and analog measurement signals cross between independently powered
  boards.

## Power-up

1. Connect and power the LaunchPad by mini-USB.
2. Wait for firmware `BOOT_SAFE`/`IDLE` with GPIO0, GPIO2, GPIO3, and GPIO4 low.
3. Power OHSIM by micro-USB using the current-limited supply as usual.
4. Wait for FPGA configuration and DAC initialization.
5. Establish UART communication and issue `PREPARE <test>`.
6. Do not run a step until the firmware reports `ARMED`.

## Power-down

1. Issue `ABORT` or `SAFE`.
2. Confirm PWM and trigger are low.
3. Remove OHSIM power.
4. Remove LaunchPad power.

This ordering avoids driving LaunchPad ADC inputs from powered OHSIM DACs while
the MCU is unpowered. On the opposite transition, the LaunchPad keeps its FPGA
input signals low while OHSIM is unpowered or configuring.

FPGA pull-downs on the LaunchPad Option B inputs remain required as a hardware
fallback during MCU reset or disconnection.

