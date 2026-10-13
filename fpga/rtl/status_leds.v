// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// status_leds.v
//
// Dos LEDs de estado, sin logica de proyecto (solo diagnostico visual):
//
// MODEL_RUNNING: heartbeat de ~1 Hz derivado de 'model_ce'. Prueba a
//   simple vista que el modelo esta corriendo (sale de reset y el
//   generador de model_ce sigue pulsando a 5 MHz).
//
// COMM_LED: indicador temporal de actividad PWM. Se enciende al detectar
//   un flanco (subida o bajada) en 'pwm_sync', y permanece encendido
//   mientras sigan llegando flancos dentro de una ventana de ~100 ms; se
//   apaga si no hay flancos nuevos durante esa ventana. Es un indicador
//   provisorio de "hay PWM llegando", no reemplaza captura por ILA.
//////////////////////////////////////////////////////////////////////////////

module status_leds #(
    parameter integer HEARTBEAT_HALF_PERIOD_CE = 2_500_000, // 0.5 s @ model_ce=5MHz -> heartbeat 1 Hz
    parameter integer COMM_TIMEOUT_CYCLES       = 3_000_000  // 100 ms @ sys_clk=30MHz
) (
    input  wire clk,       // sys_clk, 30 MHz
    input  wire resetn,
    input  wire model_ce,
    input  wire pwm_sync,

    output reg  model_running_led,
    output reg  comm_led
);

    // ---------------------------------------------------------------
    // MODEL_RUNNING: toggle cada HEARTBEAT_HALF_PERIOD_CE pulsos de
    // model_ce. Con el default (2,500,000 pulsos @ 5 MHz = 0.5 s por
    // semiperiodo) el LED queda parpadeando a 1 Hz exacto.
    // ---------------------------------------------------------------
    localparam integer HB_CNT_W = $clog2(HEARTBEAT_HALF_PERIOD_CE);
    reg [HB_CNT_W-1:0] hb_cnt;

    always @(posedge clk) begin
        if (!resetn) begin
            hb_cnt            <= {HB_CNT_W{1'b0}};
            model_running_led <= 1'b0;
        end else if (model_ce) begin
            if (hb_cnt == HEARTBEAT_HALF_PERIOD_CE - 1) begin
                hb_cnt            <= {HB_CNT_W{1'b0}};
                model_running_led <= ~model_running_led;
            end else begin
                hb_cnt <= hb_cnt + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------
    // COMM_LED: se enciende ante cualquier flanco de pwm_sync (ya
    // sincronizado, ver pwm_sync.v) y se apaga si pasan
    // COMM_TIMEOUT_CYCLES ciclos de sys_clk (~100 ms) sin un flanco
    // nuevo. Cada flanco reinicia la ventana.
    // ---------------------------------------------------------------
    localparam integer COMM_CNT_W = $clog2(COMM_TIMEOUT_CYCLES);
    reg pwm_sync_d;
    reg [COMM_CNT_W-1:0] comm_cnt;

    wire pwm_edge = pwm_sync ^ pwm_sync_d;

    always @(posedge clk) begin
        if (!resetn) begin
            pwm_sync_d <= 1'b0;
            comm_cnt   <= {COMM_CNT_W{1'b0}};
            comm_led   <= 1'b0;
        end else begin
            pwm_sync_d <= pwm_sync;

            if (pwm_edge) begin
                comm_cnt <= {COMM_CNT_W{1'b0}};
                comm_led <= 1'b1;
            end else if (comm_led) begin
                if (comm_cnt == COMM_TIMEOUT_CYCLES - 1) begin
                    comm_led <= 1'b0; // ventana vencida sin flancos nuevos
                end else begin
                    comm_cnt <= comm_cnt + 1'b1;
                end
            end
        end
    end

endmodule
