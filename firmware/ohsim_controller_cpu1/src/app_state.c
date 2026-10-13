// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "app_state.h"

#include "outputs.h"

static AppState currentState;

void AppState_init(void)
{
    currentState = APP_STATE_IDLE;
}

void AppState_forceIdle(void)
{
    Outputs_forceSafe();
    currentState = APP_STATE_IDLE;
}

void AppState_set(AppState state)
{
    currentState = state;
}

AppState AppState_get(void)
{
    return(currentState);
}

const char *AppState_getName(void)
{
    static const char * const names[] =
    {
        "IDLE",
        "PRECONDITION",
        "ARMED",
        "RUNNING",
        "DONE",
        "FAULT"
    };

    return(names[(unsigned int)currentState]);
}

bool AppState_isSafe(void)
{
    return((currentState == APP_STATE_IDLE) && Outputs_areSafe());
}
