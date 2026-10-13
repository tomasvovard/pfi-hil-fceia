function x0 = punto_periodico(buck, R, D)
%PUNTO_PERIODICO  Estado [iL; Vo] al inicio de un periodo PWM en regimen.
% Exacto para L constante; con L(iL) se evalua L en la corriente media y sirve
% como condicion inicial del Simulink (converge en pocos periodos).

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

op = punto_operacion(buck, R, D);
L  = inductancia(buck, max(op.IL, 0.05));
T  = buck.Tsw;

A = [-buck.Rs/L, -1/L; 1/buck.C, -1/(R*buck.C)];
b_on  = [(buck.Vi - buck.Vsw)/L; 0];
b_off = [-buck.Vd/L; 0];

Pon  = expm(A*D*T);       qon  = A \ ((Pon  - eye(2)) * b_on);
Poff = expm(A*(1-D)*T);   qoff = A \ ((Poff - eye(2)) * b_off);
P = Poff*Pon;   q = Poff*qon + qoff;
x0 = (eye(2) - P) \ q;
end
