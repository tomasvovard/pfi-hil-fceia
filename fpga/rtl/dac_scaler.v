// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// dac_scaler.v
//
// Deriva las 8 señales físicas de interés a partir del estado del modelo
// Buck (Q32.22) y las escala a códigos de 12 bits sin signo para el
// AD5328. Modulo PURAMENTE COMBINACIONAL: no tiene reloj, no maneja SPI,
// no maneja timing de DAC — esa responsabilidad es de dac_scheduler.v
// (que es quien toma el "snapshot coherente" de estos 8 codigos al
// arrancar cada frame). No modifica ni depende de detalles internos de
// buck_v1_0.v: recibe unicamente iL/Vo/iC/iO/pwm_sync, las mismas
// señales que ya expone buck_fpga_validation_phaseC_top.v con mark_debug.
//
// -----------------------------------------------------------------------
// 1) Señales derivadas (Q32.22):
//
//   Vi = VIN_Q                              (constante, 40 V nominal)
//   Vc = Vo                                 (Buck ideal: Vc == Vo)
//   VL = pwm_sync ? (Vi - Vo) : (-Vo)        (tension ideal del inductor,
//                                             sin las perdidas del nucleo;
//                                             solo para la salida auxiliar)
//   iI = pwm_sync ? iL : 0
//
// -----------------------------------------------------------------------
// 2) Escalado a 12 bits, redondeo al nearest,
//    saturacion ANTES de escalar (nunca se produce un codigo fuera de
//    0..4095):
//
//   Unipolar (Vi, Vo, Vc):   0..40 V   -> code 0..4095
//   Bipolar  (VL):          -40..+40V  -> code 0..4095 (centro ~2048)
//   Unipolar (iL, iO, iI):   0..2.5 A  -> code 0..4095
//   Bipolar  (iC):        -0.75..+0.75A-> code 0..4095 (centro ~2048)
//
// -----------------------------------------------------------------------
// 3) Sin divisor runtime: cada mapeo es matematicamente
//
//      code = round( numerator * 4095 / D )
//
//    con D constante conocido en tiempo de diseño (D=Xmax para
//    unipolar, D=2*Xmax para bipolar tras el offset). Se implementa
//    como multiplicacion por un reciproco de punto fijo precalculado
//    (K_INT, 40 bits fraccionarios) seguida de un shift, NUNCA un
//    divisor generico:
//
//      code = (numerator * K_INT + 2^39) >>> 40
//
//    K_INT = round(4095 * 2^40 / D), calculado en Python y verificado
//    de forma EXHAUSTIVA (los 4096 limites de codigo + 2M muestras
//    aleatorias + bordes) contra la formula de referencia exacta
//    round(numerator*4095/D) para cada uno de los 4 mapeos: 0
//    discrepancias en todos los casos. El shift de 40 bits deja margen
//    mas que suficiente (error teorico maximo ~6e-4 codigos, >>1 LSB)
//    para los rangos de 'numerator' de este diseño (maximo ~2^29).
//////////////////////////////////////////////////////////////////////////////

