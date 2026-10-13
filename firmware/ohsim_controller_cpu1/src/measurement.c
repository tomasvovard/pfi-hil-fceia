// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "measurement.h"

#include "driverlib.h"
#include "device.h"

#include "app_config.h"
#include "pwm.h"
#include "timebase.h"

static volatile uint16_t latestIlRaw;
static volatile uint16_t latestVoRaw;
static volatile uint32_t overflowCount;
static volatile uint16_t maxIsrTicks;

static volatile bool captureActive;
static volatile uint32_t captureCount;
static volatile uint32_t ilSum;
static volatile uint32_t voSum;
static volatile uint16_t ilMin;
static volatile uint16_t ilMax;
static volatile uint16_t voMin;
static volatile uint16_t voMax;
static volatile uint16_t captureFlags;
static volatile uint16_t nearZeroConsecutive;
static uint32_t captureOverflowStart;

static volatile bool calibrationActive;
static volatile bool calibrated;
static volatile uint32_t calibrationCount;
static volatile uint32_t calibrationIlSum;
static volatile uint32_t calibrationVoSum;
static volatile uint16_t ilZeroRaw;
static volatile uint16_t voZeroRaw;

static MeasurementResult frozenResult;
static bool resultValid;

static void configureAdc(uint32_t base);
static uint16_t elapsedPwmTicks(uint16_t start, uint16_t end);
__interrupt void adcA1ISR(void);

void Measurement_init(void)
{
    latestIlRaw = 0U;
    latestVoRaw = 0U;
    overflowCount = 0UL;
    maxIsrTicks = 0U;
    captureActive = false;
    calibrationActive = false;
    calibrated = false;
    ilZeroRaw = 0U;
    voZeroRaw = 0U;
    resultValid = false;

    configureAdc(ADCA_BASE);
    configureAdc(ADCC_BASE);
    DEVICE_DELAY_US(1000UL);

    ADC_setupSOC(ADCA_BASE, ADC_SOC_NUMBER0, ADC_TRIGGER_EPWM1_SOCA,
                 ADC_CH_ADCIN14, APP_ADC_ACQPS);
    ADC_setupSOC(ADCC_BASE, ADC_SOC_NUMBER0, ADC_TRIGGER_EPWM1_SOCA,
                 ADC_CH_ADCIN3, APP_ADC_ACQPS);

    ADC_setInterruptSource(ADCA_BASE, ADC_INT_NUMBER1, ADC_SOC_NUMBER0);
    ADC_clearInterruptStatus(ADCA_BASE, ADC_INT_NUMBER1);
    ADC_clearInterruptOverflowStatus(ADCA_BASE, ADC_INT_NUMBER1);
    ADC_enableInterrupt(ADCA_BASE, ADC_INT_NUMBER1);

    Interrupt_register(INT_ADCA1, &adcA1ISR);
    Interrupt_enable(INT_ADCA1);

    /* Sample once per PWM period, after the off interval and before the next
     * rising edge. The trip-zone OFF state does not stop the time base, so
     * ADC READ and CAL ZERO remain available while the PWM pin is held low. */
    EPWM_disableADCTrigger(EPWM1_BASE, EPWM_SOC_A);
    EPWM_setADCTriggerSource(EPWM1_BASE, EPWM_SOC_A,
                             EPWM_SOC_TBCTR_PERIOD);
    EPWM_setADCTriggerEventPrescale(EPWM1_BASE, EPWM_SOC_A, 1U);
    EPWM_clearADCTriggerFlag(EPWM1_BASE, EPWM_SOC_A);
}

void Measurement_startSampling(void)
{
    /* Do not allow ePWM to request conversions until global interrupts are
     * enabled. Otherwise the first ADC interrupt remains pending throughout
     * startup and is reported as a false one-shot overflow. */
    ADC_clearInterruptStatus(ADCA_BASE, ADC_INT_NUMBER1);
    ADC_clearInterruptOverflowStatus(ADCA_BASE, ADC_INT_NUMBER1);
    EPWM_clearADCTriggerFlag(EPWM1_BASE, EPWM_SOC_A);
    EPWM_enableADCTrigger(EPWM1_BASE, EPWM_SOC_A);
}

