function calibrar_pinza(I1, V1, I2, V2)
%CALIBRAR_PINZA  Ganancia y cero de la pinza a partir de dos corrientes
% continuas conocidas por el conductor (con las mismas vueltas del ensayo),
% a ~10-50 % y ~50-90 % de escala.
%   I1, I2 : corriente real [A].   V1, V2 : lectura media de CH3 [V].
%
% Copiar el resultado a cfg/medicion_cfg.m (med.pinza.ganancia y med.pinza.cero).

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

ganancia = (V2 - V1) / (I2 - I1);
cero     = V1 - ganancia * I1;
nominal  = 0.100 * 5 * 10;

fprintf('ganancia = %.4f V/A  (nominal %.3f, desvio %.2f %%)\n', ...
    ganancia, nominal, 100*(ganancia-nominal)/nominal);
fprintf('cero     = %.4f V   -> offset de corriente = %.4f A\n', cero, cero/ganancia);
fprintf('En cfg/medicion_cfg.m:\n');
fprintf('  med.pinza.ganancia = %.4f;\n  med.pinza.cero     = %.4f;\n', ganancia, cero);
end
