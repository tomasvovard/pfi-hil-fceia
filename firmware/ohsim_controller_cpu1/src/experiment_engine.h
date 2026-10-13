// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef EXPERIMENT_ENGINE_H
#define EXPERIMENT_ENGINE_H

#include <stdbool.h>
#include <stdint.h>

#include "test_types.h"

typedef enum
{
    EXP_EVENT_NONE = 0,
    EXP_EVENT_ARMED,
    EXP_EVENT_STEP,
    EXP_EVENT_DONE,
    EXP_EVENT_ABORTED,
    EXP_EVENT_FAULT
} ExperimentEventType;

typedef struct
{
    ExperimentEventType type;
    uint16_t testId;
    uint16_t step;
    TriggerReason trigger;
    uint32_t dutyPpm;
    uint16_t loadCode;
} ExperimentEvent;

void ExperimentEngine_init(void);
void ExperimentEngine_service(void);
bool ExperimentEngine_prepare(uint16_t testId);
bool ExperimentEngine_run(void);
void ExperimentEngine_abort(void);
void ExperimentEngine_forceSafe(void);
bool ExperimentEngine_consumeEvent(ExperimentEvent *event);
uint16_t ExperimentEngine_getTestId(void);
uint16_t ExperimentEngine_getStep(void);
uint16_t ExperimentEngine_getStepCount(void);

#endif
