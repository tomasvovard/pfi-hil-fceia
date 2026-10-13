// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "protocol.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "app_config.h"
#include "app_state.h"
#include "experiment_engine.h"
#include "measurement.h"
#include "outputs.h"
#include "pwm.h"
#include "trigger.h"
#include "uart.h"

#define PROTOCOL_LINE_BUFFER_SIZE    128U

static char lineBuffer[PROTOCOL_LINE_BUFFER_SIZE];
static uint16_t lineLength;
static bool discardingLine;

static void processLine(void);
static void sendPrefix(const char *requestId);
static void sendResponse(const char *requestId, const char *response);
static bool isValidRequestId(const char *text);
static bool parseUint32(const char *text, uint32_t *value);
static char *skipSpaces(char *text);
static void trimTrailingSpaces(char *text);
static void sendStatus(const char *requestId);
static void sendPwmStatus(const char *requestId);
static void writeUint32(uint32_t value);
static void writeLoadCode(uint16_t loadCode);
static void sendExperimentEvent(void);
static const char *triggerReasonName(TriggerReason reason);
static void sendMeasurementFlags(uint16_t flags);

void Protocol_init(void)
{
    lineLength = 0U;
    discardingLine = false;
    Uart_writeString("!EVT STATE=IDLE FW=" APP_VERSION_STRING "\n");
}

void Protocol_poll(void)
{
    uint16_t received;
    char character;

    if(Trigger_consumePulseComplete())
    {
        Uart_writeString("!EVT TRIGGER=DONE COUNT=");
        writeUint32(Trigger_getPulseCount());
        Uart_writeChar('\n');
    }

    sendExperimentEvent();

    if(Uart_hasRxError())
    {
        Uart_recoverRx();
        lineLength = 0U;
        discardingLine = false;
        Uart_writeString("!EVT UART_RX_ERROR\n");
    }

    while(Uart_isCharAvailable())
    {
        received = Uart_readChar();
        character = (char)(received & 0x00FFU);

        // Serial terminals differ in what Enter transmits. Treat CR, LF, and
        // the first character of CR+LF as a line terminator. The second one
        // sees an empty buffer and is ignored.
        if((character == '\r') || (character == '\n'))
        {
            if(discardingLine)
            {
                Uart_writeString("ERR LINE_TOO_LONG\n");
            }
            else if(lineLength > 0U)
            {
                lineBuffer[lineLength] = '\0';
                processLine();
            }

            lineLength = 0U;
            discardingLine = false;
            continue;
        }

        if(discardingLine)
        {
            continue;
        }

        if(lineLength >= (PROTOCOL_LINE_BUFFER_SIZE - 1U))
        {
            lineLength = 0U;
            discardingLine = true;
            continue;
        }

        lineBuffer[lineLength] = character;
        lineLength++;
    }
}