void Measurement_startRun(void)
{
    Interrupt_disable(INT_ADCA1);

    captureCount = 0UL;
    ilSum = 0UL;
    voSum = 0UL;
    ilMin = 4095U;
    ilMax = 0U;
    voMin = 4095U;
    voMax = 0U;
    captureFlags = calibrated ? 0U : MEAS_FLAG_CAL_REQUIRED;
    nearZeroConsecutive = 0U;
    captureOverflowStart = overflowCount;
    maxIsrTicks = 0U;
    resultValid = false;
    captureActive = true;

    ADC_clearInterruptStatus(ADCA_BASE, ADC_INT_NUMBER1);
    ADC_clearInterruptOverflowStatus(ADCA_BASE, ADC_INT_NUMBER1);
    Interrupt_enable(INT_ADCA1);
}

void Measurement_finishRun(void)
{
    uint32_t count;

    Interrupt_disable(INT_ADCA1);
    captureActive = false;
    count = captureCount;

    frozenResult.sampleCount = count;
    frozenResult.flags = captureFlags;
    frozenResult.overflowCount = overflowCount - captureOverflowStart;
    frozenResult.maxIsrTicks = maxIsrTicks;
    frozenResult.ilZeroRaw = ilZeroRaw;
    frozenResult.voZeroRaw = voZeroRaw;
    frozenResult.calibrated = calibrated;

    if(count == 0UL)
    {
        frozenResult.ilMinRaw = 0U;
        frozenResult.ilMaxRaw = 0U;
        frozenResult.ilMeanRaw = 0U;
        frozenResult.voMinRaw = 0U;
        frozenResult.voMaxRaw = 0U;
        frozenResult.voMeanRaw = 0U;
        frozenResult.flags |= MEAS_FLAG_NO_SAMPLES;
    }
    else
    {
        frozenResult.ilMinRaw = ilMin;
        frozenResult.ilMaxRaw = ilMax;
        frozenResult.ilMeanRaw = (uint16_t)((ilSum + (count / 2UL)) / count);
        frozenResult.voMinRaw = voMin;
        frozenResult.voMaxRaw = voMax;
        frozenResult.voMeanRaw = (uint16_t)((voSum + (count / 2UL)) / count);
    }

    if(frozenResult.overflowCount != 0UL)
    {
        frozenResult.flags |= MEAS_FLAG_ADC_OVERFLOW;
    }

    resultValid = true;
    ADC_clearInterruptStatus(ADCA_BASE, ADC_INT_NUMBER1);
    Interrupt_enable(INT_ADCA1);
}

void Measurement_abortRun(void)
{
    captureActive = false;
    resultValid = false;
}

bool Measurement_calibrateZero(void)
{
    uint32_t start;

    if(captureActive || calibrationActive)
    {
        return(false);
    }

    Interrupt_disable(INT_ADCA1);
    calibrationCount = 0UL;
    calibrationIlSum = 0UL;
    calibrationVoSum = 0UL;
    calibrationActive = true;
    ADC_clearInterruptStatus(ADCA_BASE, ADC_INT_NUMBER1);
    ADC_clearInterruptOverflowStatus(ADCA_BASE, ADC_INT_NUMBER1);
    Interrupt_enable(INT_ADCA1);

    start = Timebase_now();
    while(calibrationActive)
    {
        if(Timebase_elapsedUs(start, APP_ADC_CALIBRATION_TIMEOUT_US))
        {
            calibrationActive = false;
            return(false);
        }
    }

    return(calibrated);
}

bool Measurement_getResult(MeasurementResult *result)
{
    if(!resultValid)
    {
        return(false);
    }

    *result = frozenResult;
    return(true);
}

MeasurementVerdict Measurement_getVerdict(const MeasurementResult *result)
{
    const uint16_t failFlags = MEAS_FLAG_ADC_SATURATION |
                               MEAS_FLAG_ADC_OVERFLOW |
                               MEAS_FLAG_NO_SAMPLES;

    if((result->flags & failFlags) != 0U)
    {
        return(MEAS_VERDICT_FAIL);
    }
    if(result->flags != 0U)
    {
        return(MEAS_VERDICT_WARNING);
    }
    return(MEAS_VERDICT_PASS);
}

const char *Measurement_getVerdictName(MeasurementVerdict verdict)
{
    if(verdict == MEAS_VERDICT_PASS)
    {
        return("PASS");
    }
    if(verdict == MEAS_VERDICT_WARNING)
    {
        return("WARNING");
    }
    return("FAIL");
}

uint16_t Measurement_getLatestIlRaw(void)
{
    return(latestIlRaw);
}

