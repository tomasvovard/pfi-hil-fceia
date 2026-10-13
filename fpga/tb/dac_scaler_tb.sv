// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// dac_scaler_tb.sv
//
// Testbench unitario para dac_scaler.v (puramente combinacional, sin
// reloj). Compara codigos exactos contra referencia calculada en Python
// con la misma formula (round-to-nearest, saturacion antes de escalar).
//////////////////////////////////////////////////////////////////////////////

module dac_scaler_tb;

    localparam real S = 4194304.0; // 2^22

    reg signed [31:0] iL, Vo, iC, iO;
    reg               pwm_sync;
    wire [11:0] code_Vi, code_Vo, code_VL, code_iL, code_iO, code_iI, code_iC, code_Vc;

    dac_scaler dut (
        .iL(iL), .Vo(Vo), .iC(iC), .iO(iO), .pwm_sync(pwm_sync),
        .code_Vi(code_Vi), .code_Vo(code_Vo), .code_VL(code_VL), .code_iL(code_iL),
        .code_iO(code_iO), .code_iI(code_iI), .code_iC(code_iC), .code_Vc(code_Vc)
    );

    int error_count = 0;
    int check_count = 0;

    function automatic signed [31:0] qv(input real v);
        return $rtoi(v * S + (v >= 0.0 ? 0.5 : -0.5));
    endfunction

    task automatic check(input string name, input [11:0] actual, input [11:0] expected);
        check_count = check_count + 1;
        if (actual !== expected) begin
            error_count = error_count + 1;
            $error("[TB] %s: code=%0d, esperado=%0d", name, actual, expected);
        end
    endtask

    initial begin
        // Valores por defecto neutros
        iL = 0; Vo = 0; iC = 0; iO = 0; pwm_sync = 0;
        #1;

        // -------------------------------------------------------
        // Unipolar V (Vi/Vo/Vc), 0..40V -> 0..4095
        // -------------------------------------------------------
        Vo = qv(40.0);  #1; check("Vi=40V (Vi es const)", code_Vi, 12'd4095);
        Vo = qv(28.0);  #1; check("Vo=28V", code_Vo, 12'd2867);
                             check("Vc=28V (Vc=Vo)", code_Vc, 12'd2867);
        Vo = qv(24.0);  #1; check("Vo=24V", code_Vo, 12'd2457);
        Vo = qv(0.0);   #1; check("Vo=0V",  code_Vo, 12'd0);
        Vo = qv(40.0);  #1; check("Vo=40V (full scale)", code_Vo, 12'd4095);
        Vo = qv(-5.0);  #1; check("Vo=-5V (sat inferior)", code_Vo, 12'd0);
        Vo = qv(45.0);  #1; check("Vo=45V (sat superior)", code_Vo, 12'd4095);

        // -------------------------------------------------------
        // Bipolar VL: depende de pwm_sync y Vo -> VL=pwm?(Vi-Vo):(-Vo)
        // Para aislar VL, fijamos Vo y pwm_sync segun el VL deseado.
        // -------------------------------------------------------
        // VL=0V: con pwm_sync=0, VL=-Vo -> Vo=0 da VL=0
        pwm_sync = 0; Vo = qv(0.0); #1; check("VL=0V (via pwm=0,Vo=0)", code_VL, 12'd2048);
        // VL=+12V: con pwm_sync=1, VL=Vi-Vo=40-Vo -> Vo=28 da VL=12
        pwm_sync = 1; Vo = qv(28.0); #1; check("VL=+12V (via pwm=1,Vo=28)", code_VL, 12'd2662);
        // VL=-28V: con pwm_sync=0, VL=-Vo -> Vo=28 da VL=-28
        pwm_sync = 0; Vo = qv(28.0); #1; check("VL=-28V (via pwm=0,Vo=28)", code_VL, 12'd614);
        // VL=+40V (full scale): pwm=1, Vo=0 -> VL=40
        pwm_sync = 1; Vo = qv(0.0); #1; check("VL=+40V (full scale)", code_VL, 12'd4095);
        // VL=-40V: pwm=0, Vo=40 -> VL=-40
        pwm_sync = 0; Vo = qv(40.0); #1; check("VL=-40V (full scale neg)", code_VL, 12'd0);
        pwm_sync = 0; Vo = 0;

        // -------------------------------------------------------
        // Unipolar I (iL/iO/iI), 0..2.5A -> 0..4095
        // -------------------------------------------------------
        iL = qv(0.0);   #1; check("iL=0A", code_iL, 12'd0);
        iL = qv(1.12);  #1; check("iL=1.12A", code_iL, 12'd1835);
        iL = qv(2.5);   #1; check("iL=2.5A (full scale)", code_iL, 12'd4095);
        iL = qv(3.0);   #1; check("iL=3A (saturacion superior)", code_iL, 12'd4095);
        iL = qv(-1.0);  #1; check("iL=-1A (saturacion inferior)", code_iL, 12'd0);

        iO = qv(1.12);  #1; check("iO=1.12A", code_iO, 12'd1835);

        // iI = pwm_sync ? iL : 0
        iL = qv(1.12);
        pwm_sync = 1; #1; check("iI=iL cuando pwm=1", code_iI, 12'd1835);
        pwm_sync = 0; #1; check("iI=0 cuando pwm=0", code_iI, 12'd0);

        // -------------------------------------------------------
        // Bipolar iC, +-0.75A -> 0..4095
        // -------------------------------------------------------
        iC = qv(0.0);    #1; check("iC=0A", code_iC, 12'd2048);
        iC = qv(-0.75);  #1; check("iC=-0.75A (full scale neg)", code_iC, 12'd0);
        iC = qv(0.75);   #1; check("iC=+0.75A (full scale pos)", code_iC, 12'd4095);
        iC = qv(1.0);    #1; check("iC=+1A (saturacion superior)", code_iC, 12'd4095);
        iC = qv(-1.0);   #1; check("iC=-1A (saturacion inferior)", code_iC, 12'd0);
        iC = qv(0.455);  #1; check("iC=+0.455A", code_iC, 12'd3290);
        iC = qv(-0.455); #1; check("iC=-0.455A", code_iC, 12'd805);

        // -------------------------------------------------------
        // Rango nominal de regimen (Stage 3B): iL entre 1.015 y 1.225A
        // -------------------------------------------------------
        iL = qv(1.015); #1; check("iL=1.015A (borde inferior regimen)", code_iL, 12'd1663);
        iL = qv(1.225); #1; check("iL=1.225A (borde superior regimen)", code_iL, 12'd2007);

        $display("");
        $display("========================================================");
        $display(" RESUMEN - dac_scaler_tb");
        $display("========================================================");
        $display(" Checks: %0d   Errores: %0d", check_count, error_count);
        if (error_count == 0)
            $display(" RESULTADO GLOBAL: PASS");
        else
            $display(" RESULTADO GLOBAL: FAIL");
        $display("========================================================");

        if (error_count != 0) $fatal(1, "dac_scaler_tb finalizado con errores.");
        $finish;
    end

endmodule
