// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// model_ce_gen.v
//
// Genera 'model_ce': un pulso de UN ciclo de sys_clk cada DIVIDE ciclos
// (default DIVIDE=6), usado como clock-enable del modelo Buck.
//
// Con sys_clk = 30 MHz y DIVIDE = 6:
//   f_model = 30 MHz / 6 = 5 MHz  ->  Ts_model = 200 ns = 0.2 us
// (valor validado en MATLAB).
//
// Es un contador libre en el UNICO dominio de reloj real (sys_clk): no se
// genera ningun reloj derivado por logica combinacional, y 'model_ce' es
// una señal de habilitacion (clock enable), no un clock. Esto es exactamente
// el patron que ya se uso y valido en ad5328_driver.v para dividir sys_clk
// sin crear un segundo dominio de reloj.
//////////////////////////////////////////////////////////////////////////////

module model_ce_gen #(
    parameter integer DIVIDE = 6
) (
    input  wire clk,       // sys_clk, 30 MHz
    input  wire resetn,
    output reg  model_ce   // pulso de 1 ciclo cada DIVIDE ciclos de clk
);

    localparam integer CNT_W = (DIVIDE <= 1) ? 1 : $clog2(DIVIDE);

    reg [CNT_W-1:0] cnt;

    always @(posedge clk) begin
        if (!resetn) begin
            cnt      <= {CNT_W{1'b0}};
            model_ce <= 1'b0;
        end else if (cnt == DIVIDE - 1) begin
            cnt      <= {CNT_W{1'b0}};
            model_ce <= 1'b1;
        end else begin
            cnt      <= cnt + 1'b1;
            model_ce <= 1'b0;
        end
    end

endmodule
