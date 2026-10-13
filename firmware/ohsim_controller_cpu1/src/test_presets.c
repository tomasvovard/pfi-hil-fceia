// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "test_presets.h"

#define ARRAY_COUNT(values) ((uint16_t)(sizeof(values) / sizeof(values[0])))

static const TestSegment test1a[] =
{
    {450000UL, 0UL,      LOAD_16P6_OHM, TRIGGER_NONE, SEGMENT_PRECONDITION},
    {450000UL, 2000UL,   LOAD_16P6_OHM, TRIGGER_NONE, SEGMENT_PRETRIGGER},
    {460000UL, 332000UL, LOAD_16P6_OHM, TRIGGER_DUTY, SEGMENT_STEP}
};

static const TestSegment test1b[] =
{
    {460000UL, 0UL,      LOAD_16P6_OHM, TRIGGER_NONE, SEGMENT_PRECONDITION},
    {460000UL, 2000UL,   LOAD_16P6_OHM, TRIGGER_NONE, SEGMENT_PRETRIGGER},
    {450000UL, 332000UL, LOAD_16P6_OHM, TRIGGER_DUTY, SEGMENT_STEP}
};

static const TestSegment test2[] =
{
    {300000UL, 0UL,      LOAD_25_OHM,   TRIGGER_NONE, SEGMENT_PRECONDITION},
    {300000UL, 2000UL,   LOAD_25_OHM,   TRIGGER_NONE, SEGMENT_PRETRIGGER},
    {300000UL, 332000UL, LOAD_16P6_OHM, TRIGGER_LOAD, SEGMENT_STEP}
};

static const TestSegment test3a[] =
{
    {800000UL, 0UL,      LOAD_25_OHM, TRIGGER_NONE, SEGMENT_PRECONDITION},
    {800000UL, 2000UL,   LOAD_25_OHM, TRIGGER_NONE, SEGMENT_PRETRIGGER},
    {810000UL, 600000UL, LOAD_25_OHM, TRIGGER_DUTY, SEGMENT_STEP}
};

static const TestSegment test3b[] =
{
    {810000UL, 0UL,      LOAD_25_OHM, TRIGGER_NONE, SEGMENT_PRECONDITION},
    {810000UL, 2000UL,   LOAD_25_OHM, TRIGGER_NONE, SEGMENT_PRETRIGGER},
    {800000UL, 600000UL, LOAD_25_OHM, TRIGGER_DUTY, SEGMENT_STEP}
};

static const TestSegment test4a[] =
{
    {700000UL, 0UL,      LOAD_50_OHM,   TRIGGER_NONE, SEGMENT_PRECONDITION},
    {700000UL, 2000UL,   LOAD_50_OHM,   TRIGGER_NONE, SEGMENT_PRETRIGGER},
    {700000UL, 600000UL, LOAD_25_OHM,   TRIGGER_LOAD, SEGMENT_STEP}
};

static const TestSegment test4b[] =
{
    {700000UL, 0UL,      LOAD_25_OHM,   TRIGGER_NONE, SEGMENT_PRECONDITION},
    {700000UL, 2000UL,   LOAD_25_OHM,   TRIGGER_NONE, SEGMENT_PRETRIGGER},
    {700000UL, 332000UL, LOAD_16P6_OHM, TRIGGER_LOAD, SEGMENT_STEP}
};

static const TestSegment test5[] =
{
    {700000UL, 0UL,      LOAD_16P6_OHM, TRIGGER_NONE, SEGMENT_PRECONDITION},
    {700000UL, 2000UL,   LOAD_16P6_OHM, TRIGGER_NONE, SEGMENT_PRETRIGGER},
    {700000UL, 600000UL, LOAD_25_OHM,   TRIGGER_LOAD, SEGMENT_STEP}
};

static const TestPreset presets[] =
{
    {11U, "e1a_duty_045_046", test1a, ARRAY_COUNT(test1a)},
    {12U, "e1b_duty_046_045", test1b, ARRAY_COUNT(test1b)},
    {2U, "load_25_16p6", test2, ARRAY_COUNT(test2)},
    {31U, "e3a_duty_080_081", test3a, ARRAY_COUNT(test3a)},
    {32U, "e3b_duty_081_080", test3b, ARRAY_COUNT(test3b)},
    {41U, "e4a_load_50_25", test4a, ARRAY_COUNT(test4a)},
    {42U, "e4b_load_25_16p6", test4b, ARRAY_COUNT(test4b)},
    {5U, "load_16p6_25", test5, ARRAY_COUNT(test5)}
};

const TestPreset *TestPresets_find(uint16_t id)
{
    uint16_t index;

    for(index = 0U; index < ARRAY_COUNT(presets); index++)
    {
        if(presets[index].id == id)
        {
            return(&presets[index]);
        }
    }
    return((const TestPreset *)0);
}

uint16_t TestPresets_count(void)
{
    return(ARRAY_COUNT(presets));
}
