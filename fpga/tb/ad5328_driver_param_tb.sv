// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps

// Regression del rango parametrizado de ad5328_driver.
// DAC0 debe transmitir solo C/D; DAC1, solo A..F. Se decodifica cada
// palabra en el flanco de bajada de SCLK, igual que el AD5328 real.
module ad5328_driver_param_tb;

    localparam real CLK_PERIOD_NS = 33.333;

    reg clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    reg resetn = 1'b0;
    reg start0 = 1'b0;
    reg start1 = 1'b0;

    wire busy0, done0, din0, sclk0, sync0, ldac0;
    wire busy1, done1, din1, sclk1, sync1, ldac1;

    integer error_count = 0;
    integer sync_falls0 = 0;
    integer sync_falls1 = 0;
    integer cycle_count = 0;

    localparam [11:0] CH0 = 12'h101;
    localparam [11:0] CH1 = 12'h212;
    localparam [11:0] CH2 = 12'h323;
    localparam [11:0] CH3 = 12'h434;
    localparam [11:0] CH4 = 12'h545;
    localparam [11:0] CH5 = 12'h656;
    localparam [11:0] CH6 = 12'h767;
    localparam [11:0] CH7 = 12'h878;

    ad5328_driver #(
        .FIRST_CHANNEL (2),
        .N_CHANNELS    (2)
    ) dut0 (
        .clk(clk), .resetn(resetn),
        .ch0_data(CH0), .ch1_data(CH1),
        .ch2_data(CH2), .ch3_data(CH3),
        .ch4_data(CH4), .ch5_data(CH5),
        .ch6_data(CH6), .ch7_data(CH7),
        .start(start0), .busy(busy0), .done(done0),
        .dac_din(din0), .dac_sclk(sclk0),
        .dac_sync(sync0), .dac_ldac(ldac0)
    );

    ad5328_driver #(
        .FIRST_CHANNEL (0),
        .N_CHANNELS    (6)
    ) dut1 (
        .clk(clk), .resetn(resetn),
        .ch0_data(CH0), .ch1_data(CH1),
        .ch2_data(CH2), .ch3_data(CH3),
        .ch4_data(CH4), .ch5_data(CH5),
        .ch6_data(CH6), .ch7_data(CH7),
        .start(start1), .busy(busy1), .done(done1),
        .dac_din(din1), .dac_sclk(sclk1),
        .dac_sync(sync1), .dac_ldac(ldac1)
    );

    function automatic [11:0] channel_data(input integer channel);
        begin
            case(channel)
                0: channel_data = CH0;
                1: channel_data = CH1;
                2: channel_data = CH2;
                3: channel_data = CH3;
                4: channel_data = CH4;
                5: channel_data = CH5;
                6: channel_data = CH6;
                default: channel_data = CH7;
            endcase
        end
    endfunction

    task automatic report_error(input string message);
        begin
            error_count = error_count + 1;
            $error("[AD5328 PARAM TB] %s (t=%0t)", message, $time);
        end
    endtask

    task automatic capture_dac0;
        integer channel;
        integer bit_index;
        integer ldac_start_cycle;
        reg [15:0] received;
        reg [15:0] expected;
        begin
            for(channel = 2; channel <= 3; channel = channel + 1) begin
                wait(sync0 === 1'b0);
                received = 16'd0;
                for(bit_index = 0; bit_index < 16; bit_index = bit_index + 1) begin
                    @(negedge sclk0);
                    #1;
                    received = {received[14:0], din0};
                end
                expected = {1'b0, channel[2:0], channel_data(channel)};
                if(received !== expected)
                    report_error($sformatf("DAC0 canal %0d: esperaba %04h, obtuvo %04h",
                                           channel, expected, received));
                if(channel != 3)
                    @(posedge sync0);
            end

            @(negedge ldac0);
            ldac_start_cycle = cycle_count;
            @(posedge ldac0);
            if((cycle_count - ldac_start_cycle) != 2)
                report_error($sformatf("DAC0 LDAC duro %0d ciclos, esperaba 2",
                                       cycle_count - ldac_start_cycle));
            @(posedge done0);
            #1;
            if(sync_falls0 != 2)
                report_error($sformatf("DAC0 transmitio %0d palabras, esperaba 2", sync_falls0));
            if(busy0 !== 1'b0)
                report_error("DAC0 busy no bajo al completar");
        end
    endtask

    task automatic capture_dac1;
        integer channel;
        integer bit_index;
        integer ldac_start_cycle;
        reg [15:0] received;
        reg [15:0] expected;
        begin
            for(channel = 0; channel <= 5; channel = channel + 1) begin
                wait(sync1 === 1'b0);
                received = 16'd0;
                for(bit_index = 0; bit_index < 16; bit_index = bit_index + 1) begin
                    @(negedge sclk1);
                    #1;
                    received = {received[14:0], din1};
                end
                expected = {1'b0, channel[2:0], channel_data(channel)};
                if(received !== expected)
                    report_error($sformatf("DAC1 canal %0d: esperaba %04h, obtuvo %04h",
                                           channel, expected, received));
                if(channel != 5)
                    @(posedge sync1);
            end

            @(negedge ldac1);
            ldac_start_cycle = cycle_count;
            @(posedge ldac1);
            if((cycle_count - ldac_start_cycle) != 2)
                report_error($sformatf("DAC1 LDAC duro %0d ciclos, esperaba 2",
                                       cycle_count - ldac_start_cycle));
            @(posedge done1);
            #1;
            if(sync_falls1 != 6)
                report_error($sformatf("DAC1 transmitio %0d palabras, esperaba 6", sync_falls1));
            if(busy1 !== 1'b0)
                report_error("DAC1 busy no bajo al completar");
        end
    endtask

    always @(posedge clk)
        cycle_count = cycle_count + 1;

    always @(negedge sync0)
        if(resetn) sync_falls0 = sync_falls0 + 1;

    always @(negedge sync1)
        if(resetn) sync_falls1 = sync_falls1 + 1;

    initial begin
        repeat(4) @(posedge clk);
        @(negedge clk);
        resetn = 1'b1;

        @(negedge clk);
        start0 = 1'b1;
        start1 = 1'b1;
        @(negedge clk);
        start0 = 1'b0;
        start1 = 1'b0;

        fork
            capture_dac0();
            capture_dac1();
        join

        if(error_count == 0)
            $display("AD5328_DRIVER_PARAM_TB: PASS");
        else
            $display("AD5328_DRIVER_PARAM_TB: FAIL (%0d errores)", error_count);
        $finish;
    end

    initial begin
        #100_000;
        report_error("timeout global");
        $finish;
    end

endmodule
