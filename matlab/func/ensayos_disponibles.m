function nombres = ensayos_disponibles(nombres, med)
%ENSAYOS_DISPONIBLES  Filtra la lista de ensayos y deja solo los que tienen
% captura del CEuP y de OHSIM en las carpetas de medicion_cfg. Avisa cuales
% se omiten.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

hay = @(n) isfile(fullfile(med.raiz, med.carpeta_ceup,  [n '.csv'])) && ...
           isfile(fullfile(med.raiz, med.carpeta_ohsim, [n '.csv']));
ok = cellfun(hay, nombres);
if any(~ok)
    fprintf('Sin capturas en %s, se omiten: %s\n', med.raiz, strjoin(nombres(~ok), ', '));
end
nombres = nombres(ok);
if isempty(nombres)
    error('ensayos_disponibles: no hay capturas en %s.', med.raiz);
end
end
