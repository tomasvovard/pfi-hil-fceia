// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef APP_STATE_H
#define APP_STATE_H

#include <stdbool.h>

typedef enum
{
    APP_STATE_IDLE = 0,
    APP_STATE_PRECONDITION,
    APP_STATE_ARMED,
    APP_STATE_RUNNING,
    APP_STATE_DONE,
    APP_STATE_FAULT
} AppState;

void AppState_init(void);
void AppState_forceIdle(void);
void AppState_set(AppState state);
AppState AppState_get(void);
const char *AppState_getName(void);
bool AppState_isSafe(void);

#endif
