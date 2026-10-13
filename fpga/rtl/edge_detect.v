// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// edge_detect.v
//
// Detector de flanco de subida de un ciclo de sys_clk, sobre una señal
// YA sincronizada (ver sync_2ff.v -- este modulo no sincroniza nada por
// su cuenta, para no duplicar la logica de metaestabilidad).
//////////////////////////////////////////////////////////////////////////////

module edge_detect (
    input  wire clk,
    input  wire resetn,
    input  wire d_sync,     // ya pasada por sync_2ff.v
    output wire rising      // pulso de 1 ciclo en cada flanco de subida
);

    reg d_prev;

    always @(posedge clk) begin
        if (!resetn)
            d_prev <= 1'b0;
        else
            d_prev <= d_sync;
    end

    assign rising = d_sync & ~d_prev;

endmodule
