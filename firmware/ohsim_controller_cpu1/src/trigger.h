// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef TRIGGER_H
#define TRIGGER_H

#include <stdbool.h>
#include <stdint.h>

void Trigger_init(void);
bool Trigger_armNextPeriod(void);
void Trigger_forceLow(void);
bool Trigger_isArmed(void);
bool Trigger_consumePulseComplete(void);
uint32_t Trigger_getWidthUs(void);
uint32_t Trigger_getPulseCount(void);

#endif
