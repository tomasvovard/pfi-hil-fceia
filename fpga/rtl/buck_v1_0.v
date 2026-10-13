// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps

//////////////////////////////////////////////////////////////////////////////
// buck_v1_0.v
//
// Nucleo numerico del modelo del convertidor buck: integracion
// Forward-Euler de iL y Vo en punto fijo, un paso por cada clock_enable.
// Parte del modelo ideal de buck publicado por Pablo Trujillo
// (controlpaths.com) y fue ampliado con la caida del interruptor (Vsw),
// la del diodo (Vd), la resistencia serie (RL) y el bloqueo de la
// corriente inversa del diodo en el estado OFF.
//////////////////////////////////////////////////////////////////////////////

module buck_v1_0 #(
  parameter model_data_width = 25,
  parameter model_decimal_width = 15
)(
  input aclk, 
  input resetn, 
  input clock_enable,

  input pwm, 
  input signed [model_data_width-1:0] input_voltage,
  input signed [model_data_width-1:0] period_inductor,
  input signed [model_data_width-1:0] period_capacitor,
  input signed [model_data_width-1:0] inverse_resistor,
  input signed [model_data_width-1:0] switch_drop,
  input signed [model_data_width-1:0] diode_drop,
  input signed [model_data_width-1:0] series_resistance,
  
  output reg signed [model_data_width-1:0] inductor_current,
  output signed [model_data_width-1:0] capacitor_current,
  output signed [model_data_width-1:0] output_current,
  output reg signed [model_data_width-1:0] output_voltage  
);

  wire signed [model_data_width-1:0] voltage_diff; /* difference between voltage input and output */
  wire signed [(model_data_width*2)-1:0] voltage_diff_intl_2width; /* inductor integrator input double width*/
  wire signed [model_data_width-1:0] voltage_diff_intl; /* inductor integrator input */
  wire signed [(model_data_width*2)-1:0] capacitor_current_intc_2width; /* capacitor integrator input double width*/
  wire signed [model_data_width-1:0] capacitor_current_intc; /* capacitor integrator input */
  wire signed [(model_data_width*2)-1:0] output_current_2width; /* output current double width */
  wire signed [(model_data_width*2)-1:0] series_drop_2width;
  wire signed [model_data_width-1:0] series_drop;
  wire signed [model_data_width-1:0] inductor_current_next;

  /* Nonideal switch node and series loss:
       ON:  vL = Vin - Vsw - Vo - RL*iL
       OFF: vL =      - Vd - Vo - RL*iL */
  assign series_drop_2width = inductor_current * series_resistance;
  assign series_drop = series_drop_2width >>> model_decimal_width;
  assign voltage_diff = pwm ?
      input_voltage - switch_drop - output_voltage - series_drop :
      -diode_drop - output_voltage - series_drop;
  
  /* inductor integrator gain */
  assign voltage_diff_intl_2width = voltage_diff * period_inductor;
  assign voltage_diff_intl = voltage_diff_intl_2width >>> model_decimal_width;
  assign inductor_current_next = inductor_current + voltage_diff_intl;

  /* Inductor integrator. In OFF state the diode blocks reverse current.
     The clamp is inactive throughout the intended CCM experiments, but it
     keeps the physical zero state stable while PWM is safely disabled. */
  always @(posedge aclk)
    if (!resetn)
      inductor_current <= 0;
    else 
      if (clock_enable)
        if (!pwm && (inductor_current_next < 0))
          inductor_current <= 0;
        else
          inductor_current <= inductor_current_next;

  assign capacitor_current = inductor_current - output_current;

  /* capacitor integrator gain */
  assign capacitor_current_intc_2width = capacitor_current * period_capacitor;
  assign capacitor_current_intc = capacitor_current_intc_2width >>> model_decimal_width;

  /* capacitor integrator */
  always @(posedge aclk)
    if (!resetn)
      output_voltage <= 0;
    else 
      if (clock_enable)
        output_voltage <= output_voltage + capacitor_current_intc;

  /* resize output current */
  assign output_current_2width = output_voltage * inverse_resistor;
  assign output_current = output_current_2width >>> model_decimal_width;


endmodule
