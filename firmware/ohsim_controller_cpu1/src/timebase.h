// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef TIMEBASE_H
#define TIMEBASE_H

#include <stdbool.h>
#include <stdint.h>

void Timebase_init(void);
uint32_t Timebase_now(void);
bool Timebase_elapsedUs(uint32_t start, uint32_t intervalUs);

#endif
