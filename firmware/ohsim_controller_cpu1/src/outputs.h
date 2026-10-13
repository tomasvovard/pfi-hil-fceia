// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef OUTPUTS_H
#define OUTPUTS_H

#include <stdbool.h>
#include <stdint.h>

void Outputs_initSafe(void);
void Outputs_initTimed(void);
void Outputs_forceSafe(void);
bool Outputs_areSafe(void);
bool Outputs_setLoadCode(uint16_t loadCode);
uint16_t Outputs_getLoadCode(void);

#endif
