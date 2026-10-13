// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

#ifndef UART_H
#define UART_H

#include <stdbool.h>
#include <stdint.h>

void Uart_init(void);
bool Uart_isCharAvailable(void);
uint16_t Uart_readChar(void);
bool Uart_hasRxError(void);
void Uart_recoverRx(void);
void Uart_writeChar(char character);
void Uart_writeString(const char *text);

#endif