static void processLine(void)
{
    char *separator;
    char *requestId;
    char *command;

    trimTrailingSpaces(lineBuffer);
    if(lineBuffer[0] != '@')
    {
        Uart_writeString("ERR REQUEST_ID_REQUIRED\n");
        return;
    }

    separator = strchr(lineBuffer, ' ');
    if(separator == (char *)0)
    {
        Uart_writeString("ERR REQUEST_ID\n");
        return;
    }

    *separator = '\0';
    requestId = lineBuffer;
    if(!isValidRequestId(requestId))
    {
        Uart_writeString("ERR REQUEST_ID\n");
        return;
    }

    command = skipSpaces(separator + 1);
    trimTrailingSpaces(command);
    if(command[0] == '\0')
    {
        sendResponse(requestId, "ERR ARGUMENT");
    }
    else if(strcmp(command, "PING") == 0)
    {
        sendResponse(requestId, "OK FW=" APP_VERSION_STRING " PROTO=1");
    }
    else if(strcmp(command, "INFO") == 0)
    {
        sendResponse(requestId,
                     "OK FW=" APP_VERSION_STRING
                     " PROTO=1 TARGET=LAUNCHXL-F28379D CORE=CPU1 UART=SCIA");
    }
    else if(strcmp(command, "STATUS") == 0)
    {
        sendStatus(requestId);
    }
    else if(strcmp(command, "SAFE") == 0)
    {
        ExperimentEngine_forceSafe();
        sendResponse(requestId, "OK STATE=IDLE SAFE=1");
    }
    else if(strncmp(command, "PREPARE ", 8U) == 0)
    {
        uint32_t testId;
        char *argument = skipSpaces(command + 8U);

        if(AppState_get() != APP_STATE_IDLE)
        {
            sendResponse(requestId, "ERR STATE");
        }
        else if(!parseUint32(argument, &testId) ||
                (testId > 65535UL) ||
                !ExperimentEngine_prepare((uint16_t)testId))
        {
            sendResponse(requestId, "ERR ARGUMENT");
        }
        else
        {
            sendPrefix(requestId);
            Uart_writeString("OK STATE=PRECONDITION TEST=");
            writeUint32(testId);
            Uart_writeString(" SETTLE_US=");
            writeUint32(APP_PRECONDITION_US);
            Uart_writeChar('\n');
        }
    }
    else if(strcmp(command, "RUN") == 0)
    {
        if(!ExperimentEngine_run())
        {
            sendResponse(requestId, "ERR STATE");
        }
        else
        {
            sendPrefix(requestId);
            Uart_writeString("OK STATE=RUNNING TEST=");
            writeUint32(ExperimentEngine_getTestId());
            Uart_writeString(" PRETRIGGER_US=");
            writeUint32(APP_PRETRIGGER_US);
            Uart_writeChar('\n');
        }
    }
    else if(strcmp(command, "ABORT") == 0)
    {
        ExperimentEngine_abort();
        sendResponse(requestId, "OK STATE=IDLE SAFE=1");
    }
    else if(strcmp(command, "RESULT") == 0)
    {
        MeasurementResult result;

        if(AppState_get() != APP_STATE_DONE)
        {
            sendResponse(requestId, "ERR STATE");
        }
        else if(!Measurement_getResult(&result))
        {
            sendResponse(requestId, "ERR ADC_RESULT");
        }
        else
        {
            sendPrefix(requestId);
            Uart_writeString("OK RESULT=");
            Uart_writeString(Measurement_getVerdictName(
                             Measurement_getVerdict(&result)));
            Uart_writeString(" TEST=");
            writeUint32(ExperimentEngine_getTestId());
            Uart_writeString(" STEPS=");
            writeUint32(ExperimentEngine_getStep());
            Uart_writeString(" SAMPLES=");
            writeUint32(result.sampleCount);
            Uart_writeString(" IL_MIN_RAW=");
            writeUint32(result.ilMinRaw);
            Uart_writeString(" IL_MAX_RAW=");
            writeUint32(result.ilMaxRaw);
            Uart_writeString(" IL_MEAN_RAW=");
            writeUint32(result.ilMeanRaw);
            Uart_writeString(" VO_MIN_RAW=");
            writeUint32(result.voMinRaw);
            Uart_writeString(" VO_MAX_RAW=");
            writeUint32(result.voMaxRaw);
            Uart_writeString(" VO_MEAN_RAW=");
            writeUint32(result.voMeanRaw);
            Uart_writeString(" IL_ZERO_RAW=");
            writeUint32(result.ilZeroRaw);
            Uart_writeString(" VO_ZERO_RAW=");
            writeUint32(result.voZeroRaw);
            Uart_writeString(" ADC_OVF=");
            writeUint32(result.overflowCount);
            Uart_writeString(" ISR_MAX_TICKS=");
            writeUint32(result.maxIsrTicks);
            Uart_writeString(" FLAGS=");
            sendMeasurementFlags(result.flags);
            Uart_writeChar('\n');
        }
    }
    else if(strcmp(command, "ADC READ") == 0)
    {
        sendPrefix(requestId);
        Uart_writeString("OK IL_RAW=");
        writeUint32(Measurement_getLatestIlRaw());
        Uart_writeString(" VO_RAW=");
        writeUint32(Measurement_getLatestVoRaw());
        Uart_writeString(" CAL=");
        Uart_writeString(Measurement_isCalibrated() ? "1" : "0");
        Uart_writeString(" IL_ZERO_RAW=");
        writeUint32(Measurement_getIlZeroRaw());
        Uart_writeString(" VO_ZERO_RAW=");
        writeUint32(Measurement_getVoZeroRaw());
        Uart_writeString(" ADC_OVF=");
        writeUint32(Measurement_getOverflowCount());
        Uart_writeChar('\n');
    }
    else if(strcmp(command, "CAL ZERO") == 0)
    {
        if((AppState_get() != APP_STATE_IDLE) || Pwm_isEnabled())
        {
            sendResponse(requestId, "ERR STATE");
        }
        else if(!Measurement_calibrateZero())
        {
            sendResponse(requestId, "ERR ADC_TIMEOUT");
        }
        else
        {
            sendPrefix(requestId);
            Uart_writeString("OK CAL=ZERO SAMPLES=");
            writeUint32(APP_ADC_CALIBRATION_SAMPLES);
            Uart_writeString(" IL_ZERO_RAW=");
            writeUint32(Measurement_getIlZeroRaw());
            Uart_writeString(" VO_ZERO_RAW=");
            writeUint32(Measurement_getVoZeroRaw());
            Uart_writeChar('\n');
        }
    }
    else if(strcmp(command, "PWM ON") == 0)
    {
        if(AppState_get() != APP_STATE_IDLE)
        {
            sendResponse(requestId, "ERR STATE");
        }
        else
        {
            Pwm_enable();
            sendPwmStatus(requestId);
        }
    }
    else if(strcmp(command, "PWM OFF") == 0)
    {
        if(AppState_get() == APP_STATE_IDLE)
        {
            Pwm_forceOff();
        }
        else
        {
            // Treat an off request during a sequence as an emergency safe
            // stop; never leave the state machine running without its PWM.
            ExperimentEngine_forceSafe();
        }
        sendPwmStatus(requestId);
    }
    else if(strncmp(command, "PWM SET ", 8U) == 0)
    {
        uint32_t dutyPpm;
        char *argument = skipSpaces(command + 8U);

        if(AppState_get() != APP_STATE_IDLE)
        {
            sendResponse(requestId, "ERR STATE");
        }
        else if(!parseUint32(argument, &dutyPpm) ||
                !Pwm_setDutyPpm(dutyPpm))
        {
            sendResponse(requestId, "ERR ARGUMENT");
        }
        else
        {
            sendPwmStatus(requestId);
        }
    }
    else if(strncmp(command, "LOAD ", 5U) == 0)
    {
        char *argument = skipSpaces(command + 5U);
        uint16_t loadCode;

        if(strcmp(argument, "00") == 0)
        {
            loadCode = 0U;
        }
        else if(strcmp(argument, "01") == 0)
        {
            loadCode = 1U;
        }
        else if(strcmp(argument, "11") == 0)
        {
            loadCode = 3U;
        }
        else
        {
            sendResponse(requestId, "ERR ARGUMENT");
            return;
        }

        if((AppState_get() != APP_STATE_IDLE) || Pwm_isEnabled())
        {
            sendResponse(requestId, "ERR STATE");
        }
        else if(!Outputs_setLoadCode(loadCode))
        {
            sendResponse(requestId, "ERR ARGUMENT");
        }
        else
        {
            sendPrefix(requestId);
            Uart_writeString("OK LOAD=");
            writeLoadCode(Outputs_getLoadCode());
            Uart_writeChar('\n');
        }
    }
    else if(strcmp(command, "TRIGGER") == 0)
    {
        if(AppState_get() != APP_STATE_IDLE)
        {
            sendResponse(requestId, "ERR STATE");
        }
        else if(!Trigger_armNextPeriod())
        {
            sendResponse(requestId, "ERR BUSY");
        }
        else
        {
            sendPrefix(requestId);
            Uart_writeString("OK TRIGGER=FIRED WIDTH_US=");
            writeUint32(Trigger_getWidthUs());
            Uart_writeString(" COUNT=");
            writeUint32(Trigger_getPulseCount());
            Uart_writeChar('\n');
        }
    }
    else
    {
        sendResponse(requestId, "ERR UNKNOWN_COMMAND");
    }
}

