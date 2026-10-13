// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns/1ps
`include "buck_params.vh"
module dac_offset_tb;
  reg signed [31:0] vo=0;
  wire [11:0] raw, corrected, vc, il;
  dac_scaler base(.Vo(vo),.iL(32'sd4194304),.iC(32'sd0),.iO(32'sd0),.pwm_sync(1'b0),.code_Vo(raw));
  dac_scaler #(.VO_DAC_OFFSET_CODE(`BUCK_VO_DAC_OFFSET_CODE)) dut(
    .Vo(vo),.iL(32'sd4194304),.iC(32'sd0),.iO(32'sd0),.pwm_sync(1'b0),
    .code_Vo(corrected),.code_Vc(vc),.code_iL(il));
  integer n, expected;
  initial begin
    for(n=-10;n<=4105;n=n+1) begin
      vo=$rtoi(n*167772160.0/4095.0);
      #1;
      expected=raw>29 ? raw-29 : 0;
      if(corrected!==expected[11:0]) $fatal(1,"Offset mismatch n=%d",n);
      if(vc!==raw || il!==12'd1638) $fatal(1,"Another channel changed");
    end
    $display("PASS dac_offset_tb: subtraction, saturation, other channels unchanged");
    $finish;
  end
endmodule
