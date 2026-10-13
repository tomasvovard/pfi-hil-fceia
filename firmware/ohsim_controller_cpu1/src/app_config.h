// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include <stdint.h>

#define APP_VERSION_MAJOR          0U
#define APP_VERSION_MINOR          6U
#define APP_VERSION_PATCH          1U
#define APP_VERSION_STRING         "0.6.1"
#define APP_PROTOCOL_VERSION       1U

#define APP_PWM_GPIO               0U
#define APP_TRIGGER_GPIO           2U
#define APP_LOAD_B0_GPIO           3U
#define APP_LOAD_B1_GPIO           4U

#define APP_PWM_FREQUENCY_HZ       10000UL
#define APP_PWM_DEFAULT_DUTY_PPM   450000UL
#define APP_PWM_MIN_DUTY_PPM       10000UL
#define APP_PWM_MAX_DUTY_PPM       990000UL
#define APP_TRIGGER_WIDTH_US       1UL
#define APP_UART_BAUD              115200UL
#define APP_PRECONDITION_US        1000000UL
#define APP_PRETRIGGER_US          2000UL

#define APP_ADC_SAMPLE_RATE_HZ              APP_PWM_FREQUENCY_HZ
#define APP_ADC_ACQPS                       31U
#define APP_ADC_CALIBRATION_SAMPLES         256UL
#define APP_ADC_CALIBRATION_TIMEOUT_US      100000UL
#define APP_ADC_SATURATION_HIGH_RAW         4094U
#define APP_IL_NEAR_ZERO_MARGIN_RAW         64U
#define APP_IL_NEAR_ZERO_CONSECUTIVE        3U

#define APP_MAIN_LOOP_PERIOD_US    100UL

#endif
