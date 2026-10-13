// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "experiment_engine.h"

#include "app_config.h"
#include "app_state.h"
#include "measurement.h"
#include "outputs.h"
#include "pwm.h"
#include "test_presets.h"
#include "timebase.h"
#include "trigger.h"

static const TestPreset *activePreset;
static uint16_t segmentIndex;
static uint16_t completedSteps;
static uint32_t phaseStart;
static ExperimentEvent pendingEvent;

static void setEvent(ExperimentEventType type, const TestSegment *segment);
static void applyStep(const TestSegment *segment);

void ExperimentEngine_init(void)
{
    activePreset = (const TestPreset *)0;
    segmentIndex = 0U;
    completedSteps = 0U;
    pendingEvent.type = EXP_EVENT_NONE;
}

void ExperimentEngine_service(void)
{
    const TestSegment *segment;

    if((AppState_get() == APP_STATE_PRECONDITION) &&
       Timebase_elapsedUs(phaseStart, APP_PRECONDITION_US))
    {
        AppState_set(APP_STATE_ARMED);
        setEvent(EXP_EVENT_ARMED, (const TestSegment *)0);
    }
    else if(AppState_get() == APP_STATE_RUNNING)
    {
        segment = &activePreset->segments[segmentIndex];
        if(Timebase_elapsedUs(phaseStart, segment->hold_us))
        {
            segmentIndex++;
            if(segmentIndex >= activePreset->segment_count)
            {
                Measurement_finishRun();
                AppState_set(APP_STATE_DONE);
                setEvent(EXP_EVENT_DONE, (const TestSegment *)0);
            }
            else
            {
                applyStep(&activePreset->segments[segmentIndex]);
            }
        }
    }
}

bool ExperimentEngine_prepare(uint16_t testId)
{
    const TestPreset *preset;
    const TestSegment *initial;

    if(AppState_get() != APP_STATE_IDLE)
    {
        return(false);
    }

    preset = TestPresets_find(testId);
    if(preset == (const TestPreset *)0)
    {
        return(false);
    }

    initial = &preset->segments[0];
    Pwm_forceOff();
    Pwm_waitForUpdateWindow();
    (void)Pwm_setDutyPpm(initial->duty_ppm);
    (void)Outputs_setLoadCode((uint16_t)initial->load);
    Pwm_enable();

    activePreset = preset;
    segmentIndex = 0U;
    completedSteps = 0U;
    pendingEvent.type = EXP_EVENT_NONE;
    phaseStart = Timebase_now();
    AppState_set(APP_STATE_PRECONDITION);
    return(true);
}

bool ExperimentEngine_run(void)
{
    if((AppState_get() != APP_STATE_ARMED) ||
       (activePreset == (const TestPreset *)0))
    {
        return(false);
    }

    segmentIndex = 1U;
    Measurement_startRun();
    phaseStart = Timebase_now();
    AppState_set(APP_STATE_RUNNING);
    return(true);
}

void ExperimentEngine_abort(void)
{
    bool wasActive = AppState_get() != APP_STATE_IDLE;
    uint16_t abortedTestId = ExperimentEngine_getTestId();

    ExperimentEngine_forceSafe();
    if(wasActive)
    {
        pendingEvent.type = EXP_EVENT_ABORTED;
        pendingEvent.testId = abortedTestId;
        pendingEvent.step = 0U;
        pendingEvent.trigger = TRIGGER_NONE;
        pendingEvent.dutyPpm = Pwm_getDutyPpm();
        pendingEvent.loadCode = Outputs_getLoadCode();
    }
}

void ExperimentEngine_forceSafe(void)
{
    Measurement_abortRun();
    AppState_forceIdle();
    activePreset = (const TestPreset *)0;
    segmentIndex = 0U;
    completedSteps = 0U;
    pendingEvent.type = EXP_EVENT_NONE;
}

bool ExperimentEngine_consumeEvent(ExperimentEvent *event)
{
    if(pendingEvent.type == EXP_EVENT_NONE)
    {
        return(false);
    }

    *event = pendingEvent;
    pendingEvent.type = EXP_EVENT_NONE;
    return(true);
}

uint16_t ExperimentEngine_getTestId(void)
{
    return((activePreset == (const TestPreset *)0) ? 0U : activePreset->id);
}

uint16_t ExperimentEngine_getStep(void)
{
    return(completedSteps);
}

uint16_t ExperimentEngine_getStepCount(void)
{
    if(activePreset == (const TestPreset *)0)
    {
        return(0U);
    }
    return(activePreset->segment_count - 2U);
}

static void setEvent(ExperimentEventType type, const TestSegment *segment)
{
    pendingEvent.type = type;
    pendingEvent.testId = ExperimentEngine_getTestId();
    pendingEvent.step = completedSteps;
    pendingEvent.trigger = (segment == (const TestSegment *)0) ?
                           TRIGGER_NONE : segment->trigger;
    pendingEvent.dutyPpm = (segment == (const TestSegment *)0) ?
                           Pwm_getDutyPpm() : segment->duty_ppm;
    pendingEvent.loadCode = (segment == (const TestSegment *)0) ?
                            Outputs_getLoadCode() : (uint16_t)segment->load;
}

static void applyStep(const TestSegment *segment)
{
    Pwm_waitForUpdateWindow();
    if(!Pwm_setDutyPpm(segment->duty_ppm) ||
       !Outputs_setLoadCode((uint16_t)segment->load) ||
       !Trigger_armNextPeriod())
    {
        Outputs_forceSafe();
        AppState_set(APP_STATE_FAULT);
        setEvent(EXP_EVENT_FAULT, segment);
        return;
    }

    completedSteps++;
    phaseStart = Timebase_now();
    setEvent(EXP_EVENT_STEP, segment);
}