module dac_scaler #(
    // Compensacion del offset de cero del DAC en el canal Vo: se resta este
    // codigo (12 bits) antes de enviarlo, de modo que la salida analogica del
    // DAC quede compensada en el rango util. No elimina un offset analogico
    // a codigo cero: el DAC unipolar no puede producir codigos negativos.
    // Lo calcula r3_parametros_verilog.m; 0 = sin compensacion (default).
    parameter [11:0] VO_DAC_OFFSET_CODE = 12'd0
) (
    input  wire signed [31:0] iL,   // Q32.22
    input  wire signed [31:0] Vo,   // Q32.22
    input  wire signed [31:0] iC,   // Q32.22 (no se usa para derivar, pasa directo a escala)
    input  wire signed [31:0] iO,   // Q32.22
    input  wire                pwm_sync,

    output wire [11:0] code_Vi,
    output wire [11:0] code_Vo,
    output wire [11:0] code_VL,
    output wire [11:0] code_iL,
    output wire [11:0] code_iO,
    output wire [11:0] code_iI,
    output wire [11:0] code_iC,
    output wire [11:0] code_Vc
);

    // ---------------------------------------------------------------
    // Coeficientes del modelo (mismo valor que BUCK_VIN_Q de buck_params.vh;
    // se repite aca como localparam explicito porque dac_scaler.v no
    // debe depender de la jerarquia interna de buck_model.v/buck_v1_0.v).
    // ---------------------------------------------------------------
    localparam signed [31:0] VIN_Q = 32'sd167772160; // 40.000000000 V

    // ---------------------------------------------------------------
    // 1) Señales derivadas
    // ---------------------------------------------------------------
    wire signed [31:0] Vi_q = VIN_Q;
    wire signed [31:0] Vc_q = Vo;
    wire signed [31:0] VL_q = pwm_sync ? (VIN_Q - Vo) : (-Vo);
    wire signed [31:0] iI_q = pwm_sync ? iL : 32'sd0;

    // ---------------------------------------------------------------
    // 2) Constantes de escalado (derivacion en la cabecera).
    //    Formato:
    //    Xmax_Q = limite en Q32.22, K_INT = reciproco de 4095/D en Q40.
    // ---------------------------------------------------------------

    // Unipolar 0..40V (Vi, Vo, Vc): D = 40*2^22 = 167 772 160
    localparam signed [31:0] V_XMAX_Q = 32'sd167772160;
    localparam [63:0]        V_K_INT  = 64'd26836992;

    // Bipolar +-40V (VL): D = 2*40*2^22 = 335 544 320
    localparam signed [31:0] VL_XMAX_Q = 32'sd167772160;
    localparam [63:0]        VL_K_INT  = 64'd13418496;

    // Unipolar 0..2.5A (iL, iO, iI): D = 2.5*2^22 = 10 485 760
    localparam signed [31:0] I_XMAX_Q = 32'sd10485760;
    localparam [63:0]        I_K_INT  = 64'd429391872;

    // Bipolar +-0.75A (iC): D = 2*0.75*2^22 = 6 291 456
    localparam signed [31:0] IC_XMAX_Q = 32'sd3145728;
    localparam [63:0]        IC_K_INT  = 64'd715653120;

    // ---------------------------------------------------------------
    // Funciones de escalado (puramente combinacionales). 'numerator'
    // siempre no-negativo por construccion (ya saturado / ya
    // desplazado a [0, D]), asi que toda la aritmetica interna es
    // unsigned de 64 bits: sin ambiguedad de signo, sin necesidad de
    // shift aritmetico.
    // ---------------------------------------------------------------
    function automatic [11:0] scale_unipolar(
        input signed [31:0] x,
        input signed [31:0] xmax,
        input        [63:0] k_int
    );
        reg [31:0] sat;
        reg [63:0] prod;
        begin
            if (x < 0)          sat = 32'd0;
            else if (x > xmax)  sat = xmax;
            else                sat = x;

            prod = ({32'd0, sat} * k_int) + 64'd549755813888; // +2^39 (redondeo)
            scale_unipolar = prod[51:40];
        end
    endfunction

    function automatic [11:0] scale_bipolar(
        input signed [31:0] x,
        input signed [31:0] xmax,   // limite POSITIVO (D = 2*xmax)
        input        [63:0] k_int
    );
        reg signed [31:0] sat;
        reg        [31:0] offset;
        reg        [63:0] prod;
        begin
            if (x < -xmax)      sat = -xmax;
            else if (x > xmax)  sat = xmax;
            else                sat = x;

            offset = sat + xmax; // ahora en [0, 2*xmax], siempre no-negativo
            prod   = ({32'd0, offset} * k_int) + 64'd549755813888; // +2^39
            scale_bipolar = prod[51:40];
        end
    endfunction

    assign code_Vi = scale_unipolar(Vi_q, V_XMAX_Q, V_K_INT);
    assign code_Vc = scale_unipolar(Vc_q, V_XMAX_Q, V_K_INT);

    // Vo con compensacion del offset de cero del DAC (resta y satura a 0).
    wire [11:0] code_Vo_raw = scale_unipolar(Vo, V_XMAX_Q, V_K_INT);
    assign code_Vo = (code_Vo_raw > VO_DAC_OFFSET_CODE) ?
                     (code_Vo_raw - VO_DAC_OFFSET_CODE) : 12'd0;

    assign code_VL = scale_bipolar(VL_q, VL_XMAX_Q, VL_K_INT);

    assign code_iL = scale_unipolar(iL,   I_XMAX_Q, I_K_INT);
    assign code_iO = scale_unipolar(iO,   I_XMAX_Q, I_K_INT);
    assign code_iI = scale_unipolar(iI_q, I_XMAX_Q, I_K_INT);

    assign code_iC = scale_bipolar(iC, IC_XMAX_Q, IC_K_INT);

endmodule
