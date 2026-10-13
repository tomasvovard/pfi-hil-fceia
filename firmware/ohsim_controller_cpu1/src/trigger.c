// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "trigger.h"

#include "driverlib.h"

#include "app_config.h"
#include "pwm.h"

static volatile bool triggerArmed;
static volatile bool pulseComplete;
static uint16_t pulseWidthCounts;
static uint32_t pulseCount;

void Trigger_init(void)
{
    uint32_t widthCounts;

    SysCtl_disablePeripheral(SYSCTL_PERIPH_CLK_TBCLKSYNC);

    widthCounts = (Pwm_getTbclkHz() / 1000000UL) *
                  APP_TRIGGER_WIDTH_US;
    pulseWidthCounts = (uint16_t)widthCounts;

    EPWM_setTimeBaseCounterMode(EPWM2_BASE, EPWM_COUNTER_MODE_UP);
    EPWM_setClockPrescaler(EPWM2_BASE, EPWM_CLOCK_DIVIDER_1,
                          EPWM_HSCLOCK_DIVIDER_1);
    EPWM_setTimeBasePeriod(EPWM2_BASE, Pwm_getPeriodCounts() - 1U);
    EPWM_setTimeBaseCounter(EPWM2_BASE, 0U);
    EPWM_setPhaseShift(EPWM2_BASE, 0U);
    EPWM_enablePhaseShiftLoad(EPWM2_BASE);
    EPWM_setSyncOutPulseMode(EPWM2_BASE,
                             EPWM_SYNC_OUT_PULSE_ON_EPWMxSYNCIN);
    EPWM_setEmulationMode(EPWM2_BASE, EPWM_EMULATION_FREE_RUN);

    EPWM_disableCounterCompareShadowLoadMode(EPWM2_BASE,
                                             EPWM_COUNTER_COMPARE_A);
    EPWM_setCounterCompareValue(EPWM2_BASE, EPWM_COUNTER_COMPARE_A,
                                pulseWidthCounts);
    EPWM_setActionQualifierAction(EPWM2_BASE, EPWM_AQ_OUTPUT_A,
                                  EPWM_AQ_OUTPUT_HIGH,
                                  EPWM_AQ_OUTPUT_ON_TIMEBASE_ZERO);
    EPWM_setActionQualifierAction(EPWM2_BASE, EPWM_AQ_OUTPUT_A,
                                  EPWM_AQ_OUTPUT_LOW,
                                  EPWM_AQ_OUTPUT_ON_TIMEBASE_UP_CMPA);

    EPWM_disableTripZoneAdvAction(EPWM2_BASE);
    EPWM_setTripZoneAction(EPWM2_BASE, EPWM_TZ_ACTION_EVENT_TZA,
                           EPWM_TZ_ACTION_LOW);
    EPWM_setTripZoneAction(EPWM2_BASE, EPWM_TZ_ACTION_EVENT_TZB,
                           EPWM_TZ_ACTION_DISABLE);
    EPWM_forceTripZoneEvent(EPWM2_BASE, EPWM_TZ_FORCE_EVENT_OST);

    triggerArmed = false;
    pulseComplete = false;
    pulseCount = 0UL;

    // GPIO2 changes ownership only after the Trip Zone is latched low.
    GPIO_setMasterCore(APP_TRIGGER_GPIO, GPIO_CORE_CPU1);
    GPIO_setPinConfig(GPIO_2_EPWM2A);
    GPIO_setPadConfig(APP_TRIGGER_GPIO, GPIO_PIN_TYPE_STD);
    GPIO_setDirectionMode(APP_TRIGGER_GPIO, GPIO_DIR_MODE_OUT);

    SysCtl_enablePeripheral(SYSCTL_PERIPH_CLK_TBCLKSYNC);
}

bool Trigger_armNextPeriod(void)
{
    uint16_t previousCounter;
    uint16_t currentCounter;

    if(triggerArmed)
    {
        return(false);
    }

    // If called during this cycle's pulse window, wait until its AQ state is
    // low before releasing the trip. The next ZERO then creates one full,
    // hardware-timed pulse rather than a partial asynchronous one.
    while(EPWM_getTimeBaseCounterValue(EPWM2_BASE) <= pulseWidthCounts)
    {
    }

    pulseComplete = false;
    triggerArmed = true;
    EPWM_clearTripZoneFlag(EPWM2_BASE, EPWM_TZ_FLAG_OST);

    // Wait for the next synchronized period boundary. ePWM2A rises there in
    // hardware; no CPU instruction determines the rising-edge instant.
    previousCounter = EPWM_getTimeBaseCounterValue(EPWM2_BASE);
    do
    {
        currentCounter = EPWM_getTimeBaseCounterValue(EPWM2_BASE);
        if(currentCounter < previousCounter)
        {
            break;
        }
        previousCounter = currentCounter;
    }
    while(true);

    // Compare A drives the output low exactly at pulseWidthCounts. Polling
    // only decides when to re-latch the one-shot trip, and finishes long
    // before the following 100 us period boundary.
    while(EPWM_getTimeBaseCounterValue(EPWM2_BASE) < pulseWidthCounts)
    {
    }

    EPWM_forceTripZoneEvent(EPWM2_BASE, EPWM_TZ_FORCE_EVENT_OST);
    triggerArmed = false;
    pulseComplete = true;
    pulseCount++;
    return(true);
}

void Trigger_forceLow(void)
{
    EPWM_forceTripZoneEvent(EPWM2_BASE, EPWM_TZ_FORCE_EVENT_OST);
    triggerArmed = false;
    pulseComplete = false;
}

bool Trigger_isArmed(void)
{
    return(triggerArmed);
}

bool Trigger_consumePulseComplete(void)
{
    bool wasComplete = pulseComplete;

    pulseComplete = false;
    return(wasComplete);
}

uint32_t Trigger_getWidthUs(void)
{
    return(APP_TRIGGER_WIDTH_US);
}

uint32_t Trigger_getPulseCount(void)
{
    return(pulseCount);
}
