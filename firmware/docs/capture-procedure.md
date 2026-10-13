# Instrument capture procedure

Use this same wiring and naming convention for every HIL test. It is designed
to feed the MATLAB importers without manual column edits.

## Oscilloscope wiring

| Channel | Connect to | Scale represented |
|---|---|---|
| CH1 | LaunchPad GPIO2 / J4-8 trigger | 0/3.3 V digital, 1 us pulse |
| CH2 | OHSIM DAC0 AOUT3 / TP-A03 (`Vo`) | 0..3.0 V = 0..40 V |
| CH3 | OHSIM DAC0 AOUT2 / TP-A02 (`iL`) | 0..3.0 V = 0..2.5 A |

Use DC coupling and short ground connections. LaunchPad and OHSIM already
share signal ground through the assembled interface; do not create a long
ground loop with another bench reference.

## Trigger and horizontal setup

- Trigger type: edge, CH1, rising, approximately 1.65 V.
- Acquisition: single.
- Keep at least a small pretrigger region; MATLAB treats the trigger as `t=0`.
- On the MHO934 set **Horizontal > Mem Depth = 1M** and 20 ms/div, with the
  trigger 20 ms from the left edge of the window. This gives 5 MSa/s over
  200 ms (500 points per 100 us PWM period), enough for the step response and
  the ripple, and keeps a combined CSV near 44 MB. These are the settings of
  the published E1a capture.

The old real-bench captures used pulse-width triggering for duty steps because
no dedicated marker existed. OHSIM has GPIO2, so every HIL capture uses the
same rising-edge trigger for both duty and load changes.

## Vertical setup

- CH1: 1 V/div is normally sufficient for the 3.3 V trigger.
- CH2 and CH3: start at 500 mV/div, DC coupled, with zero near the bottom.
- Enable a 20 MHz bandwidth limit if it reduces digital feedthrough without
  distorting the envelope of interest.
- Do not apply probe-ratio or math scaling unless it is recorded. MATLAB
  expects the exported DAC voltage and performs the 3.0 V physical conversion.

## Per-test sequence

1. Send `PREPARE <id>` and wait for `STATE=ARMED`.
2. Run `scripts/arm_ila_trigger.tcl` in Vivado Hardware Manager.
3. Put the oscilloscope in Single/Waiting.
4. Send `RUN` (or press Enter in the host runner).
5. Wait for `STATE=DONE`, query `RESULT`, then send `SAFE`.
6. At the runner's second prompt, upload/export ILA data before rearming it.
7. Export the Rigol combined CSV and press Enter to continue to the next test.

## File names

For the corresponding key (`E1a`, `E1b`, `E2`, `E3a`, `E3b`, `E4a`, `E4b`,
or `E5`), store:

```text
E1a_CH1.csv       trigger
E1a_CH2.csv       Vo DAC
E1a_CH3.csv       iL DAC
E1a_ILA.csv       optional ILA export
E1a_Img.png       optional screenshot
```

Keep the exports inside the runner's capture directory and copy the combined
CSV files to the MATLAB data folder for processing (see `matlab/README.md`).
Do not modify the original exports.

If the oscilloscope exports all enabled channels in one file, rename it to
`E1a.csv`, `E1b.csv`, etc. and store one combined CSV in each test directory.
The MATLAB processing reads only the combined file (`E1a.csv`, ...).

## Acceptance before continuing to the next test

- CH1 contains exactly one 1 us pulse.
- CH2/CH3 are within 0..3.0 V and not clipped.
- ILA `dbg_trigger` is present at `t=0`.
- Firmware reports no `ADC_SATURATION` or `ADC_OVERFLOW`.
- Exported files reopen in MATLAB before changing the instrument setup.
