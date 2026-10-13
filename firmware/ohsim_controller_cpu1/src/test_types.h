// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef TEST_TYPES_H
#define TEST_TYPES_H

#include <stdint.h>

typedef enum
{
    LOAD_16P6_OHM = 0x0U,
    LOAD_25_OHM   = 0x1U,
    LOAD_HOLD     = 0x2U,
    LOAD_50_OHM   = 0x3U
} LoadGrayCode;

typedef enum
{
    TRIGGER_NONE = 0U,
    TRIGGER_DUTY = 1U,
    TRIGGER_LOAD = 2U
} TriggerReason;

typedef enum
{
    SEGMENT_PRECONDITION = 0U,
    SEGMENT_PRETRIGGER   = 1U,
    SEGMENT_STEP         = 2U
} TestSegmentKind;

typedef struct
{
    uint32_t duty_ppm;
    uint32_t hold_us;
    LoadGrayCode load;
    TriggerReason trigger;
    TestSegmentKind kind;
} TestSegment;

typedef struct
{
    uint16_t id;
    const char *name;
    const TestSegment *segments;
    uint16_t segment_count;
} TestPreset;

#endif

