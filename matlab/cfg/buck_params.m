function buck = buck_params()
%BUCK_PARAMS  Parametros fisicos y de ajuste del convertidor buck (CEuP).
% Editar aca al repetir mediciones. L, Rs, Vsw y Vd son equivalentes de
% ajuste (reproducen lo observado), no todos mediciones directas.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

buck.Vi  = 40;          % [V]   tension de entrada (medida con tester)
buck.C   = 2118e-6;     % [F]   capacidad de salida (medida sobre el banco)
buck.fsw = 10e3;        % [Hz]  frecuencia PWM
buck.Tsw = 1/buck.fsw;  % [s]
buck.R   = [50 25 16.6];% [ohm] cargas disponibles

% Perdidas equivalentes del modelo no ideal.
buck.Vsw = 1.9482;      % [V]   caida equivalente del IGBT en conduccion (ON)
buck.Vd  = 0.6926;      % [V]   caida equivalente del diodo (OFF)
buck.Rs  = 0.42;        % [ohm] resistencia serie equivalente (DCR medida ~0.16)

% -------------------------------------------------------------------------
% Inductancia L(iL). La bobina baja de valor con la corriente. 
% El modelo (Simulink y FPGA) trabaja con la inversa 1/L como una recta, 
% para evitar divisiones. El ajuste afín en L es otra aproximacion, solo grafica.
%
%   tipo = 'const' : L = buck.L.const
%   tipo = 'lin'   : 1/L = a_inv*iL + b_inv    (sin limites)
%   tipo = 'knee'  : idem, pero L limitada a L_rodilla; por
%                        debajo de ~0.371 A la recta daria L > 1 mH y la bobina
%                        en realidad se mantiene plana en su valor de senal
%                        chica (rodilla).
% -------------------------------------------------------------------------
buck.L.tipo      = 'knee';

buck.L.const = 0.70e-3;   % [H]

buck.L.a_inv = 313.9;         % [1/(H*A)]  1/L = a_inv*iL + b_inv   
buck.L.b_inv = 883.4;         % [1/H]
buck.L.a     = -0.2207e-3;    % [H/A] L = a*iL + b
buck.L.b     =  1.0617e-3;    % [H]

buck.L.knee_max = 1.00e-3;     % [H]  L maxima (valor plano de senal chica)
% Sin limite inferior artificial de L (igual que Simulink).

% Texto que se copia a los reportes y al header de Verilog.
buck.fuente = 'Ajuste sobre ensayos del CEuP; L(iL) medida';
end
