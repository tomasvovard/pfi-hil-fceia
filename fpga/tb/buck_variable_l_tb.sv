// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns/1ps
`include "buck_params.vh"
module buck_variable_l_tb;
  reg clk=0;
  always #5 clk=~clk;
  reg signed [31:0] test_i=0;
  wire signed [31:0] il,vo,ic,io;
  buck_model dut(.clk(clk),.resetn(1'b0),.model_ce(1'b0),.pwm_sync(1'b0),
    .KR_Q_ext(`BUCK_KR_25_Q),.iL(il),.Vo(vo),.iC(ic),.iO(io));
  integer n;
  longint signed expected, product;
  initial begin
    force dut.u_buck.inductor_current=test_i;
    // Includes low-current plateau and currents past the former 0.45 mH cap.
    for(n=-100;n<=1000;n=n+1) begin
      test_i=$rtoi(n*4194304.0/100.0);
      #1;
      product=$signed(test_i)*64'sd263;
      expected=741+(product>>>22);
      if(expected<839) expected=839;
      if(dut.kl_var !== expected[31:0]) $fatal(1,"KL mismatch i=%d",test_i);
    end
    if(dut.kl_var<=1864) $fatal(1,"Former L floor still active");
    release dut.u_buck.inductor_current;
    $display("PASS buck_variable_l_tb: 1101 points, no 0.45 mH floor");
    $finish;
  end
endmodule
