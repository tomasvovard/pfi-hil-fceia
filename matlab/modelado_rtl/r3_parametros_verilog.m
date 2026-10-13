%% r3 - Genera el header buck_params.vh para el RTL
% Cuantiza los parametros a signed Q32.22 (Ts = 200 ns) y escribe el header y
% un reporte con el error de cuantizacion. Revisar el reporte antes de copiar
% el header al repositorio de la FPGA.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)
clear; clc;
addpath('..'); addpath('../cfg'); addpath('../func');

buck = buck_params();
med  = medicion_cfg();
W = 32; F = 22; Ts = 200e-9;
q = @(x) round(x * 2^F);

c.VIN = q(buck.Vi);
c.KC  = q(Ts/buck.C);
c.VSW = q(buck.Vsw);
c.VD  = q(buck.Vd);
c.RS  = q(buck.Rs);
c.KR  = arrayfun(@(R) q(1/R), buck.R);

% Offset de cero del DAC (canal Vo), en codigo de 12 bits. offset_Vo_dac esta
% medido en crudo (mismo punto/escala que CH2, ver medicion_cfg.m): primero se
% refiere a Vo fisico (*ganancia_Vo) y despues se cuantiza a codigo (los
% 4095 codigos del DAC cubren Vmax_Vo volts de Vo fisico).
offset_Vo_fisico = med.ohsim.offset_Vo_dac * med.ohsim.ganancia_Vo;
c.VO_DAC_OFFSET_CODE = max(0, min(4095, round(offset_Vo_fisico * 4095 / med.ohsim.Vmax_Vo)));

% Recta 1/L: Ts/L(iL) = max(KL0 + (KL_SLOPE*iL)>>>F, KL_MIN).
% Sin limite superior de KL: no se impone un piso artificial de L.
switch buck.L.tipo
    case 'const'
        c.KL0 = q(Ts/buck.L.const); c.KLs = 0;
        c.KLmin = c.KL0;
        texto_L = sprintf('L constante = %.3f mH', 1e3*buck.L.const);
    otherwise
        c.KL0 = q(Ts*buck.L.b_inv);   c.KLs = q(Ts*buck.L.a_inv);
        c.KLmin = q(Ts/buck.L.knee_max);
        texto_L = sprintf('L(iL): 1/L = max(%.1f*iL + %.1f, %.1f) [1/H], sin piso de L', ...
            buck.L.a_inv, buck.L.b_inv, 1/buck.L.knee_max);
end

out = 'output'; if ~isfolder(out), mkdir(out); end
fid = fopen(fullfile(out,'buck_params.vh'), 'wt');
fprintf(fid, '`ifndef BUCK_PARAMS_VH\n`define BUCK_PARAMS_VH\n\n');
fprintf(fid, '// Generado por modelado_rtl/r3_parametros_verilog.m. No editar a mano.\n');
fprintf(fid, '// signed Q%d.%d, Ts=%.0f ns. %s\n', W, F, Ts*1e9, buck.fuente);
fprintf(fid, '// %s\n', texto_L);
fprintf(fid, '`define BUCK_VIN_Q       %d''sd%d\n', W, c.VIN);
fprintf(fid, '`define BUCK_KL0_Q       %d''sd%d\n', W, c.KL0);
fprintf(fid, '`define BUCK_KL_SLOPE_Q  %d''sd%d\n', W, c.KLs);
fprintf(fid, '`define BUCK_KL_MIN_Q    %d''sd%d\n', W, c.KLmin);
fprintf(fid, '`define BUCK_KC_Q        %d''sd%d\n', W, c.KC);
fprintf(fid, '`define BUCK_VSW_Q       %d''sd%d\n', W, c.VSW);
fprintf(fid, '`define BUCK_VD_Q        %d''sd%d\n', W, c.VD);
fprintf(fid, '`define BUCK_RL_Q        %d''sd%d\n', W, c.RS);
for k = 1:numel(buck.R)
    et = upper(strrep(sprintf('%g', buck.R(k)), '.', 'P'));
    fprintf(fid, '`define BUCK_KR_%s_Q   %d''sd%d\n', et, W, c.KR(k));
end
fprintf(fid, '`define BUCK_VO_DAC_OFFSET_CODE  12''d%d\n', c.VO_DAC_OFFSET_CODE);
fprintf(fid, '\n`endif\n');
fclose(fid);

fprintf('Header  -> %s\n', fullfile(out,'buck_params.vh'));
fprintf('%s\n', texto_L);
fprintf('KL0=%d  KL_SLOPE=%d  KL_MIN=%d (sin KL_MAX)\n', c.KL0, c.KLs, c.KLmin);
fprintf('VO_DAC_OFFSET_CODE=%d  (offset %.0f mV crudo -> %.0f mV Vo fisico / fondo de escala %.0f V)\n', ...
    c.VO_DAC_OFFSET_CODE, 1e3*med.ohsim.offset_Vo_dac, 1e3*offset_Vo_fisico, med.ohsim.Vmax_Vo);
if c.KLs ~= 0
    for I = [0.4 1.0 1.7]
        KL = max(c.KL0 + floor(round(I*2^F)*c.KLs/2^F), c.KLmin);
        fprintf('  iL=%.1f A -> L = %.3f mH (RTL)  vs  %.3f mH (ideal)\n', ...
            I, 1e3*Ts/(KL/2^F), 1e3*inductancia(buck, I));
    end
end
