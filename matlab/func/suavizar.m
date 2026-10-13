function y = suavizar(t, x, fsw, periodos)
%SUAVIZAR  Media movil de x sobre 'periodos' periodos de PWM (envolvente).
% t puede tener paso variable (p.ej. la salida de un solver de Simulink):
% se resamplea a una grilla uniforme ANTES de promediar, porque una media
% movil por cantidad de muestras (movmean) sobre paso variable no cubre un
% periodo real de PWM en las zonas de paso grande y deja pasar rizado.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)
if nargin < 4, periodos = 1; end
t_in = t(:); x = x(:);
[tp, iu] = unique(t_in, 'last');   % puntos de muestreo para interp1 (sin duplicados)
xp = x(iu);

muestras_por_periodo = 50;               % resolucion de la grilla interna
dt = 1 / (fsw * muestras_por_periodo);
tu = (tp(1):dt:tp(end)).';
xu = interp1(tp, xp, tu, 'linear');

n = round(periodos * muestras_por_periodo);
yu = movmean(xu, n, 'Endpoints', 'shrink');

y = interp1(tu, yu, t_in, 'linear');   % de vuelta sobre el t ORIGINAL (mismo largo, dup. incluidos)
end
