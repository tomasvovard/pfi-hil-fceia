// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef TEST_PRESETS_H
#define TEST_PRESETS_H

#include <stdint.h>

#include "test_types.h"

const TestPreset *TestPresets_find(uint16_t id);
uint16_t TestPresets_count(void);

#endif
