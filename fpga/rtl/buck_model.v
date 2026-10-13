// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
`include "buck_params.vh"
//////////////////////////////////////////////////////////////////////////////
// buck_model.v
//
// Wrapper del modelo no ideal del convertidor buck. Instancia el nucleo
// numerico buck_v1_0.v y le agrega la inductancia dependiente de la
// corriente. El 1/R activo llega por el puerto KR_Q_ext desde
// r_select_gray.v, que permite cambiar la carga en caliente.
//
// VIN_Q, KL*_Q, KC_Q y las perdidas (Vsw, Vd, RL) se incluyen desde
// buck_params.vh, generado por matlab/modelado_rtl/r3_parametros_verilog.m
// a partir de matlab/cfg/buck_params.m. No se editan coeficientes
// numericos en este wrapper.
//
// -----------------------------------------------------------------------
// Inductancia dependiente de la corriente:
//   La bobina del banco (Bourns 2300LL-102) tiene una L(I) marcada. Se
//   modela 1/L como una RECTA en iL, limitada inferiormente por KL_MIN_Q
//   (L <= L maxima de senal chica):
//       Ts/L(iL)  =  max( KL0_Q + (KL_SLOPE_Q * iL) >>> F , KL_MIN_Q )
//   Para L constante, MATLAB genera KL_SLOPE_Q = 0 y KL0_Q = Ts/L.
//   iL es la muestra anterior (Ts = 200 ns): el retardo de un paso es
//   despreciable frente a cuanto cambia iL por paso.
//
// -----------------------------------------------------------------------
// Formato de punto fijo: signed, W=32, F=22 (Q32.22).
//   valor_real = codigo_signed / 2^22
//////////////////////////////////////////////////////////////////////////////

module buck_model #(
    parameter integer W = 32,  // model_data_width  (ancho total, signed)
    parameter integer F = 22   // model_decimal_width (bits fraccionarios)
) (
    input  wire             clk,       // sys_clk, 30 MHz
    input  wire             resetn,
    input  wire             model_ce,  // pulso de 1 ciclo cada 6 clocks (5 MHz, Ts=0.2us)
    input  wire             pwm_sync,  // PWM ya sincronizado a clk (ver pwm_sync.v)

    input  wire signed [W-1:0] KR_Q_ext, // 1/R activo, ya seleccionado (ver r_select_gray.v)

    output wire signed [W-1:0] iL,     // corriente de inductor, Q32.22
    output wire signed [W-1:0] Vo,     // tension de salida,     Q32.22
    output wire signed [W-1:0] iC,     // corriente de capacitor, Q32.22
    output wire signed [W-1:0] iO      // corriente de salida,    Q32.22
);

    // ---------------------------------------------------------------
    // Coeficientes generados desde MATLAB (ver cabecera).
    // ---------------------------------------------------------------
    localparam signed [W-1:0] VIN_Q = `BUCK_VIN_Q;
    localparam signed [W-1:0] KC_Q  = `BUCK_KC_Q;
    localparam signed [W-1:0] VSW_Q = `BUCK_VSW_Q;
    localparam signed [W-1:0] VD_Q  = `BUCK_VD_Q;
    localparam signed [W-1:0] RL_Q  = `BUCK_RL_Q;

    // Recta 1/L: Ts/L(iL) = KL0_Q + (KL_SLOPE_Q * iL) >>> F, saturada a
    // inferiormente por KL_MIN_Q (L <= 1 mH). No hay piso artificial de L.
    // Con KL_SLOPE_Q = 0 queda L constante = Ts/(KL0_Q/2^F).
    localparam signed [W-1:0] KL0_Q      = `BUCK_KL0_Q;
    localparam signed [W-1:0] KL_SLOPE_Q = `BUCK_KL_SLOPE_Q;
    localparam signed [W-1:0] KL_MIN_Q   = `BUCK_KL_MIN_Q;

    wire signed [(2*W)-1:0] kl_slope_full = iL * KL_SLOPE_Q;
    wire signed [W-1:0]     kl_slope_term = kl_slope_full >>> F;
    wire signed [W-1:0]     kl_unclamped  = KL0_Q + kl_slope_term;
    wire signed [W-1:0]     kl_var =
          (kl_unclamped < KL_MIN_Q) ? KL_MIN_Q : kl_unclamped;

    // Nucleo numerico con caidas y resistencia serie.
    buck_v1_0 #(
        .model_data_width    (W),
        .model_decimal_width (F)
    ) u_buck (
        .aclk             (clk),
        .resetn           (resetn),
        .clock_enable     (model_ce),

        .pwm              (pwm_sync),
        .input_voltage    (VIN_Q),
        .period_inductor  (kl_var),
        .period_capacitor (KC_Q),
        .inverse_resistor (KR_Q_ext),
        .switch_drop      (VSW_Q),
        .diode_drop       (VD_Q),
        .series_resistance(RL_Q),

        .inductor_current (iL),
        .capacitor_current(iC),
        .output_current   (iO),
        .output_voltage   (Vo)
    );

endmodule
