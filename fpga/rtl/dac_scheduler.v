// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// dac_scheduler.v
//
// Dispara actualizaciones continuas de un ad5328_driver.v a la maxima
// tasa que permite el driver (2.5 us por trama en DAC0, 7.4 us en DAC1), SIN
// acoplar 'start' a 'model_ce' (el modelo corre a 5 MHz, el DAC no).
//
// Responsabilidad UNICA de este modulo: tomar un snapshot coherente de
// los 8 codigos de 12 bits (todos calculados a partir del MISMO instante
// del modelo) justo antes de arrancar cada frame, y manejar el
// protocolo start/busy/done sin iniciar nunca una transaccion nueva
// mientras busy=1. No genera SPI, no conoce el protocolo AD5328 (eso es
// ad5328_driver.v) y no hace la cuenta de escalado (eso es
// dac_scaler.v, puramente combinacional).
//
// Bucle:
//   IDLE: si busy=0 -> capturar snapshot de los 8 codigos actuales,
//         pulsar start (1 ciclo), pasar a BUSY.
//   BUSY: esperar 'done' (fin del frame completo, incluye el pulso de
//         LDAC de los canales enviados) -> volver a IDLE.
//
// Como IDLE vuelve a evaluar 'busy' inmediatamente (ya en 0, porque
// 'done' solo se levanta cuando busy ya volvio a bajar), el siguiente
// frame arranca en el primer ciclo posible: actualizacion continua,
// tasa de frame determinada unicamente por cuanto tarda el driver, no
// por ningun temporizador externo.
//////////////////////////////////////////////////////////////////////////////

module dac_scheduler (
    input  wire        clk,
    input  wire        resetn,

    // Codigos de 12 bits ya escalados (salida de dac_scaler.v),
    // actualizandose continuamente en tiempo real junto con el modelo.
    input  wire [11:0] code_ch0,
    input  wire [11:0] code_ch1,
    input  wire [11:0] code_ch2,
    input  wire [11:0] code_ch3,
    input  wire [11:0] code_ch4,
    input  wire [11:0] code_ch5,
    input  wire [11:0] code_ch6,
    input  wire [11:0] code_ch7,

    // Interfaz hacia ad5328_driver.v (instanciado en el top)
    input  wire        drv_busy,
    input  wire        drv_done,
    output reg          drv_start,
    output reg  [11:0] drv_ch0,
    output reg  [11:0] drv_ch1,
    output reg  [11:0] drv_ch2,
    output reg  [11:0] drv_ch3,
    output reg  [11:0] drv_ch4,
    output reg  [11:0] drv_ch5,
    output reg  [11:0] drv_ch6,
    output reg  [11:0] drv_ch7
);

    localparam S_IDLE = 1'b0;
    localparam S_BUSY = 1'b1;

    reg state;

    always @(posedge clk) begin
        if (!resetn) begin
            state     <= S_IDLE;
            drv_start <= 1'b0;
            drv_ch0   <= 12'd0;
            drv_ch1   <= 12'd0;
            drv_ch2   <= 12'd0;
            drv_ch3   <= 12'd0;
            drv_ch4   <= 12'd0;
            drv_ch5   <= 12'd0;
            drv_ch6   <= 12'd0;
            drv_ch7   <= 12'd0;
        end else begin
            drv_start <= 1'b0; // pulso de 1 ciclo por defecto

            case (state)
                S_IDLE: begin
                    if (!drv_busy) begin
                        // Snapshot coherente: los 8 canales quedan
                        // capturados en el MISMO flanco de reloj, todos
                        // derivados del mismo instante del modelo.
                        drv_ch0 <= code_ch0;
                        drv_ch1 <= code_ch1;
                        drv_ch2 <= code_ch2;
                        drv_ch3 <= code_ch3;
                        drv_ch4 <= code_ch4;
                        drv_ch5 <= code_ch5;
                        drv_ch6 <= code_ch6;
                        drv_ch7 <= code_ch7;
                        drv_start <= 1'b1;
                        state     <= S_BUSY;
                    end
                end

                S_BUSY: begin
                    if (drv_done)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
