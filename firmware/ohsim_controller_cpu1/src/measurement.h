// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef MEASUREMENT_H
#define MEASUREMENT_H

#include <stdbool.h>
#include <stdint.h>

#define MEAS_FLAG_IL_NEAR_ZERO   0x0001U
#define MEAS_FLAG_ADC_SATURATION 0x0002U
#define MEAS_FLAG_ADC_OVERFLOW   0x0004U
#define MEAS_FLAG_NO_SAMPLES     0x0008U
#define MEAS_FLAG_CAL_REQUIRED   0x0010U

typedef enum
{
    MEAS_VERDICT_PASS = 0,
    MEAS_VERDICT_WARNING,
    MEAS_VERDICT_FAIL
} MeasurementVerdict;

typedef struct
{
    uint32_t sampleCount;
    uint16_t ilMinRaw;
    uint16_t ilMaxRaw;
    uint16_t ilMeanRaw;
    uint16_t voMinRaw;
    uint16_t voMaxRaw;
    uint16_t voMeanRaw;
    uint16_t ilZeroRaw;
    uint16_t voZeroRaw;
    uint16_t flags;
    uint32_t overflowCount;
    uint16_t maxIsrTicks;
    bool calibrated;
} MeasurementResult;

void Measurement_init(void);
void Measurement_startSampling(void);
void Measurement_startRun(void);
void Measurement_finishRun(void);
void Measurement_abortRun(void);
bool Measurement_calibrateZero(void);
bool Measurement_getResult(MeasurementResult *result);
MeasurementVerdict Measurement_getVerdict(const MeasurementResult *result);
const char *Measurement_getVerdictName(MeasurementVerdict verdict);
uint16_t Measurement_getLatestIlRaw(void);
uint16_t Measurement_getLatestVoRaw(void);
uint16_t Measurement_getIlZeroRaw(void);
uint16_t Measurement_getVoZeroRaw(void);
uint32_t Measurement_getOverflowCount(void);
bool Measurement_isCalibrated(void);

#endif
