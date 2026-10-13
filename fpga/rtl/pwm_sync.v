// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// pwm_sync.v
//
// Sincronizador de dos flip-flops para llevar la señal PWM externa
// (asincrona respecto de sys_clk) al dominio de sys_clk de forma segura
// frente a metaestabilidad.
//
//   pwm_in -> FF1 -> FF2(=pwm_sync)
//
// Latencia: 1 a 2 ciclos de sys_clk (33.3-66.7 ns @ 30 MHz) hasta que un
// flanco de pwm_in se refleja en pwm_sync, dependiendo de la fase relativa
// entre pwm_in y sys_clk. El modelo Buck NUNCA debe leer pwm_in
// directamente: siempre pwm_sync.
//
// Ambos flip-flops se marcan con el atributo ASYNC_REG para que Vivado:
//  - los ubique fisicamente cerca uno del otro (reduce la probabilidad de
//    metaestabilidad al minimizar el skew entre ambos);
//  - los excluya de analisis de setup/hold normales entre pwm_in y FF1
//    (esa transicion es inherentemente asincrona, no se puede timear).
//////////////////////////////////////////////////////////////////////////////

module pwm_sync (
    input  wire clk,       // sys_clk, 30 MHz
    input  wire resetn,
    input  wire pwm_in,    // asincrono, PACKAGE_PIN A2 (PWM1A)
    (* ASYNC_REG = "TRUE" *) output reg pwm_sync   // sincronizado a clk, listo para usar en el modelo
);

    (* ASYNC_REG = "TRUE" *) reg pwm_ff1;

    always @(posedge clk) begin
        if (!resetn) begin
            pwm_ff1  <= 1'b0;
            pwm_sync <= 1'b0;
        end else begin
            pwm_ff1  <= pwm_in;
            pwm_sync <= pwm_ff1;
        end
    end

endmodule
