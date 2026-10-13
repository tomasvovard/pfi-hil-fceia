function t_evento = alinear_evento(t, senal, modo)
%ALINEAR_EVENTO  Instante del escalon (para poner el evento en t=0).
%   modo = 'flanco' : flanco de 'senal' mas cercano al trigger nominal (t~0).
%          'carga'  : cambio de 'senal' (CH4) que se mantiene en el estado final.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

t = t(:); senal = senal(:);
dt = median(diff(t));

switch modo
    case 'flanco'
        cerca = abs(t) <= 1e-3;
        idx = find(cerca);
        y = sort(senal(idx));
        umbral = (y(round(0.1*end)) + y(round(0.9*end))) / 2;
        cruces = idx(1:end-1);
        cruces = cruces((senal(cruces)-umbral) .* (senal(cruces+1)-umbral) <= 0);
        if isempty(cruces), t_evento = 0; return; end
        [~, k] = min(abs(t(cruces)));
        t_evento = t(cruces(k));

    case 'carga'
        n = max(1, round(5e-6/dt));           % mediana breve para limpiar CH4
        z = movmedian(senal, n);
        borde = round(0.1*numel(z));
        ini = median(z(1:borde));
        fin = median(z(end-borde+1:end));
        estado = (z - (ini+fin)/2) * sign(fin-ini) > 0;
        inicios = find(diff([false; estado]) == 1);
        duracion = zeros(size(inicios));
        for j = 1:numel(inicios)
            k = find(~estado(inicios(j):end), 1);
            if isempty(k), k = numel(estado) - inicios(j) + 1; end
            duracion(j) = k * dt;
        end
        cand = inicios(duracion >= 0.5e-3 & abs(t(inicios)) <= 20e-3 & inicios > 1);
        if isempty(cand), t_evento = 0; return; end
        k = cand(1);
        t_evento = (t(k-1) + t(k)) / 2;

    otherwise
        error('alinear_evento: modo desconocido (%s).', modo);
end
end
