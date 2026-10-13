function [fit, rmse, R] = ajuste_fit(x, ref)
%AJUSTE_FIT  Similitud entre x y la referencia ref (tipo compare() de
% identificacion de sistemas):
%   fit [%] = 100*( 1 - ||ref - x|| / ||ref - mean(ref)|| )
%             100 = coincidencia perfecta ; 0 = no mejor que la media de ref.
%   rmse    = raiz del error cuadratico medio, en unidades de la senal.
%   R       = correlacion de Pearson.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

x = x(:); ref = ref(:);
ok = isfinite(x) & isfinite(ref);
x = x(ok); ref = ref(ok);

fit  = 100 * (1 - norm(ref - x) / norm(ref - mean(ref)));
rmse = sqrt(mean((ref - x).^2));
c = corrcoef(x, ref);
R = c(1,2);
end
