# UART protocol contract

## Framing

- ASCII, 115200 8N1.
- One command or response per line. CR, LF, and CR+LF are accepted as command
  terminators; firmware responses use LF.
- Maximum line length: 128 bytes including terminator.
- Commands carry a request identifier: `@<id> <command>`.
- Replies repeat that identifier.
- Unsolicited events begin with `!EVT`.
- Only one command may be outstanding in the initial host implementation.

## Configuración de una terminal serie

Conectar la terminal al puerto COM expuesto por el USB del depurador XDS100v2
de la LaunchPad. En PuTTY, la terminal de CCS o un programa equivalente usar:

| Parámetro | Valor |
|---|---|
| Velocidad | 115200 baud |
| Bits de datos | 8 |
| Paridad | None / ninguna |
| Bits de parada | 1 |
| Control de flujo | None / ninguno |
| Codificación | ASCII |
| Fin de línea transmitido | CR, LF o CR+LF |
| Fin de línea recibido | LF |
| Eco local | Opcional; desactivarlo si aparecen comandos duplicados |

En Windows, confirmar en el Administrador de dispositivos cuál de los puertos
del XDS100 corresponde a la interfaz serie. El número de puerto (`COMn`)
puede cambiar entre computadoras o puertos USB. Cada orden debe enviarse como
una línea completa, con un identificador decimal al comienzo: `@1 PING`.

Examples:

```text
@1 PING
@1 OK FW=0.6.1 PROTO=1

@2 PREPARE 31
@2 OK STATE=PRECONDITION
!EVT STATE=ARMED TEST=31

@3 RUN
@3 OK STATE=RUNNING
!EVT STEP=1 TRIGGER=DUTY
!EVT STATE=DONE RESULT=PASS
```

## Experiment commands

| Command | Purpose |
|---|---|
| `PING` | Connectivity and protocol version |
| `INFO` | Firmware, hardware, and build information |
| `STATUS` | Current state, preset, step, and warning flags |
| `SAFE` | Force safe outputs and return to IDLE |
| `PREPARE <id>` | Apply the initial point; transitions to `ARMED` after at least 1 s |
| `RUN` | Execute the prepared preset after its 2 ms pretrigger interval |
| `ABORT` | Stop immediately and force PWM low |
| `RESULT` | Return the frozen timing and ADC consistency summary |
| `CAL ZERO` | Measure zero offsets with PWM disabled |
| `ADC READ` | Read latest raw `iL`/`Vo`, calibration state, and overflow count |

## Manual hardware commands

These commands support staged bring-up and diagnostics. They do not start an
experiment or emit a trigger.

| Command | Purpose |
|---|---|
| `PWM SET <duty_ppm>` | Set duty in parts per million; accepted range 10000 to 990000 |
| `PWM ON` | Clear the ePWM1A one-shot trip and start complete PWM cycles |
| `PWM OFF` | Immediately latch ePWM1A low |
| `LOAD <00|01|11>` | Set a valid numerical-load code while PWM is off |
| `TRIGGER` | Arm one 1 us ePWM2A pulse for the next PWM-period boundary |

The reserved `10` load input is intentionally rejected. Planned experiment
transitions use the valid Gray-adjacent sequence `00 <-> 01 <-> 11`.

Firmware 0.6.1 implements eight built-in presets in
`experiments/experiments.csv`. Each preset matches one real-bench capture and
contains exactly one transition. Duty, numerical-load code, and the 1 us
trigger are committed at the same PWM-period boundary. After the hold interval,
the state is `DONE`; PWM and the final load point remain active for observation
until `SAFE` or `ABORT` is sent.

| Preset | Bench capture | Transition |
|---:|---|---|
| `11` | E1a | duty 0.45 -> 0.46 at 16.6 ohm |
| `12` | E1b | duty 0.46 -> 0.45 at 16.6 ohm |
| `2` | E2 | load 25 -> 16.6 ohm at duty 0.30 |
| `31` | E3a | duty 0.80 -> 0.81 at 25 ohm |
| `32` | E3b | duty 0.81 -> 0.80 at 25 ohm |
| `41` | E4a | load 50 -> 25 ohm at duty 0.70 |
| `42` | E4b | load 25 -> 16.6 ohm at duty 0.70 |
| `5` | E5 | load 16.6 -> 25 ohm at duty 0.70 |

Dynamic `SEQ CLEAR/ADD/RUN` commands are reserved for a later protocol version.
They do not block the initial built-in-preset workflow.

## Result levels

- `PASS`: all implemented consistency checks passed.
- `WARNING`: data was acquired but a non-fatal condition occurred, such as
  `IL_NEAR_ZERO`.
- `FAIL`: invalid state, timeout, ADC saturation, DMA overflow, or another
  condition that invalidates the run.

Firmware 0.6.1 returns one machine-readable result line. All ADC values remain
raw 12-bit counts until gain calibration is measured:

```text
@4 OK RESULT=PASS TEST=11 STEPS=1 SAMPLES=3340 IL_MIN_RAW=... IL_MAX_RAW=... IL_MEAN_RAW=... VO_MIN_RAW=... VO_MAX_RAW=... VO_MEAN_RAW=... IL_ZERO_RAW=... VO_ZERO_RAW=... ADC_OVF=0 ISR_MAX_TICKS=... FLAGS=NONE
```

Possible flags are `IL_NEAR_ZERO`, `ADC_SATURATION`, `ADC_OVERFLOW`,
`NO_SAMPLES`, and `CAL_REQUIRED`. Multiple flags are comma-separated.
`CAL_REQUIRED` and `IL_NEAR_ZERO` produce `WARNING`; saturation, overflow, or
no samples produce `FAIL`.

## Parser rules

- Unknown commands return `ERR UNKNOWN_COMMAND`.
- Invalid arguments return `ERR ARGUMENT` without changing outputs.
- Commands invalid in the current state return `ERR STATE`.
- Buffer overflow discards the entire line and returns `ERR LINE_TOO_LONG`.
- UART receive processing never changes ePWM registers directly; it posts a
  validated request to the foreground state machine.
