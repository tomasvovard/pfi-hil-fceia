// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// r_select_gray_tb.sv
//
// Testbench dedicado de r_select_gray.v, en el mismo espiritu que
// dac_scaler_tb.sv (modulo aislado, sin el resto del sistema). Cubre:
//   - los 3 codigos validos seleccionan el KR_Q correcto;
//   - el codigo NO usado (2'b10) retiene el ultimo valor valido en vez
//     de mapear a cualquier cosa (el motivo de ser de este modulo);
//   - la salida esta registrada (1 ciclo de latencia).
//////////////////////////////////////////////////////////////////////////////

module r_select_gray_tb;

    localparam real CLK_PERIOD_NS = 33.333;
    localparam signed [31:0] KR_Q_16p6 = 32'sd252669;
    localparam signed [31:0] KR_Q_25   = 32'sd167772;
    localparam signed [31:0] KR_Q_50   = 32'sd83886;

    reg clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    reg resetn = 1'b0;
    reg gray_b0 = 1'b0, gray_b1 = 1'b0;
    wire signed [31:0] KR_Q_sel;
    wire [1:0] r_select_dbg;

    int error_count = 0;
    task automatic report_error(input string msg);
        error_count = error_count + 1;
        $error("[TB] %s (t=%0t)", msg, $time);
    endtask

    r_select_gray #(.W(32), .F(22)) dut (
        .clk          (clk),
        .resetn       (resetn),
        .gray_b0_sync (gray_b0),
        .gray_b1_sync (gray_b1),
        .KR_Q_sel     (KR_Q_sel),
        .r_select_dbg (r_select_dbg)
    );

    task automatic set_gray(input bit b1, input bit b0, input string label);
        @(posedge clk);
        gray_b1 = b1;
        gray_b0 = b0;
        @(posedge clk); // 1 ciclo de latencia del registro interno
        #1;
        $display("[TB] gray={%0d,%0d} (%s) -> KR_Q_sel=%0d r_select_dbg=%0b", b1, b0, label, KR_Q_sel, r_select_dbg);
    endtask

    initial begin
        // Reset: debe arrancar en el codigo 00 (16.6 ohm)
        repeat (3) @(posedge clk);
        resetn = 1'b1;
        @(posedge clk); #1;
        if (KR_Q_sel !== KR_Q_16p6)
            report_error($sformatf("post-reset: esperaba KR_Q_16p6=%0d, obtuve %0d", KR_Q_16p6, KR_Q_sel));
        if (r_select_dbg !== 2'b00)
            report_error("post-reset: r_select_dbg deberia ser 00");

        // 00 -> 01 (16.6 -> 25)
        set_gray(1'b0, 1'b1, "25 ohm");
        if (KR_Q_sel !== KR_Q_25) report_error("gray=01 no selecciono KR_Q_25");

        // 01 -> 11 (25 -> 50)
        set_gray(1'b1, 1'b1, "50 ohm");
        if (KR_Q_sel !== KR_Q_50) report_error("gray=11 no selecciono KR_Q_50");

        // 11 -> 10 (NO USADO): debe retener KR_Q_50 (el ultimo valido)
        set_gray(1'b1, 1'b0, "NO USADO, debe retener 50 ohm");
        if (KR_Q_sel !== KR_Q_50)
            report_error($sformatf("gray=10 (no usado) no retuvo el ultimo valor: esperaba %0d, obtuve %0d", KR_Q_50, KR_Q_sel));
        if (r_select_dbg !== 2'b11)
            report_error("gray=10: r_select_dbg deberia seguir mostrando 11 (el ultimo valido), no el codigo invalido");

        // 10 -> 11 (vuelve a un codigo valido, mismo valor: no deberia cambiar nada raro)
        set_gray(1'b1, 1'b1, "50 ohm, de nuevo");
        if (KR_Q_sel !== KR_Q_50) report_error("retorno a gray=11 no selecciono KR_Q_50");

        // 11 -> 00 (50 -> 16.6, salto NO real en la secuencia de ensayos
        // pero valido igual: el modulo tiene que soportarlo)
        set_gray(1'b0, 1'b0, "16.6 ohm");
        if (KR_Q_sel !== KR_Q_16p6) report_error("gray=00 no selecciono KR_Q_16p6");

        repeat (5) @(posedge clk);

        $display("");
        $display("============================================================");
        if (error_count == 0)
            $display(" r_select_gray_tb: PASS (0 errores)");
        else
            $display(" r_select_gray_tb: FAIL (%0d errores)", error_count);
        $display("============================================================");
        $display("");

        $finish;
    end

endmodule