static void sendPrefix(const char *requestId)
{
    Uart_writeString(requestId);
    Uart_writeChar(' ');
}

static void sendResponse(const char *requestId, const char *response)
{
    sendPrefix(requestId);
    Uart_writeString(response);
    Uart_writeChar('\n');
}

static bool isValidRequestId(const char *text)
{
    uint16_t index = 1U;

    if((text[0] != '@') || (text[1] == '\0'))
    {
        return(false);
    }

    while(text[index] != '\0')
    {
        if((text[index] < '0') || (text[index] > '9'))
        {
            return(false);
        }
        index++;
    }

    return(true);
}

static bool parseUint32(const char *text, uint32_t *value)
{
    uint32_t result = 0UL;
    uint16_t digit;

    if(*text == '\0')
    {
        return(false);
    }

    while(*text != '\0')
    {
        if((*text < '0') || (*text > '9'))
        {
            return(false);
        }

        digit = (uint16_t)(*text - '0');
        if((result > 429496729UL) ||
           ((result == 429496729UL) && (digit > 5U)))
        {
            return(false);
        }

        result = (result * 10UL) + digit;
        text++;
    }

    *value = result;
    return(true);
}

static char *skipSpaces(char *text)
{
    while(*text == ' ')
    {
        text++;
    }
    return(text);
}

