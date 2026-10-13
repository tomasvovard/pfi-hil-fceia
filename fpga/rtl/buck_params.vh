`ifndef BUCK_PARAMS_VH
`define BUCK_PARAMS_VH

// Generado por modelado_rtl/r3_parametros_verilog.m. No editar a mano.
// signed Q32.22, Ts=200 ns. Ajuste sobre ensayos del CEuP; L(iL) medida
// L(iL): 1/L = max(313.9*iL + 883.4, 1000.0) [1/H], sin piso de L
`define BUCK_VIN_Q       32'sd167772160
`define BUCK_KL0_Q       32'sd741
`define BUCK_KL_SLOPE_Q  32'sd263
`define BUCK_KL_MIN_Q    32'sd839
`define BUCK_KC_Q        32'sd396
`define BUCK_VSW_Q       32'sd8171343
`define BUCK_VD_Q        32'sd2904975
`define BUCK_RL_Q        32'sd1761608
`define BUCK_KR_50_Q   32'sd83886
`define BUCK_KR_25_Q   32'sd167772
`define BUCK_KR_16P6_Q   32'sd252669
`define BUCK_VO_DAC_OFFSET_CODE  12'd29

`endif
