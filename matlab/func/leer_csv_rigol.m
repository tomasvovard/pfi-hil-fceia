function [t, canales] = leer_csv_rigol(archivo)
%LEER_CSV_RIGOL  CSV combinado del Rigol MHO934: cabecera con t0 y tInc, luego
% una columna por canal (CH1..CH4). Devuelve el tiempo y la matriz de canales.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

cab = fgetl(fopen(archivo));
t0 = str2double(regexp(cab, 't0\s*=\s*([-+0-9.eE]+)', 'tokens', 'once'));
dt = str2double(regexp(cab, 'tInc\s*=\s*([-+0-9.eE]+)', 'tokens', 'once'));
nc = numel(regexp(cab, 'CH[1-4]'));

m = readmatrix(archivo, 'NumHeaderLines', 1);
canales = m(:, 1:nc);                 % el Rigol agrega comas vacias al final
t = t0 + (0:size(canales,1)-1).' * dt;
end
