// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef PWM_H
#define PWM_H

#include <stdbool.h>
#include <stdint.h>

void Pwm_init(void);
bool Pwm_setDutyPpm(uint32_t dutyPpm);
void Pwm_enable(void);
void Pwm_forceOff(void);
bool Pwm_isEnabled(void);
uint32_t Pwm_getDutyPpm(void);
uint32_t Pwm_getFrequencyHz(void);
uint32_t Pwm_getTbclkHz(void);
uint16_t Pwm_getPeriodCounts(void);
void Pwm_waitForUpdateWindow(void);

#endif