static void trimTrailingSpaces(char *text)
{
    uint16_t length = (uint16_t)strlen(text);

    while((length > 0U) && (text[length - 1U] == ' '))
    {
        length--;
        text[length] = '\0';
    }
}

static void sendStatus(const char *requestId)
{
    sendPrefix(requestId);
    Uart_writeString("OK STATE=");
    Uart_writeString(AppState_getName());
    Uart_writeString(" SAFE=");
    Uart_writeString(AppState_isSafe() ? "1" : "0");
    Uart_writeString(" PWM=");
    Uart_writeString(Pwm_isEnabled() ? "ON" : "OFF");
    Uart_writeString(" FREQ_HZ=");
    writeUint32(Pwm_getFrequencyHz());
    Uart_writeString(" DUTY_PPM=");
    writeUint32(Pwm_getDutyPpm());
    Uart_writeString(" TRIGGER=");
    Uart_writeString(Trigger_isArmed() ? "ARMED" : "IDLE");
    Uart_writeString(" TRIGGER_COUNT=");
    writeUint32(Trigger_getPulseCount());
    Uart_writeString(" LOAD=");
    writeLoadCode(Outputs_getLoadCode());
    Uart_writeString(" TEST=");
    writeUint32(ExperimentEngine_getTestId());
    Uart_writeString(" STEP=");
    writeUint32(ExperimentEngine_getStep());
    Uart_writeString(" STEPS=");
    writeUint32(ExperimentEngine_getStepCount());
    Uart_writeString(" ADC_CAL=");
    Uart_writeString(Measurement_isCalibrated() ? "1" : "0");
    Uart_writeString(" IL_RAW=");
    writeUint32(Measurement_getLatestIlRaw());
    Uart_writeString(" VO_RAW=");
    writeUint32(Measurement_getLatestVoRaw());
    Uart_writeString(" ADC_OVF=");
    writeUint32(Measurement_getOverflowCount());
    Uart_writeChar('\n');
}

static void sendPwmStatus(const char *requestId)
{
    sendPrefix(requestId);
    Uart_writeString("OK PWM=");
    Uart_writeString(Pwm_isEnabled() ? "ON" : "OFF");
    Uart_writeString(" FREQ_HZ=");
    writeUint32(Pwm_getFrequencyHz());
    Uart_writeString(" DUTY_PPM=");
    writeUint32(Pwm_getDutyPpm());
    Uart_writeChar('\n');
}

