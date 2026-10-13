function L = inductancia(buck, iL)
%INDUCTANCIA  L [H] en funcion de la corriente iL [A], segun buck.L.tipo.
%   'const' -> L = buck.L.const
%   'lin'   -> 1/L = a_inv*iL + b_inv
%   'knee'  -> 1/L limitada por abajo a 1/L_max; sin piso de L.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

switch buck.L.tipo
    case 'const'
        L = buck.L.const * ones(size(iL));
    case 'lin'
        L = 1 ./ (buck.L.a_inv .* iL + buck.L.b_inv);
    case 'knee'
        L = 1 ./ max(buck.L.a_inv .* iL + buck.L.b_inv, 1/buck.L.knee_max);
    otherwise
        error('inductancia: buck.L.tipo desconocido (%s).', buck.L.tipo);
end
end
