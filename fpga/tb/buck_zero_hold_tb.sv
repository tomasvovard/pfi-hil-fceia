// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps

// Regression for the safe, unenergized state. With the nonideal diode drop,
// an unrestricted CCM equation would integrate a negative current whenever
// PWM=0. The physical diode must block that reverse current.
module buck_zero_hold_tb;
    localparam integer W = 32;
    localparam integer F = 22;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg resetn = 1'b0;
    reg pwm = 1'b0;
    wire signed [W-1:0] iL;
    wire signed [W-1:0] vO;
    wire signed [W-1:0] iC;
    wire signed [W-1:0] iO;

    buck_v1_0 #(
        .model_data_width(W),
        .model_decimal_width(F)
    ) dut (
        .aclk(clk),
        .resetn(resetn),
        .clock_enable(1'b1),
        .pwm(pwm),
        .input_voltage(32'sd167772160),
        .period_inductor(32'sd839),
        .period_capacitor(32'sd419),
        .inverse_resistor(32'sd167772),
        .switch_drop(32'sd3992977),
        .diode_drop(32'sd3825205),
        .series_resistance(32'sd2930141),
        .inductor_current(iL),
        .capacitor_current(iC),
        .output_current(iO),
        .output_voltage(vO)
    );

    initial begin
        repeat (4) @(posedge clk);
        resetn = 1'b1;
        repeat (200) begin
            @(posedge clk);
            #1;
            if ((iL !== 0) || (vO !== 0)) begin
                $error("Estado cero inestable con PWM=0: iL=%0d vO=%0d", iL, vO);
                $fatal(1);
            end
        end
        $display("buck_zero_hold_tb: PASS (iL=0 y Vo=0 durante 200 pasos OFF)");
        $finish;
    end
endmodule
