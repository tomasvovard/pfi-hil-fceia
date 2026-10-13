// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#include "uart.h"

#include "driverlib.h"
#include "device.h"

#include "app_config.h"

void Uart_init(void)
{
    GPIO_setMasterCore(DEVICE_GPIO_PIN_SCIRXDA, GPIO_CORE_CPU1);
    GPIO_setPinConfig(DEVICE_GPIO_CFG_SCIRXDA);
    GPIO_setDirectionMode(DEVICE_GPIO_PIN_SCIRXDA, GPIO_DIR_MODE_IN);
    GPIO_setPadConfig(DEVICE_GPIO_PIN_SCIRXDA, GPIO_PIN_TYPE_STD);
    GPIO_setQualificationMode(DEVICE_GPIO_PIN_SCIRXDA, GPIO_QUAL_ASYNC);

    GPIO_setMasterCore(DEVICE_GPIO_PIN_SCITXDA, GPIO_CORE_CPU1);
    GPIO_setPinConfig(DEVICE_GPIO_CFG_SCITXDA);
    GPIO_setDirectionMode(DEVICE_GPIO_PIN_SCITXDA, GPIO_DIR_MODE_OUT);
    GPIO_setPadConfig(DEVICE_GPIO_PIN_SCITXDA, GPIO_PIN_TYPE_STD);
    GPIO_setQualificationMode(DEVICE_GPIO_PIN_SCITXDA, GPIO_QUAL_ASYNC);

    SCI_performSoftwareReset(SCIA_BASE);
    SCI_setConfig(SCIA_BASE, DEVICE_LSPCLK_FREQ, APP_UART_BAUD,
                  SCI_CONFIG_WLEN_8 | SCI_CONFIG_STOP_ONE |
                  SCI_CONFIG_PAR_NONE);
    SCI_resetChannels(SCIA_BASE);
    SCI_resetRxFIFO(SCIA_BASE);
    SCI_resetTxFIFO(SCIA_BASE);
    SCI_clearInterruptStatus(SCIA_BASE, SCI_INT_TXFF | SCI_INT_RXFF);
    SCI_enableFIFO(SCIA_BASE);
    SCI_enableModule(SCIA_BASE);
    SCI_performSoftwareReset(SCIA_BASE);
}

bool Uart_isCharAvailable(void)
{
    return(SCI_getRxFIFOStatus(SCIA_BASE) != SCI_FIFO_RX0);
}

uint16_t Uart_readChar(void)
{
    return(SCI_readCharNonBlocking(SCIA_BASE));
}

bool Uart_hasRxError(void)
{
    return((SCI_getRxStatus(SCIA_BASE) & SCI_RXSTATUS_ERROR) != 0U);
}

void Uart_recoverRx(void)
{
    SCI_performSoftwareReset(SCIA_BASE);
    SCI_resetRxFIFO(SCIA_BASE);
}

void Uart_writeChar(char character)
{
    SCI_writeCharBlockingFIFO(SCIA_BASE, (uint16_t)character);
}

void Uart_writeString(const char *text)
{
    while(*text != '\0')
    {
        Uart_writeChar(*text);
        text++;
    }
}