static void writeUint32(uint32_t value)
{
    char digits[10];
    uint16_t count = 0U;

    do
    {
        digits[count] = (char)('0' + (value % 10UL));
        value /= 10UL;
        count++;
    }
    while(value != 0UL);

    while(count > 0U)
    {
        count--;
        Uart_writeChar(digits[count]);
    }
}

static void writeLoadCode(uint16_t loadCode)
{
    Uart_writeChar(((loadCode & 2U) != 0U) ? '1' : '0');
    Uart_writeChar(((loadCode & 1U) != 0U) ? '1' : '0');
}

static void sendExperimentEvent(void)
{
    ExperimentEvent event;

    if(!ExperimentEngine_consumeEvent(&event))
    {
        return;
    }

    Uart_writeString("!EVT ");
    if(event.type == EXP_EVENT_ARMED)
    {
        Uart_writeString("STATE=ARMED TEST=");
        writeUint32(event.testId);
    }
    else if(event.type == EXP_EVENT_STEP)
    {
        Uart_writeString("STEP=");
        writeUint32(event.step);
        Uart_writeString(" TEST=");
        writeUint32(event.testId);
        Uart_writeString(" TRIGGER=");
        Uart_writeString(triggerReasonName(event.trigger));
        Uart_writeString(" DUTY_PPM=");
        writeUint32(event.dutyPpm);
        Uart_writeString(" LOAD=");
        writeLoadCode(event.loadCode);
    }
    else if(event.type == EXP_EVENT_DONE)
    {
        MeasurementResult result;

        Uart_writeString("STATE=DONE RESULT=");
        if(Measurement_getResult(&result))
        {
            Uart_writeString(Measurement_getVerdictName(
                             Measurement_getVerdict(&result)));
        }
        else
        {
            Uart_writeString("FAIL");
        }
        Uart_writeString(" TEST=");
        writeUint32(event.testId);
        Uart_writeString(" STEPS=");
        writeUint32(event.step);
    }
    else if(event.type == EXP_EVENT_ABORTED)
    {
        Uart_writeString("STATE=IDLE RESULT=ABORTED TEST=");
        writeUint32(event.testId);
    }
    else
    {
        Uart_writeString("STATE=FAULT TEST=");
        writeUint32(event.testId);
        Uart_writeString(" STEP=");
        writeUint32(event.step);
    }
    Uart_writeChar('\n');
}

static const char *triggerReasonName(TriggerReason reason)
{
    if(reason == TRIGGER_DUTY)
    {
        return("DUTY");
    }
    if(reason == TRIGGER_LOAD)
    {
        return("LOAD");
    }
    return("NONE");
}

static void sendMeasurementFlags(uint16_t flags)
{
    bool wroteFlag = false;

    if(flags == 0U)
    {
        Uart_writeString("NONE");
        return;
    }

    if((flags & MEAS_FLAG_IL_NEAR_ZERO) != 0U)
    {
        Uart_writeString("IL_NEAR_ZERO");
        wroteFlag = true;
    }
    if((flags & MEAS_FLAG_ADC_SATURATION) != 0U)
    {
        if(wroteFlag) { Uart_writeChar(','); }
        Uart_writeString("ADC_SATURATION");
        wroteFlag = true;
    }
    if((flags & MEAS_FLAG_ADC_OVERFLOW) != 0U)
    {
        if(wroteFlag) { Uart_writeChar(','); }
        Uart_writeString("ADC_OVERFLOW");
        wroteFlag = true;
    }
    if((flags & MEAS_FLAG_NO_SAMPLES) != 0U)
    {
        if(wroteFlag) { Uart_writeChar(','); }
        Uart_writeString("NO_SAMPLES");
        wroteFlag = true;
    }
    if((flags & MEAS_FLAG_CAL_REQUIRED) != 0U)
    {
        if(wroteFlag) { Uart_writeChar(','); }
        Uart_writeString("CAL_REQUIRED");
    }
}
