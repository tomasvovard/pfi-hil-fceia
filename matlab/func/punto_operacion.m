function op = punto_operacion(buck, R, D)
%PUNTO_OPERACION  Regimen estacionario aproximado.
%   op.Vo, op.IL, op.rizado_pp, op.iL_min, op.iL_max, op.es_mcc

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

A = buck.Vi - buck.Vsw + buck.Vd;
op.IL = (D*A - buck.Vd) / (R + buck.Rs);
op.Vo = R * op.IL;

L = inductancia(buck, max(op.IL, 0));
op.rizado_pp = A * D * (1-D) / (L * buck.fsw);
op.iL_min = op.IL - op.rizado_pp/2;
op.iL_max = op.IL + op.rizado_pp/2;
op.es_mcc = op.iL_min > 0;
end
