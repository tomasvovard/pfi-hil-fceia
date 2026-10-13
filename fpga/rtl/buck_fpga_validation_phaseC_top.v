// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
`include "buck_params.vh"
//////////////////////////////////////////////////////////////////////////////
// buck_fpga_validation_phaseC_top.v
//
// Top del diseño de ensayos: modelo no ideal del convertidor buck en
// tiempo real (Ts = 200 ns), con salida por los dos DAC de la placa,
// disparo de ensayo y seleccion de carga en caliente.
//
//   - DAC0 (U5, canales C/D, TP-A02/TP-A03): iL y Vo. Al enviar solo dos
//     canales, es el que se actualiza mas rapido (2.5 us por trama).
//   - DAC1 (U13, canales A..F): Vi, VL, iO, iI, iC y Vc.
//   - Disparo de ensayo: DIO_3 como entrada, con sincronizador y detector
//     de flanco, para disparar el ILA.
//   - Seleccion de R en caliente: DIO_4/DIO_5 como entrada, codigo Gray
//     de 2 bits -> r_select_gray.v -> KR_Q_ext de buck_model.v. Permite
//     observar la transicion completa de un escalon de carga en una sola
//     captura.
//
// Los coeficientes del modelo no se escriben a mano: los genera
// matlab/modelado_rtl/r3_parametros_verilog.m en buck_params.vh.
//////////////////////////////////////////////////////////////////////////////

module buck_fpga_validation_phaseC_top #(
    // Expuestos SOLO para que el testbench pueda simular heartbeat/timeout
    // de LEDs en tiempos cortos. La instancia
    // real de sintesis no pasa estos parametros.
    parameter integer HEARTBEAT_HALF_PERIOD_CE = 2_500_000,
    parameter integer COMM_TIMEOUT_CYCLES       = 3_000_000,
    parameter integer ENABLE_AUX_DAC1           = 1
) (
    input  wire sys_clk,          // 30 MHz, PACKAGE_PIN G4

    input  wire pwm_in,           // PACKAGE_PIN A2 (PWM1A), asincrono

    output wire model_running_led, // PACKAGE_PIN P12
    output wire comm_led,          // PACKAGE_PIN P13

    // DAC0 (AD5328 U5, 4 canales con punta de prueba: C/D/E/F) — iL/Vo
    output wire dac0_din,          // PACKAGE_PIN D13
    output wire dac0_sclk,         // PACKAGE_PIN D14
    output wire dac0_sync,         // PACKAGE_PIN E13
    output wire dac0_ldac,         // PACKAGE_PIN F14

    // DAC1 (AD5328 U13, 8 canales con punta de prueba) — resto de señales.
    output wire dac1_din,          // PACKAGE_PIN J14
    output wire dac1_sclk,         // PACKAGE_PIN H13
    output wire dac1_sync,         // PACKAGE_PIN J13
    output wire dac1_ldac,         // PACKAGE_PIN L14

    // DIO: PWM/Vsw/Vx
    output wire dio_pwm_sync,      // PACKAGE_PIN L1  (DIO_0)
    output wire dio_vsw,           // PACKAGE_PIN L2  (DIO_1)
    output wire dio_vx,            // PACKAGE_PIN M1  (DIO_2)

    // DIO de ensayo, todos entrada, todos asincronos
    input  wire dio_trigger_in,    // PACKAGE_PIN A4 (LaunchPad GPIO2)
    input  wire dio_rsel_b0_in,    // PACKAGE_PIN A5 (LaunchPad GPIO3), Gray bit0
    input  wire dio_rsel_b1_in     // PACKAGE_PIN B5 (LaunchPad GPIO4), Gray bit1
);

    // ---------------------------------------------------------------
    // Reset interno.
    // ---------------------------------------------------------------
    reg [4:0] rst_cnt = 5'd0;
    reg       resetn  = 1'b0;

    always @(posedge sys_clk) begin
        if (rst_cnt != 5'd31) begin
            rst_cnt <= rst_cnt + 1'b1;
            resetn  <= 1'b0;
        end else begin
            resetn <= 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // Sincronizador de PWM.
    // ---------------------------------------------------------------
    wire pwm_sync;

    pwm_sync u_pwm_sync (
        .clk      (sys_clk),
        .resetn   (resetn),
        .pwm_in   (pwm_in),
        .pwm_sync (pwm_sync)
    );

    // ---------------------------------------------------------------
    // model_ce: 5 MHz.
    // ---------------------------------------------------------------
    wire model_ce;

    model_ce_gen #(
        .DIVIDE (6)
    ) u_model_ce_gen (
        .clk      (sys_clk),
        .resetn   (resetn),
        .model_ce (model_ce)
    );

    (* mark_debug = "true" *) reg [31:0] sample_counter;

    always @(posedge sys_clk) begin
        if (!resetn)
            sample_counter <= 32'd0;
        else if (model_ce)
            sample_counter <= sample_counter + 1'b1;
    end

    // ---------------------------------------------------------------
    // Disparo del ensayo (DIO_3) y seleccion de R en
    // caliente (DIO_4/DIO_5, codigo Gray). Ver sync_2ff.v,
    // edge_detect.v, r_select_gray.v.
    // ---------------------------------------------------------------
    wire trigger_sync, trigger_pulse;
    wire rsel_b0_sync, rsel_b1_sync;
    wire signed [31:0] KR_Q_sel;
    wire [1:0] r_select_dbg;

    sync_2ff u_sync_trigger (
        .clk (sys_clk), .resetn (resetn),
        .d_in (dio_trigger_in), .q_sync (trigger_sync)
    );
    edge_detect u_edge_trigger (
        .clk (sys_clk), .resetn (resetn),
        .d_sync (trigger_sync), .rising (trigger_pulse)
    );

    sync_2ff u_sync_rsel_b0 (
        .clk (sys_clk), .resetn (resetn),
        .d_in (dio_rsel_b0_in), .q_sync (rsel_b0_sync)
    );
    sync_2ff u_sync_rsel_b1 (
        .clk (sys_clk), .resetn (resetn),
        .d_in (dio_rsel_b1_in), .q_sync (rsel_b1_sync)
    );

    r_select_gray #(
        .W (32), .F (22)
    ) u_r_select (
        .clk           (sys_clk),
        .resetn        (resetn),
        .gray_b0_sync  (rsel_b0_sync),
        .gray_b1_sync  (rsel_b1_sync),
        .KR_Q_sel      (KR_Q_sel),
        .r_select_dbg  (r_select_dbg)
    );

    (* mark_debug = "true" *) wire dbg_trigger    = trigger_pulse;
    (* mark_debug = "true" *) wire [1:0] dbg_rsel = r_select_dbg;

    // ---------------------------------------------------------------
    // Modelo Buck. KR_Q_ext viene del selector de R.
    // ---------------------------------------------------------------
    wire signed [31:0] iL, Vo, iC, iO;

    buck_model #(
        .W (32),
        .F (22)
    ) u_buck_model (
        .clk      (sys_clk),
        .resetn   (resetn),
        .model_ce (model_ce),
        .pwm_sync (pwm_sync),
        .KR_Q_ext (KR_Q_sel),
        .iL       (iL),
        .Vo       (Vo),
        .iC       (iC),
        .iO       (iO)
    );

    // Debug taps: iC/iO no se mandan al ILA (se reconstruyen en el
    // procesamiento como iO = Vo/R e iC = iL - iO). dac_scaler.v si los
    // necesita como entrada (para derivar VL/Vc/iI y escalar iC/iO al
    // DAC1), asi que siguen existiendo como wires internos sin mark_debug.
    (* mark_debug = "true" *) wire dbg_pwm_sync = pwm_sync;
    (* mark_debug = "true" *) wire dbg_model_ce = model_ce;
    (* mark_debug = "true" *) wire signed [31:0] dbg_iL = iL;
    (* mark_debug = "true" *) wire signed [31:0] dbg_Vo = Vo;

    // ---------------------------------------------------------------
    // Escalador DAC: recibe iL/Vo/iC/iO/pwm_sync y devuelve 8 codigos
    // de 12 bits.
    // ---------------------------------------------------------------
    wire [11:0] code_Vi, code_Vo, code_VL, code_iL, code_iO, code_iI, code_iC, code_Vc;

    dac_scaler #(
        .VO_DAC_OFFSET_CODE (`BUCK_VO_DAC_OFFSET_CODE)  // compensacion de offset de Vo (ver r3_parametros_verilog.m)
    ) u_dac_scaler (
        .iL       (iL),
        .Vo       (Vo),
        .iC       (iC),
        .iO       (iO),
        .pwm_sync (pwm_sync),
        .code_Vi  (code_Vi),
        .code_Vo  (code_Vo),
        .code_VL  (code_VL),
        .code_iL  (code_iL),
        .code_iO  (code_iO),
        .code_iI  (code_iI),
        .code_iC  (code_iC),
        .code_Vc  (code_Vc)
    );

    // ---------------------------------------------------------------
    // DAC0 (U5, 4 canales con punta de prueba: C/D/E/F): iL en ch2(C,
    // TP-A02), Vo en ch3(D, TP-A03). Resto de los canales sin usar,
    // atados a 0.
    // ---------------------------------------------------------------
    wire        drv0_start, drv0_busy, drv0_done;
    wire [11:0] drv0_ch0, drv0_ch1, drv0_ch2, drv0_ch3, drv0_ch4, drv0_ch5, drv0_ch6, drv0_ch7;

    dac_scheduler u_dac_scheduler_0 (
        .clk       (sys_clk),
        .resetn    (resetn),
        .code_ch0  (12'd0),
        .code_ch1  (12'd0),
        .code_ch2  (code_iL),
        .code_ch3  (code_Vo),
        .code_ch4  (12'd0),
        .code_ch5  (12'd0),
        .code_ch6  (12'd0),
        .code_ch7  (12'd0),
        .drv_busy  (drv0_busy),
        .drv_done  (drv0_done),
        .drv_start (drv0_start),
        .drv_ch0   (drv0_ch0),
        .drv_ch1   (drv0_ch1),
        .drv_ch2   (drv0_ch2),
        .drv_ch3   (drv0_ch3),
        .drv_ch4   (drv0_ch4),
        .drv_ch5   (drv0_ch5),
        .drv_ch6   (drv0_ch6),
        .drv_ch7   (drv0_ch7)
    );

    ad5328_driver #(
        .FIRST_CHANNEL (2), // canal C: solo C/D tienen punta de prueba en DAC0
        .N_CHANNELS    (2), // C y D nada mas
        .SYNC_HIGH_CYCLES (2), // 66.7 ns >= t8=50 ns
        .LDAC_LOW_CYCLES  (1)  // 33.3 ns >= t9=20 ns
    ) u_dac0_driver (
        .clk      (sys_clk),
        .resetn   (resetn),
        .ch0_data (drv0_ch0), .ch1_data (drv0_ch1),
        .ch2_data (drv0_ch2), .ch3_data (drv0_ch3),
        .ch4_data (drv0_ch4), .ch5_data (drv0_ch5),
        .ch6_data (drv0_ch6), .ch7_data (drv0_ch7),
        .start    (drv0_start),
        .busy     (drv0_busy),
        .done     (drv0_done),
        .dac_din  (dac0_din),
        .dac_sclk (dac0_sclk),
        .dac_sync (dac0_sync),
        .dac_ldac (dac0_ldac)
    );

    // ---------------------------------------------------------------
    // DAC1 (U13): seis señales derivadas en los canales consecutivos
    // A..F. G/H quedan sin usar y no se serializan.
    // ---------------------------------------------------------------
    wire        drv1_start, drv1_busy, drv1_done;
    wire [11:0] drv1_ch0, drv1_ch1, drv1_ch2, drv1_ch3, drv1_ch4, drv1_ch5, drv1_ch6, drv1_ch7;

    generate if (ENABLE_AUX_DAC1 != 0) begin : g_aux_dac1
    dac_scheduler u_dac_scheduler_1 (
        .clk       (sys_clk),
        .resetn    (resetn),
        .code_ch0  (code_Vi),
        .code_ch1  (code_VL),
        .code_ch2  (code_iO),
        .code_ch3  (code_iI),
        .code_ch4  (code_iC),
        .code_ch5  (code_Vc),
        .code_ch6  (12'd0),
        .code_ch7  (12'd0),
        .drv_busy  (drv1_busy),
        .drv_done  (drv1_done),
        .drv_start (drv1_start),
        .drv_ch0   (drv1_ch0),
        .drv_ch1   (drv1_ch1),
        .drv_ch2   (drv1_ch2),
        .drv_ch3   (drv1_ch3),
        .drv_ch4   (drv1_ch4),
        .drv_ch5   (drv1_ch5),
        .drv_ch6   (drv1_ch6),
        .drv_ch7   (drv1_ch7)
    );

    ad5328_driver #(
        .FIRST_CHANNEL (0), // canal A
        .N_CHANNELS    (6)  // A..F: 222 ciclos/frame (~7.4 us, ~135 kHz)
    ) u_dac1_driver (
        .clk      (sys_clk),
        .resetn   (resetn),
        .ch0_data (drv1_ch0), .ch1_data (drv1_ch1),
        .ch2_data (drv1_ch2), .ch3_data (drv1_ch3),
        .ch4_data (drv1_ch4), .ch5_data (drv1_ch5),
        .ch6_data (drv1_ch6), .ch7_data (drv1_ch7),
        .start    (drv1_start),
        .busy     (drv1_busy),
        .done     (drv1_done),
        .dac_din  (dac1_din),
        .dac_sclk (dac1_sclk),
        .dac_sync (dac1_sync),
        .dac_ldac (dac1_ldac)
    );
    end else begin : g_aux_dac1_off
        assign drv1_start = 1'b0;
        assign drv1_busy  = 1'b0;
        assign drv1_done  = 1'b0;
        assign drv1_ch0 = 12'd0; assign drv1_ch1 = 12'd0;
        assign drv1_ch2 = 12'd0; assign drv1_ch3 = 12'd0;
        assign drv1_ch4 = 12'd0; assign drv1_ch5 = 12'd0;
        assign drv1_ch6 = 12'd0; assign drv1_ch7 = 12'd0;
        assign dac1_din  = 1'b0;
        assign dac1_sclk = 1'b0;
        assign dac1_sync = 1'b1;
        assign dac1_ldac = 1'b1;
    end endgenerate

    // Debug minimo del DAC0 (el rapido, el que importa para ver el
    // ensayo) para el ILA. DAC1 no se probea (ya se ve iL/Vo por DAC0 a
    // mas velocidad; agregar sus 8 codigos solo gastaria BRAM sin
    // aportar nada nuevo al analisis de un ensayo).
    (* mark_debug = "true" *) wire dbg_dac0_start = drv0_start;
    (* mark_debug = "true" *) wire dbg_dac0_busy  = drv0_busy;
    (* mark_debug = "true" *) wire dbg_dac0_done  = drv0_done;

    // ---------------------------------------------------------------
    // DIO: PWM/Vsw/Vx.
    // ---------------------------------------------------------------
    assign dio_pwm_sync = pwm_sync;
    assign dio_vsw      = ~pwm_sync;
    assign dio_vx       = pwm_sync;

    // ---------------------------------------------------------------
    // LEDs de estado.
    // ---------------------------------------------------------------
    status_leds #(
        .HEARTBEAT_HALF_PERIOD_CE (HEARTBEAT_HALF_PERIOD_CE),
        .COMM_TIMEOUT_CYCLES      (COMM_TIMEOUT_CYCLES)
    ) u_status_leds (
        .clk               (sys_clk),
        .resetn            (resetn),
        .model_ce          (model_ce),
        .pwm_sync          (pwm_sync),
        .model_running_led (model_running_led),
        .comm_led          (comm_led)
    );

endmodule
