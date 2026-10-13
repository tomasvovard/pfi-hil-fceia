// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// buck_fpga_validation_phaseC_tb.sv
//
// Testbench de integracion para buck_fpga_validation_phaseC_top.v. No
// revalida en detalle lo que ya tienen sus propios testbenches:
//   - rango parametrizado y palabras SPI del AD5328: cubiertos por
//     tb/ad5328_driver_param_tb.sv;
//   - escalado del dac_scaler: cubierto por tb/dac_scaler_tb.sv;
//   - decodificador de codigo Gray, incluido el caso "no usado": cubierto
//     por tb/r_select_gray_tb.sv.
//
// Este testbench cubre la integracion de todo el top:
//
//  A. Regresion de la recurrencia con los coeficientes de buck_params.vh
//     (R=25 fijo via r_select en gray=01): arranque en frio, 750
//     muestras, comparacion BIT-EXACTA contra coldstart_exp_*.mem
//     (generados por scripts/generate_reference.py).
//  B. Disparo del ensayo: un pulso en dio_trigger_in produce exactamente
//     un pulso de 1 ciclo en dbg_trigger, con la latencia esperada del
//     sincronizador + detector de flanco (documentado, no solo
//     comprobado silenciosamente).
//  C. Seleccion de R en caliente: cambiar dio_rsel_b0/b1_in en pleno
//     funcionamiento efectivamente cambia el valor que ve
//     buck_model.KR_Q_ext (via jerarquia, ya que es lo unico observable
//     sin instrumentar mas el top).
//  D. Salidas DIO: dio_pwm_sync==pwm_sync, dio_vsw==~pwm_sync,
//     dio_vx==pwm_sync, en todo momento.
//  E. Sanity de ambos DAC: DAC0 transmite iL/Vo con timing minimo seguro;
//     DAC1 transmite seis señales auxiliares en su driver independiente.
//////////////////////////////////////////////////////////////////////////////

