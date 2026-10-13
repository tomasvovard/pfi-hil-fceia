// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
`include "buck_params.vh"
//////////////////////////////////////////////////////////////////////////////
// r_select_gray.v
//
// Selecciona en caliente cual de 3 coeficientes KR_Q (1/R, Q32.22)
// alimenta al modelo Buck, segun 2 bits YA SINCRONIZADOS (ver
// sync_2ff.v) que llegan de DIO_4/DIO_5 en codigo Gray:
//
//   {b1,b0} = 00 -> R = 16.6 ohm (estado de reset)
//   {b1,b0} = 01 -> R = 25   ohm
//   {b1,b0} = 11 -> R = 50   ohm
//   {b1,b0} = 10 -> NO USADO. Se mantiene el ultimo codigo valido en vez
//                   de mapear a cualquier R: en una transicion REAL entre
//                   dos codigos vecinos de la secuencia de ensayo
//                   (16.6<->25<->50) nunca deberian cambiar los dos bits
//                   a la vez, pero si el controlador externo no
//                   conmutara ambos GPIO exactamente en el mismo ciclo,
//                   preferimos un ciclo de mas en el valor anterior a un
//                   coeficiente indefinido.
//
// Por que codigo Gray y no binario: en binario, 25->50 (01->10) cambia
// LOS DOS bits a la vez, y una diferencia de sub-ciclo entre ambos GPIO
// externos podria pasar transitoriamente por 11 (=50 ohm) o 00 (=16.6
// ohm) -- un valor de R completamente equivocado, no solo "el anterior
// un instante de mas". En Gray, toda la secuencia real de los ensayos
// (16.6<->25<->50, nunca salta directo de 16.6 a 50) cambia un solo bit
// por transicion, asi que el peor caso de desalineacion entre los dos
// GPIO es quedarse un ciclo de mas en el valor viejo -- nunca ver un
// codigo intermedio invalido.
//
// La salida queda registrada (1 ciclo de latencia sys_clk extra antes de
// llegar a buck_model.v): irrelevante para este uso, R cambia a la
// escala de tiempo de un DSP/AWG externo, no a la de sys_clk.
//////////////////////////////////////////////////////////////////////////////

module r_select_gray #(
    parameter integer W = 32,
    parameter integer F = 22
) (
    input  wire              clk,
    input  wire              resetn,
    input  wire               gray_b0_sync,  // DIO_4, ya sincronizado
    input  wire               gray_b1_sync,  // DIO_5, ya sincronizado

    output reg  signed [W-1:0] KR_Q_sel,      // hacia buck_model.v
    output reg  [1:0]          r_select_dbg   // codigo Gray activo, para el ILA
);

    // ---------------------------------------------------------------
    // Coeficientes KR_Q = 1/R en Q32.22, definidos en buck_params.vh
    // (generado por matlab/modelado_rtl/r3_parametros_verilog.m):
    //
    //   KR_Q(16.6) = round((1/16.6)  * 2^22) = 252669  (err=0.0000%)
    //   KR_Q(25)   = round((1/25)    * 2^22) = 167772  (err=-0.0001%)
    //   KR_Q(50)   = round((1/50)    * 2^22) = 83886   (err=-0.0001%)
    // ---------------------------------------------------------------
    localparam signed [W-1:0] KR_Q_16p6 = `BUCK_KR_16P6_Q;
    localparam signed [W-1:0] KR_Q_25   = `BUCK_KR_25_Q;
    localparam signed [W-1:0] KR_Q_50   = `BUCK_KR_50_Q;

    always @(posedge clk) begin
        if (!resetn) begin
            KR_Q_sel     <= KR_Q_16p6; // arranca en el codigo 00
            r_select_dbg <= 2'b00;
        end else begin
            case ({gray_b1_sync, gray_b0_sync})
                2'b00: begin KR_Q_sel <= KR_Q_16p6; r_select_dbg <= 2'b00; end
                2'b01: begin KR_Q_sel <= KR_Q_25;   r_select_dbg <= 2'b01; end
                2'b11: begin KR_Q_sel <= KR_Q_50;   r_select_dbg <= 2'b11; end
                default: begin
                    // 2'b10, no usado: retiene el ultimo valor valido.
                    KR_Q_sel     <= KR_Q_sel;
                    r_select_dbg <= r_select_dbg;
                end
            endcase
        end
    end

endmodule
