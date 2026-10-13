// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "pwm.h"

#include "driverlib.h"
#include "device.h"

#include "app_config.h"

#define PWM_TBCLK_HZ       (DEVICE_SYSCLK_FREQ / 2UL)
#define PWM_PERIOD_COUNTS  (PWM_TBCLK_HZ / APP_PWM_FREQUENCY_HZ)

static uint32_t currentDutyPpm;
static bool pwmEnabled;

static uint16_t dutyPpmToCompare(uint32_t dutyPpm);

void Pwm_init(void)
{
    SysCtl_disablePeripheral(SYSCTL_PERIPH_CLK_TBCLKSYNC);
    SysCtl_setEPWMClockDivider(SYSCTL_EPWMCLK_DIV_2);

    EPWM_setTimeBaseCounterMode(EPWM1_BASE, EPWM_COUNTER_MODE_UP);
    EPWM_setClockPrescaler(EPWM1_BASE, EPWM_CLOCK_DIVIDER_1,
                          EPWM_HSCLOCK_DIVIDER_1);
    EPWM_setTimeBasePeriod(EPWM1_BASE, (uint16_t)(PWM_PERIOD_COUNTS - 1UL));
    EPWM_setTimeBaseCounter(EPWM1_BASE, 0U);
    EPWM_setPhaseShift(EPWM1_BASE, 0U);
    EPWM_disablePhaseShiftLoad(EPWM1_BASE);
    EPWM_setSyncOutPulseMode(EPWM1_BASE,
                             EPWM_SYNC_OUT_PULSE_ON_COUNTER_ZERO);
    EPWM_setEmulationMode(EPWM1_BASE, EPWM_EMULATION_FREE_RUN);

    currentDutyPpm = APP_PWM_DEFAULT_DUTY_PPM;
    EPWM_setCounterCompareShadowLoadMode(EPWM1_BASE,
                                         EPWM_COUNTER_COMPARE_A,
                                         EPWM_COMP_LOAD_ON_CNTR_ZERO);
    EPWM_setCounterCompareValue(EPWM1_BASE, EPWM_COUNTER_COMPARE_A,
                                dutyPpmToCompare(currentDutyPpm));

    EPWM_setActionQualifierAction(EPWM1_BASE, EPWM_AQ_OUTPUT_A,
                                  EPWM_AQ_OUTPUT_HIGH,
                                  EPWM_AQ_OUTPUT_ON_TIMEBASE_ZERO);
    EPWM_setActionQualifierAction(EPWM1_BASE, EPWM_AQ_OUTPUT_A,
                                  EPWM_AQ_OUTPUT_LOW,
                                  EPWM_AQ_OUTPUT_ON_TIMEBASE_UP_CMPA);

    // A software one-shot trip is the authoritative OFF state. It overrides
    // the action qualifier immediately and remains latched until PWM ON.
    EPWM_disableTripZoneAdvAction(EPWM1_BASE);
    EPWM_setTripZoneAction(EPWM1_BASE, EPWM_TZ_ACTION_EVENT_TZA,
                           EPWM_TZ_ACTION_LOW);
    EPWM_forceTripZoneEvent(EPWM1_BASE, EPWM_TZ_FORCE_EVENT_OST);
    pwmEnabled = false;

    // Switch GPIO0 to the peripheral only after ePWM1A is already tripped low.
    GPIO_setMasterCore(APP_PWM_GPIO, GPIO_CORE_CPU1);
    GPIO_setPinConfig(GPIO_0_EPWM1A);
    GPIO_setPadConfig(APP_PWM_GPIO, GPIO_PIN_TYPE_STD);
    GPIO_setDirectionMode(APP_PWM_GPIO, GPIO_DIR_MODE_OUT);

    SysCtl_enablePeripheral(SYSCTL_PERIPH_CLK_TBCLKSYNC);
}

bool Pwm_setDutyPpm(uint32_t dutyPpm)
{
    if((dutyPpm < APP_PWM_MIN_DUTY_PPM) ||
       (dutyPpm > APP_PWM_MAX_DUTY_PPM))
    {
        return(false);
    }

    currentDutyPpm = dutyPpm;
    EPWM_setCounterCompareValue(EPWM1_BASE, EPWM_COUNTER_COMPARE_A,
                                dutyPpmToCompare(dutyPpm));
    return(true);
}

void Pwm_enable(void)
{
    // While tripped, AQ remains low until the next ZERO event establishes the
    // first complete pulse. Compare updates are also committed at ZERO.
    EPWM_clearTripZoneFlag(EPWM1_BASE, EPWM_TZ_FLAG_OST);
    pwmEnabled = true;
}

void Pwm_forceOff(void)
{
    EPWM_forceTripZoneEvent(EPWM1_BASE, EPWM_TZ_FORCE_EVENT_OST);
    pwmEnabled = false;
}

bool Pwm_isEnabled(void)
{
    return(pwmEnabled);
}

uint32_t Pwm_getDutyPpm(void)
{
    return(currentDutyPpm);
}

uint32_t Pwm_getFrequencyHz(void)
{
    return(APP_PWM_FREQUENCY_HZ);
}

uint32_t Pwm_getTbclkHz(void)
{
    return(PWM_TBCLK_HZ);
}

uint16_t Pwm_getPeriodCounts(void)
{
    return((uint16_t)PWM_PERIOD_COUNTS);
}

void Pwm_waitForUpdateWindow(void)
{
    uint16_t counter;

    // Leave at least 5 us on either side of ZERO. This prevents a group of
    // shadow-register writes from straddling a load event.
    do
    {
        counter = EPWM_getTimeBaseCounterValue(EPWM1_BASE);
    }
    while((counter < 500U) ||
          (counter > ((uint16_t)PWM_PERIOD_COUNTS - 500U)));
}

static uint16_t dutyPpmToCompare(uint32_t dutyPpm)
{
    uint64_t scaledCounts = ((uint64_t)PWM_PERIOD_COUNTS * dutyPpm) +
                            500000ULL;

    return((uint16_t)(scaledCounts / 1000000ULL));
}
