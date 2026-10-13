// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "driverlib.h"
#include "device.h"

#include "app_config.h"
#include "app_state.h"
#include "experiment_engine.h"
#include "measurement.h"
#include "outputs.h"
#include "protocol.h"
#include "pwm.h"
#include "trigger.h"
#include "timebase.h"
#include "uart.h"

static void initStatusLedOff(void);

void main(void)
{
    Device_init();
    Device_initGPIO();

    Outputs_initSafe();
    initStatusLedOff();

    Interrupt_initModule();
    Interrupt_initVectorTable();

    Pwm_init();
    Trigger_init();
    Outputs_initTimed();
    Timebase_init();
    Measurement_init();

    AppState_init();
    ExperimentEngine_init();
    Uart_init();
    Protocol_init();

    EINT;
    ERTM;
    Measurement_startSampling();

    for(;;)
    {
        ExperimentEngine_service();
        Protocol_poll();

        DEVICE_DELAY_US(APP_MAIN_LOOP_PERIOD_US);
    }
}

static void initStatusLedOff(void)
{
    GPIO_setPadConfig(DEVICE_GPIO_PIN_LED1, GPIO_PIN_TYPE_STD);
    GPIO_setDirectionMode(DEVICE_GPIO_PIN_LED1, GPIO_DIR_MODE_OUT);
    /* The LaunchPad LED is active low. Keep it dark during measurements. */
    GPIO_writePin(DEVICE_GPIO_PIN_LED1, 1U);
}
