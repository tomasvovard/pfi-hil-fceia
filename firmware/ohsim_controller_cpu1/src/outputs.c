// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "outputs.h"

#include "driverlib.h"

#include "app_config.h"
#include "pwm.h"
#include "trigger.h"

static uint16_t currentLoadCode;
static uint16_t triggerLevel;

static void forceLoadBit(uint32_t base,
                         EPWM_ActionQualifierOutputModule output,
                         bool high);

void Outputs_initSafe(void)
{
    static const uint32_t outputPins[] =
    {
        APP_PWM_GPIO,
        APP_TRIGGER_GPIO,
        APP_LOAD_B0_GPIO,
        APP_LOAD_B1_GPIO
    };
    uint16_t index;

    GPIO_setPinConfig(GPIO_0_GPIO0);
    GPIO_setPinConfig(GPIO_2_GPIO2);
    GPIO_setPinConfig(GPIO_3_GPIO3);
    GPIO_setPinConfig(GPIO_4_GPIO4);

    for(index = 0U; index < (sizeof(outputPins) / sizeof(outputPins[0])); index++)
    {
        // Set the output latch before enabling the driver to avoid a high glitch.
        GPIO_writePin(outputPins[index], 0U);
        GPIO_setPadConfig(outputPins[index], GPIO_PIN_TYPE_STD);
        GPIO_setDirectionMode(outputPins[index], GPIO_DIR_MODE_OUT);
    }

    currentLoadCode = 0U;
    triggerLevel = 0U;
}

void Outputs_initTimed(void)
{
    SysCtl_disablePeripheral(SYSCTL_PERIPH_CLK_TBCLKSYNC);

    // GPIO3 is ePWM2B. ePWM2A is already the synchronized trigger. Begin in
    // immediate-low mode, then use shadow-at-ZERO for atomic load steps.
    EPWM_setActionQualifierContSWForceShadowMode(
        EPWM2_BASE, EPWM_AQ_SW_IMMEDIATE_LOAD);
    forceLoadBit(EPWM2_BASE, EPWM_AQ_OUTPUT_B, false);

    // ePWM3 follows the ePWM1 -> ePWM2 sync chain and carries load bit 1.
    EPWM_setTimeBaseCounterMode(EPWM3_BASE, EPWM_COUNTER_MODE_UP);
    EPWM_setClockPrescaler(EPWM3_BASE, EPWM_CLOCK_DIVIDER_1,
                          EPWM_HSCLOCK_DIVIDER_1);
    EPWM_setTimeBasePeriod(EPWM3_BASE, Pwm_getPeriodCounts() - 1U);
    EPWM_setTimeBaseCounter(EPWM3_BASE, 0U);
    EPWM_setPhaseShift(EPWM3_BASE, 0U);
    EPWM_enablePhaseShiftLoad(EPWM3_BASE);
    EPWM_setSyncOutPulseMode(EPWM3_BASE,
                             EPWM_SYNC_OUT_PULSE_ON_EPWMxSYNCIN);
    EPWM_setEmulationMode(EPWM3_BASE, EPWM_EMULATION_FREE_RUN);
    EPWM_setActionQualifierContSWForceShadowMode(
        EPWM3_BASE, EPWM_AQ_SW_IMMEDIATE_LOAD);
    forceLoadBit(EPWM3_BASE, EPWM_AQ_OUTPUT_A, false);

    GPIO_setMasterCore(APP_LOAD_B0_GPIO, GPIO_CORE_CPU1);
    GPIO_setPinConfig(GPIO_3_EPWM2B);
    GPIO_setPadConfig(APP_LOAD_B0_GPIO, GPIO_PIN_TYPE_STD);
    GPIO_setDirectionMode(APP_LOAD_B0_GPIO, GPIO_DIR_MODE_OUT);

    GPIO_setMasterCore(APP_LOAD_B1_GPIO, GPIO_CORE_CPU1);
    GPIO_setPinConfig(GPIO_4_EPWM3A);
    GPIO_setPadConfig(APP_LOAD_B1_GPIO, GPIO_PIN_TYPE_STD);
    GPIO_setDirectionMode(APP_LOAD_B1_GPIO, GPIO_DIR_MODE_OUT);

    EPWM_setActionQualifierContSWForceShadowMode(
        EPWM2_BASE, EPWM_AQ_SW_SH_LOAD_ON_CNTR_ZERO);
    EPWM_setActionQualifierContSWForceShadowMode(
        EPWM3_BASE, EPWM_AQ_SW_SH_LOAD_ON_CNTR_ZERO);
    currentLoadCode = 0U;

    SysCtl_enablePeripheral(SYSCTL_PERIPH_CLK_TBCLKSYNC);
}

void Outputs_forceSafe(void)
{
    Pwm_forceOff();
    Trigger_forceLow();
    GPIO_writePin(APP_TRIGGER_GPIO, 0U);

    // SAFE must not wait for a PWM boundary.
    EPWM_setActionQualifierContSWForceShadowMode(
        EPWM2_BASE, EPWM_AQ_SW_IMMEDIATE_LOAD);
    EPWM_setActionQualifierContSWForceShadowMode(
        EPWM3_BASE, EPWM_AQ_SW_IMMEDIATE_LOAD);
    forceLoadBit(EPWM2_BASE, EPWM_AQ_OUTPUT_B, false);
    forceLoadBit(EPWM3_BASE, EPWM_AQ_OUTPUT_A, false);
    EPWM_setActionQualifierContSWForceShadowMode(
        EPWM2_BASE, EPWM_AQ_SW_SH_LOAD_ON_CNTR_ZERO);
    EPWM_setActionQualifierContSWForceShadowMode(
        EPWM3_BASE, EPWM_AQ_SW_SH_LOAD_ON_CNTR_ZERO);
    currentLoadCode = 0U;
    triggerLevel = 0U;
}

bool Outputs_areSafe(void)
{
    return(!Pwm_isEnabled() && !Trigger_isArmed() &&
           (triggerLevel == 0U) &&
           (currentLoadCode == 0U));
}

bool Outputs_setLoadCode(uint16_t loadCode)
{
    if((loadCode != 0U) && (loadCode != 1U) && (loadCode != 3U))
    {
        return(false);
    }

    // These writes update shadow controls. Both physical bits take effect at
    // the next synchronized ZERO event, alongside a pending PWM compare.
    forceLoadBit(EPWM2_BASE, EPWM_AQ_OUTPUT_B,
                 (loadCode & 1U) != 0U);
    forceLoadBit(EPWM3_BASE, EPWM_AQ_OUTPUT_A,
                 (loadCode & 2U) != 0U);
    currentLoadCode = loadCode;
    return(true);
}

uint16_t Outputs_getLoadCode(void)
{
    return(currentLoadCode);
}

static void forceLoadBit(uint32_t base,
                         EPWM_ActionQualifierOutputModule output,
                         bool high)
{
    EPWM_setActionQualifierContSWForceAction(
        base, output,
        high ? EPWM_AQ_SW_OUTPUT_HIGH : EPWM_AQ_SW_OUTPUT_LOW);
}