uint16_t Measurement_getLatestVoRaw(void)
{
    return(latestVoRaw);
}

uint16_t Measurement_getIlZeroRaw(void)
{
    return(ilZeroRaw);
}

uint16_t Measurement_getVoZeroRaw(void)
{
    return(voZeroRaw);
}

uint32_t Measurement_getOverflowCount(void)
{
    return(overflowCount);
}

bool Measurement_isCalibrated(void)
{
    return(calibrated);
}

static void configureAdc(uint32_t base)
{
    ADC_setPrescaler(base, ADC_CLK_DIV_4_0);
    ADC_setMode(base, ADC_RESOLUTION_12BIT, ADC_MODE_SINGLE_ENDED);
    ADC_setInterruptPulseMode(base, ADC_PULSE_END_OF_CONV);
    ADC_enableConverter(base);
}

static uint16_t elapsedPwmTicks(uint16_t start, uint16_t end)
{
    const uint16_t period = Pwm_getPeriodCounts();

    if(end >= start)
    {
        return(end - start);
    }
    return((uint16_t)((period - start) + end));
}

__interrupt void adcA1ISR(void)
{
    uint16_t startTicks = EPWM_getTimeBaseCounterValue(EPWM1_BASE);
    uint16_t ilRaw = ADC_readResult(ADCCRESULT_BASE, ADC_SOC_NUMBER0);
    uint16_t voRaw = ADC_readResult(ADCARESULT_BASE, ADC_SOC_NUMBER0);
    uint16_t endTicks;
    uint16_t isrTicks;

    latestIlRaw = ilRaw;
    latestVoRaw = voRaw;

    ADC_clearInterruptStatus(ADCA_BASE, ADC_INT_NUMBER1);
    if(ADC_getInterruptOverflowStatus(ADCA_BASE, ADC_INT_NUMBER1))
    {
        overflowCount++;
        ADC_clearInterruptOverflowStatus(ADCA_BASE, ADC_INT_NUMBER1);
        ADC_clearInterruptStatus(ADCA_BASE, ADC_INT_NUMBER1);
    }

    if(calibrationActive)
    {
        calibrationIlSum += ilRaw;
        calibrationVoSum += voRaw;
        calibrationCount++;
        if(calibrationCount >= APP_ADC_CALIBRATION_SAMPLES)
        {
            ilZeroRaw = (uint16_t)((calibrationIlSum +
                       (APP_ADC_CALIBRATION_SAMPLES / 2UL)) /
                       APP_ADC_CALIBRATION_SAMPLES);
            voZeroRaw = (uint16_t)((calibrationVoSum +
                       (APP_ADC_CALIBRATION_SAMPLES / 2UL)) /
                       APP_ADC_CALIBRATION_SAMPLES);
            calibrated = true;
            calibrationActive = false;
        }
    }

    if(captureActive)
    {
        captureCount++;
        ilSum += ilRaw;
        voSum += voRaw;

        if(ilRaw < ilMin) { ilMin = ilRaw; }
        if(ilRaw > ilMax) { ilMax = ilRaw; }
        if(voRaw < voMin) { voMin = voRaw; }
        if(voRaw > voMax) { voMax = voRaw; }

        if((ilRaw >= APP_ADC_SATURATION_HIGH_RAW) ||
           (voRaw >= APP_ADC_SATURATION_HIGH_RAW))
        {
            captureFlags |= MEAS_FLAG_ADC_SATURATION;
        }

        if(calibrated &&
           (ilRaw <= (uint16_t)(ilZeroRaw + APP_IL_NEAR_ZERO_MARGIN_RAW)))
        {
            if(nearZeroConsecutive < APP_IL_NEAR_ZERO_CONSECUTIVE)
            {
                nearZeroConsecutive++;
            }
            if(nearZeroConsecutive >= APP_IL_NEAR_ZERO_CONSECUTIVE)
            {
                captureFlags |= MEAS_FLAG_IL_NEAR_ZERO;
            }
        }
        else
        {
            nearZeroConsecutive = 0U;
        }
    }

    endTicks = EPWM_getTimeBaseCounterValue(EPWM1_BASE);
    isrTicks = elapsedPwmTicks(startTicks, endTicks);
    if(isrTicks > maxIsrTicks)
    {
        maxIsrTicks = isrTicks;
    }

    Interrupt_clearACKGroup(INTERRUPT_ACK_GROUP1);
}
