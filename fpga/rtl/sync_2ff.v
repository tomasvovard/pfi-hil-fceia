// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// sync_2ff.v
//
// Sincronizador generico de dos flip-flops, mismo patron que pwm_sync.v
// (dedicado solo a PWM) para las señales digitales
// EXTERNAS del ensayo: el pulso de disparo del ensayo y los 2
// bits de seleccion de R en codigo Gray. Todas son asincronas respecto
// de sys_clk (vienen de un DIO conectado a un DSP/AWG/pulsador externo).
//
//   d_in -> FF1 -> FF2(=q_sync)
//
// Los dos flip-flops se marcan ASYNC_REG por el mismo motivo que en
// pwm_sync.v (colocacion fisica cercana, exclusion de analisis de
// setup/hold entre d_in y FF1, que es inherentemente asincrono).
//////////////////////////////////////////////////////////////////////////////

module sync_2ff (
    input  wire clk,       // sys_clk, 30 MHz
    input  wire resetn,
    input  wire d_in,      // asincrono
    (* ASYNC_REG = "TRUE" *) output reg q_sync   // sincronizado a clk
);

    (* ASYNC_REG = "TRUE" *) reg d_ff1;

    always @(posedge clk) begin
        if (!resetn) begin
            d_ff1   <= 1'b0;
            q_sync  <= 1'b0;
        end else begin
            d_ff1   <= d_in;
            q_sync  <= d_ff1;
        end
    end

endmodule
