// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "timebase.h"

#include "driverlib.h"
#include "device.h"

#define TIMEBASE_TICKS_PER_US  (DEVICE_SYSCLK_FREQ / 1000000UL)

void Timebase_init(void)
{
    CPUTimer_stopTimer(CPUTIMER0_BASE);
    CPUTimer_setPeriod(CPUTIMER0_BASE, 0xFFFFFFFFUL);
    CPUTimer_setPreScaler(CPUTIMER0_BASE, 0U);
    CPUTimer_setEmulationMode(CPUTIMER0_BASE,
                              CPUTIMER_EMULATIONMODE_RUNFREE);
    CPUTimer_startTimer(CPUTIMER0_BASE);
}

uint32_t Timebase_now(void)
{
    return(CPUTimer_getTimerCount(CPUTIMER0_BASE));
}

bool Timebase_elapsedUs(uint32_t start, uint32_t intervalUs)
{
    uint32_t elapsedTicks = start - Timebase_now();
    uint32_t requiredTicks = intervalUs * TIMEBASE_TICKS_PER_US;

    return(elapsedTicks >= requiredTicks);
}
