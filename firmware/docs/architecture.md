# Firmware architecture

## Scope

This firmware controls only the LaunchPad installed on OHSIM. The CEuP power
converter uses a different controller and is not part of this system.

```text
PC / serial client
        |
        | USB UART (SCIA)
        v
LAUNCHXL-F28379D, CPU1
  |-- ePWM1A / GPIO0  --------> FPGA buck PWM input
  |-- ePWM2A / GPIO2  --------> FPGA acquisition trigger
  |-- ePWM2B/ePWM3A   --------> FPGA numerical load selector (GPIO3/GPIO4)
  |-- ADCINC3         <-------- DAC0 AOUT2: inductor current
  `-- ADCIN14         <-------- DAC0 AOUT3: output voltage
```

## CPU allocation

The first implementation uses CPU1 only.

- ePWM hardware generates PWM and trigger timing without software bit-banging.
- ePWM1 SOCA triggers simultaneous ADCA/ADCC conversions once per PWM period.
- One short 10 kHz ISR reads both results and accumulates summary statistics.
  DMA is reserved for a future raw-waveform buffer; it is unnecessary for the
  current min/max/mean consistency check.
- The sequence engine changes setpoints only at segment boundaries.
- UART parsing never runs in a timing-critical ISR.

Resolution is determined by peripheral clocks and conversion modes, not by CPU
instruction load. With a 100 MHz ePWM time-base and 10 kHz up-count PWM, the
period has approximately 10,000 counts (about 0.01 percent duty resolution).

The module boundary `measurement -> control -> pwm command` is kept explicit so
it can later move to CPU2 or the CLA if closed-loop control is required. IPC is
not placed in the current measurement path.

## State machine

```text
BOOT_SAFE -> IDLE -> PRECONDITION -> ARMED -> RUNNING -> DONE
    ^          |          |            |         |
    `----------+----------+------------+---------+--> FAULT
                         SAFE / ABORT / timeout
```

- `BOOT_SAFE`: PWM, trigger, and both load bits are low.
- `IDLE`: UART is available; no experiment is active.
- `PRECONDITION`: initial duty/load are applied and the model is allowed to
  reach the intended operating point.
- `ARMED`: precondition is valid and acquisition equipment may be armed.
- `RUNNING`: timed steps are applied at deterministic PWM boundaries.
- `DONE`: summary is frozen until read or cleared.
- `FAULT`: PWM is forced low and a reason code is retained.

## Experiment lifecycle

The MATLAB `Tvisual = 20*Tsw = 2 ms` interval is treated as a pre-step viewing
window, not as cold-start settling time.

1. Apply preset initial duty and numerical load.
2. Wait for a minimum settling time and, later, an ADC stability criterion.
3. Announce `READY`/enter `ARMED`.
4. Wait the configured 2 ms pre-trigger interval.
5. Apply a step and emit its trigger at a known PWM boundary.
6. Hold for the recipe duration and accumulate validation statistics.
7. Return the single-transition result; the reverse direction is a separate
   bench-aligned preset when applicable.

The current 0.5.x engine uses CPU Timer0 for foreground interval scheduling.
At each step it stages duty and both load bits away from the shadow-load edge;
the ePWM hardware then commits them and raises the trigger together at the next
counter-zero boundary. Long hold intervals have foreground-loop scheduling
granularity (nominally 100 us); the output transitions themselves remain
hardware-aligned to PWM boundaries.

## Measurement role

The LaunchPad ADC provides an immediate consistency check, not the definitive
waveform measurement. The oscilloscope and FPGA ILA remain the authoritative
sources for detailed analysis.

For inductor current, the FPGA DAC output is unipolar and clamps negative
values. The firmware therefore reports `IL_NEAR_ZERO`, never a claim that
current is negative. The threshold is relative to a measured zero offset and
uses hysteresis plus a consecutive-sample requirement.

## Timing instrumentation

The implementation retains:

- ADC interrupt overflow counts;
- maximum ADC ISR execution time in ePWM time-base ticks;
- minimum/maximum/mean ADC values for each segment.

Firmware 0.6.1 samples `iL` on ADCC SOC0 / ADCINC3 and `Vo` on ADCA SOC0 /
ADCIN14. Both SOCs are triggered at the ePWM1 period event, after the PWM off
interval and immediately before the following rising edge. Statistics cover
the 2 ms pre-trigger interval and the complete post-step hold interval.