module buck_fpga_validation_phaseC_tb;

    localparam real CLK_PERIOD_NS = 33.333; // sys_clk = 30 MHz
    localparam int  W = 32;
    localparam real SCALE = 4194304.0; // 2^22

    reg sys_clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) sys_clk = ~sys_clk;

    int error_count = 0;
    time t_start0, t_done0;
    time t_start1, t_done1;
    integer ciclos0, ciclos1;
    task automatic report_error(input string msg);
        error_count = error_count + 1;
        $error("[TB] %s (t=%0t)", msg, $time);
    endtask

    // =================================================================
    // DUT
    // =================================================================
    reg pwm_in_tb        = 1'b0;
    reg dio_trigger_tb    = 1'b0;
    reg dio_rsel_b0_tb    = 1'b0;
    reg dio_rsel_b1_tb    = 1'b0;

    wire model_running_led, comm_led;
    wire dac0_din, dac0_sclk, dac0_sync, dac0_ldac;
    wire dac1_din, dac1_sclk, dac1_sync, dac1_ldac;
    wire dio_pwm_sync, dio_vsw, dio_vx;

    buck_fpga_validation_phaseC_top #(
        .HEARTBEAT_HALF_PERIOD_CE (50),
        .COMM_TIMEOUT_CYCLES      (500)
    ) dut (
        .sys_clk           (sys_clk),
        .pwm_in            (pwm_in_tb),
        .model_running_led (model_running_led),
        .comm_led          (comm_led),
        .dac0_din          (dac0_din),
        .dac0_sclk         (dac0_sclk),
        .dac0_sync         (dac0_sync),
        .dac0_ldac         (dac0_ldac),
        .dac1_din          (dac1_din),
        .dac1_sclk         (dac1_sclk),
        .dac1_sync         (dac1_sync),
        .dac1_ldac         (dac1_ldac),
        .dio_pwm_sync      (dio_pwm_sync),
        .dio_vsw           (dio_vsw),
        .dio_vx            (dio_vx),
        .dio_trigger_in    (dio_trigger_tb),
        .dio_rsel_b0_in    (dio_rsel_b0_tb),
        .dio_rsel_b1_in    (dio_rsel_b1_tb)
    );

    wire                dut_resetn    = dut.resetn;
    wire                dut_model_ce  = dut.dbg_model_ce;
    wire                dut_pwm_sync  = dut.dbg_pwm_sync;
    wire signed [W-1:0] dut_iL        = dut.dbg_iL;
    wire signed [W-1:0] dut_Vo        = dut.dbg_Vo;
    wire signed [W-1:0] dut_iC        = dut.iC;  // no tiene mark_debug (ver top), pero existe como wire interno
    wire signed [W-1:0] dut_iO        = dut.iO;
    wire                dut_trigger   = dut.dbg_trigger;
    wire [1:0]          dut_rsel_dbg  = dut.dbg_rsel;
    wire signed [W-1:0] dut_KR_Q_ext  = dut.u_buck_model.KR_Q_ext;
    wire                dut_drv0_start = dut.drv0_start;
    wire                dut_drv0_busy  = dut.drv0_busy;
    wire                dut_drv1_start = dut.drv1_start;
    wire                dut_drv1_busy  = dut.drv1_busy;

    // ---------------------------------------------------------------
    // A. Regresion: monitor de periodo de model_ce.
    // ---------------------------------------------------------------
    real t_ce_prev = -1.0;
    int  ce_period_errors = 0;
    int  ce_pulse_count = 0;
    always @(posedge sys_clk) begin
        if (dut_model_ce) begin
            ce_pulse_count = ce_pulse_count + 1;
            if (t_ce_prev >= 0.0) begin
                // XSim 2025.2 no soporta $abs como system function.
                // Chequeo equivalente sin $abs:
                if ((($realtime - t_ce_prev - 6.0*CLK_PERIOD_NS) > 0.01) ||
                    (($realtime - t_ce_prev - 6.0*CLK_PERIOD_NS) < -0.01))
                    ce_period_errors = ce_period_errors + 1;
            end
            t_ce_prev = $realtime;
        end
    end

    // ---------------------------------------------------------------
    // A. Regresion: memorias de referencia
    // ---------------------------------------------------------------
    localparam int N_COLDSTART = 750;
    reg              coldstart_pwm      [0:N_COLDSTART-1];
    reg signed [W-1:0] exp_iL           [0:N_COLDSTART-1];
    reg signed [W-1:0] exp_vO           [0:N_COLDSTART-1];
    reg signed [W-1:0] exp_iC           [0:N_COLDSTART-1];
    reg signed [W-1:0] exp_iO           [0:N_COLDSTART-1];

    initial begin
        $readmemb("coldstart_pwm.mem", coldstart_pwm); // 0/1 por linea, formato binario
        $readmemh("coldstart_exp_iL.mem", exp_iL);
        $readmemh("coldstart_exp_vO.mem", exp_vO);
        $readmemh("coldstart_exp_iC.mem", exp_iC);
        $readmemh("coldstart_exp_iO.mem", exp_iO);
    end

    int coldstart_idx = 0;
    int coldstart_mismatches = 0;
    bit coldstart_done = 1'b0;

    always @(posedge sys_clk) begin
        if (dut_resetn && dut_model_ce && !coldstart_done) begin
            if (dut_iL !== exp_iL[coldstart_idx])
                report_error($sformatf("coldstart iL muestra %0d: esperaba %0d, obtuve %0d", coldstart_idx, exp_iL[coldstart_idx], dut_iL));
            if (dut_Vo !== exp_vO[coldstart_idx])
                report_error($sformatf("coldstart Vo muestra %0d: esperaba %0d, obtuve %0d", coldstart_idx, exp_vO[coldstart_idx], dut_Vo));
            if (dut_iC !== exp_iC[coldstart_idx])
                report_error($sformatf("coldstart iC muestra %0d: esperaba %0d, obtuve %0d", coldstart_idx, exp_iC[coldstart_idx], dut_iC));
            if (dut_iO !== exp_iO[coldstart_idx])
                report_error($sformatf("coldstart iO muestra %0d: esperaba %0d, obtuve %0d", coldstart_idx, exp_iO[coldstart_idx], dut_iO));

            coldstart_idx = coldstart_idx + 1;
            if (coldstart_idx == N_COLDSTART)
                coldstart_done = 1'b1;
        end
    end

    // Maneja pwm_in_tb segun coldstart_pwm.mem, una muestra por model_ce
    // (arranca ANTES del reset para que el sincronizador ya tenga un
    // valor estable cuando resetn sube).
    int pwm_drive_idx = 0;
    always @(posedge sys_clk) begin
        if (!coldstart_done) begin
            if (pwm_drive_idx < N_COLDSTART)
                pwm_in_tb <= coldstart_pwm[pwm_drive_idx];
            if (dut_model_ce && pwm_drive_idx < N_COLDSTART)
                pwm_drive_idx = pwm_drive_idx + 1;
        end
    end

    // ---------------------------------------------------------------
    // C. Seleccion de R: gray=01 (R=25) fijo durante TODA la seccion A,
    // para que coincida con el R usado al generar coldstart_exp_*.mem
    // (scripts/generate_reference.py).
    // Se establece ANTES del reset para que ya este estable (via los
    // sync_2ff) cuando arranca el primer model_ce real.
    // ---------------------------------------------------------------
    initial begin
        dio_rsel_b0_tb = 1'b1; // {b1,b0}=01 -> R=25
        dio_rsel_b1_tb = 1'b0;
    end

    // ---------------------------------------------------------------
    // Secuencia principal
    // ---------------------------------------------------------------
    initial begin
        wait (dut_resetn == 1'b1);
        $display("[TB] Reset liberado en t=%0t. Arranca regresion de coldstart (%0d muestras).", $time, N_COLDSTART);

        wait (coldstart_done == 1'b1);
        $display("[TB] Regresion de coldstart terminada en t=%0t (%0d mismatches).", $time, coldstart_mismatches);

        // -------------------------------------------------------
        // B. Disparo del ensayo: pulso en dio_trigger_in
        // -------------------------------------------------------
        @(posedge sys_clk);
        dio_trigger_tb = 1'b1;
        @(posedge sys_clk);
        dio_trigger_tb = 1'b0;

        fork
            begin: wait_trigger_pulse
                @(posedge dut_trigger);
                $display("[TB] dbg_trigger pulso en t=%0t (esperado).", $time);
            end
            begin: timeout_trigger
                repeat (20) @(posedge sys_clk);
                report_error("dbg_trigger nunca pulso despues del flanco en dio_trigger_in (timeout)");
            end
        join_any
        disable fork;

        // Confirmar que dura EXACTAMENTE 1 ciclo. Ojo con el orden de
        // evaluacion: dbg_trigger es COMBINACIONAL (d_sync & ~d_prev), asi
        // que en el mismo posedge donde d_prev se actualiza (region NBA,
        // se aplica DESPUES de que este bloque retome ejecucion en la
        // region Active), leerlo sin esperar un delta mas todavia muestra
        // el valor viejo -- no es que el pulso dure de mas, es que se lo
        // esta leyendo antes de que la actualizacion non-blocking se
        // aplique. Se agrega #1 para leerlo ya asentado.
        if (dut_trigger === 1'b1) begin
            @(posedge sys_clk);
            #1;
            if (dut_trigger === 1'b1)
                report_error("dbg_trigger duro mas de 1 ciclo (deberia ser un pulso, no un nivel)");
        end

        // -------------------------------------------------------
        // C. Cambiar R en caliente y confirmar que KR_Q_ext cambia
        // -------------------------------------------------------
        repeat (5) @(posedge sys_clk);
        dio_rsel_b0_tb = 1'b1; dio_rsel_b1_tb = 1'b1; // gray=11 -> 50 ohm
        repeat (10) @(posedge sys_clk); // margen: 2 sync_2ff + 1 registro de r_select_gray
        if (dut_KR_Q_ext !== 32'sd83886)
            report_error($sformatf("tras gray=11, KR_Q_ext deberia ser 83886 (50 ohm), es %0d", dut_KR_Q_ext));
        else
            $display("[TB] KR_Q_ext cambio correctamente a 50 ohm tras el cambio de DIO_4/5.");

        dio_rsel_b0_tb = 1'b0; dio_rsel_b1_tb = 1'b0; // gray=00 -> 16.6 ohm
        repeat (10) @(posedge sys_clk);
        if (dut_KR_Q_ext !== 32'sd252669)
            report_error($sformatf("tras gray=00, KR_Q_ext deberia ser 252669 (16.6 ohm), es %0d", dut_KR_Q_ext));
        else
            $display("[TB] KR_Q_ext cambio correctamente a 16.6 ohm tras el cambio de DIO_4/5.");

        // Volver a 25 ohm para dejar el sistema en un estado conocido
        dio_rsel_b0_tb = 1'b1; dio_rsel_b1_tb = 1'b0;
        repeat (10) @(posedge sys_clk);

        // -------------------------------------------------------
        // E. DAC0 transmite solo C/D. Con SYNC=2 ciclos y LDAC=1 ciclo,
        // el frame completo dura unos 75 ciclos (2.50 us). DAC1 transmite
        // A..F en paralelo logico y no reduce la tasa del DAC0.
        // -------------------------------------------------------
        fork
            begin: wait_dac0
                @(posedge dut_drv0_start);
                t_start0 = $time;
                $display("[TB] DAC0 arranco su primer frame en t=%0t.", $time);
                @(posedge dut.drv0_done);
                t_done0 = $time;
                ciclos0 = (t_done0 - t_start0) / CLK_PERIOD_NS;
                $display("[TB] DAC0 completo el frame en %0d ciclos (~%.2f us).", ciclos0, ciclos0*CLK_PERIOD_NS/1000.0);
                if (ciclos0 < 72 || ciclos0 > 78)
                    report_error($sformatf("DAC0: frame de %0d ciclos, esperaba ~75 (C/D, timing minimo seguro).", ciclos0));
            end
            begin: timeout_dac0
                repeat (2000) @(posedge sys_clk);
                report_error("DAC0 nunca arranco/completo un frame (timeout)");
            end
        join_any
        disable fork;

        fork
            begin: wait_dac1
                @(posedge dut_drv1_start);
                t_start1 = $time;
                $display("[TB] DAC1 arranco su primer frame en t=%0t.", $time);
                @(posedge dut.drv1_done);
                t_done1 = $time;
                ciclos1 = (t_done1 - t_start1) / CLK_PERIOD_NS;
                $display("[TB] DAC1 completo el frame en %0d ciclos (~%.2f us).", ciclos1, ciclos1*CLK_PERIOD_NS/1000.0);
                if (ciclos1 < 218 || ciclos1 > 226)
                    report_error($sformatf("DAC1: frame de %0d ciclos, esperaba ~222 (FIRST_CHANNEL=0, N_CHANNELS=6).", ciclos1));
            end
            begin: timeout_dac1
                repeat (2000) @(posedge sys_clk);
                report_error("DAC1 nunca arranco/completo un frame (timeout)");
            end
        join_any
        disable fork;

        repeat (100) @(posedge sys_clk);

        $display("");
        $display("============================================================");
        $display(" RESUMEN buck_fpga_validation_phaseC_tb");
        $display("============================================================");
        $display(" A. Regresion coldstart (%0d muestras)   %s", N_COLDSTART, (error_count==0) ? "PASS" : "ver errores arriba");
        $display(" B. Disparo del ensayo (dio_trigger_in)                revisar arriba");
        $display(" C. Seleccion de R en caliente                        revisar arriba");
        $display(" D. DIO (monitor continuo, ver abajo)                 revisar al final");
        $display(" E. DAC0 rapido + DAC1 auxiliar independiente          revisar arriba");
        $display("");
        $display(" Errores totales detectados: %0d", error_count);
        if (error_count == 0)
            $display(" RESULTADO GLOBAL: PASS");
        else
            $display(" RESULTADO GLOBAL: FAIL");
        $display("============================================================");
        $display("");

        $finish;
    end

    // ---------------------------------------------------------------
    // D. DIO: monitor continuo
    // ---------------------------------------------------------------
    always @(*) begin
        if (dio_pwm_sync !== dut_pwm_sync)
            report_error("dio_pwm_sync != pwm_sync");
        if (dio_vsw !== ~dut_pwm_sync)
            report_error("dio_vsw != ~pwm_sync");
        if (dio_vx !== dut_pwm_sync)
            report_error("dio_vx != pwm_sync");
    end

    // ---------------------------------------------------------------
    // Timeout global de seguridad (no se espera llegar aca)
    // ---------------------------------------------------------------
    initial begin
        #5_000_000; // 5 ms de tiempo de simulacion
        report_error("TIMEOUT GLOBAL: la simulacion no termino sola.");
        $finish;
    end

endmodule
