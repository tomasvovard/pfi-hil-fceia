%% p1 - Identificacion de L(iL) a partir del rizado del CEuP
% Para cada ensayo y cada regimen (inicial y final) se ajusta una recta a iL
% en las fases ON y OFF. De la DIFERENCIA de pendientes sale L, sin depender
% del cero de la pinza ni del valor de Rs:
%     v_L = v_nodo - Vo - Rs*iL
%     L*m_on  = v_nodo_on  - Vo - Rs*iL       L*m_off = v_nodo_off - Vo - Rs*iL
%     L = (v_nodo_on - v_nodo_off) / (m_on - m_off)
% Con todos los puntos (iL, 1/L) se ajusta la recta 1/L(iL) que usa el modelo.
%
% Los ensayos sin captura en data/ se toman de med.puntos_L (puntos obtenidos
% con este mismo script sobre las capturas completas del CEuP), de modo que
% la recta ajustada es la del modelo aunque solo se disponga de E1a.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)
clear; clc; close all;
%% Setear entorno
addpath('cfg');
addpath('func');

%% Cargar parámetros
buck    = buck_params();
simcfg  = simulacion_cfg();
med     = medicion_cfg();
guarda  = 3e-6; % [s] se ignora a cada lado de cada conmutacion
excluir = {'E1b'}; % la corriente de E1b quedo con escala distinta

%% Simular
filas = [];   % ensayo, estado, iL_med, Vo, vn_on, vn_off, L [mH]
guardados = readtable(med.puntos_L, 'TextType', 'char');
for e = simcfg.ensayos
    if any(strcmp(e.nombre, excluir)), continue; end
    ie = find(strcmp(e.nombre, {simcfg.ensayos.nombre}));
    if ~isfile(fullfile(med.raiz, med.carpeta_ceup, [e.nombre '.csv']))
        g = guardados(strcmp(guardados.Ensayo, e.nombre), :);
        for v = 1:height(g)
            filas(end+1,:) = [ie g.Regimen(v) g.iL_pinza_A(v) g.Vo_V(v), ...
                g.vnodo_on_V(v) g.vnodo_off_V(v) g.L_mH(v)]; %#ok<SAGROW>
            regimen = {'inicial', 'final'};
            fprintf('%-4s %-8s | iL=%.3f A  ->  L=%.3f mH  (puntos guardados)\n', ...
                e.nombre, regimen{g.Regimen(v)}, g.iL_pinza_A(v), g.L_mH(v));
        end
        continue
    end
    d = cargar_ceup(e, med);
    tfin = d.t(end);
    ventanas = {'inicial', [-13e-3, -2e-3]              % regimen antes del evento
                'final',   [tfin-9e-3, tfin-1e-3]};     % regimen al final de la captura
    for v = 1:2
        sel = d.t >= ventanas{v,2}(1) & d.t <= ventanas{v,2}(2);
        s = pendientes(d.t(sel), d.vSw(sel), d.vO(sel), d.iL_crudo(sel), guarda, buck.fsw);
        if isempty(s), continue; end
        L = (s.vn_on - s.vn_off) / (s.m_on - s.m_off);
        filas(end+1,:) = [ie v, s.iL, s.vO, s.vn_on, s.vn_off, L*1e3]; %#ok<SAGROW>
        fprintf('%-4s %-8s | iL=%.3f A  Vo=%.2f V  vnodo=%.2f/%.2f V  ->  L=%.3f mH\n', ...
            e.nombre, ventanas{v,1}, s.iL, s.vO, s.vn_on, s.vn_off, L*1e3);
    end
end

%% Calcular
iL_pinza = filas(:,3);
iL_real  = iL_pinza - med.pinza.compensacion_A;
L_mH     = filas(:,7);

% Ajuste de la recta 1/L vs iL (la que usa el modelo) y de la recta L vs iL.
c_inv = polyfit(iL_real, 1./(L_mH*1e-3), 1);   % [1/H] : 1/L = c_inv(1)*iL + c_inv(2)
c_L   = polyfit(iL_real, L_mH*1e-3,      1);   % [H]   : L   = c_L(1)*iL + c_L(2)
res   = L_mH*1e-3 - polyval(c_L, iL_real);

fprintf('\nAjuste (iL real = pinza - %.3f A):\n', med.pinza.compensacion_A);
fprintf('  1/L [1/H] = %.1f*iL + %.1f     <- buck.L.a_inv / b_inv\n', c_inv(1), c_inv(2));
fprintf('  L  [mH]   = %+.4f*iL + %.4f\n', c_L(1)*1e3, c_L(2)*1e3);
fprintf('  residuo RMS del ajuste lineal: %.1f uH  (%d puntos)\n', 1e6*std(res), numel(L_mH));

% Figura: L vs iL, medido + recta + puntos de hoja de datos (1 mH a 0 A, 0.38 a 3.5 A).
figure('Name','Inductancia vs corriente'); hold on; grid on;
ii = linspace(0, 3.6, 50);
plot(ii, interp1([0 3.5],[1.0 0.38], ii, 'linear','extrap'), '--', 'Color',[.5 .5 .5], ...
    'DisplayName','Datasheet (0-3.5 A)');
plot(iL_pinza, L_mH, 'o', 'MarkerFaceColor',[.12 .47 .71], 'MarkerEdgeColor','none', ...
    'DisplayName','CEuP (pendientes ripple)');
plot(ii, 1e3*polyval(c_L, ii - med.pinza.compensacion_A), '-', 'Color',[.85 .16 .16], ...
    'LineWidth',1.5, 'DisplayName','Recta ajustada');
yline(1e3*buck.L.knee_max, ':', 'Color',[.5 .5 .5], 'DisplayName','L nominal');
xlabel('i_L media [A]'); ylabel('L estimada [mH]');
xlim([0 2]); ylim([0.6 1.05]); legend('Location','northeast');
title('Inductancia del CEuP - Bourns 2300LL-102');

%% 
% -------------------------------------------------------------------------
function s = pendientes(t, vSw, vO, iL, guarda, fsw)
%PENDIENTES  Rectas a iL en ON y OFF de cada periodo; medianas de la ventana.
s = [];
if numel(t) < 100, return; end
dt = median(diff(t));
alto = vSw > (max(vSw)+min(vSw))/2;
sub = find(~alto(1:end-1) &  alto(2:end)) + 1;     % flancos de subida
baj = find( alto(1:end-1) & ~alto(2:end)) + 1;     % flancos de bajada
g = max(1, round(guarda/dt));
m_on = []; m_off = []; vn_on = []; vn_off = [];
for k = 1:numel(sub)-1
    a = sub(k);  b = baj(find(baj>a,1));  c = sub(find(sub>a,1));
    if isempty(b) || isempty(c), break; end
    if a+2*g >= b-g || b+2*g >= c-g, continue; end
    p1 = polyfit(t(a+g:b-g), iL(a+g:b-g), 1);  m_on(end+1)  = p1(1); %#ok<AGROW>
    p2 = polyfit(t(b+g:c-g), iL(b+g:c-g), 1);  m_off(end+1) = p2(1); %#ok<AGROW>
    vn_on(end+1)  = median(vSw(a+g:b-g)); %#ok<AGROW>
    vn_off(end+1) = median(vSw(b+g:c-g)); %#ok<AGROW>
end
if numel(m_on) < 5, return; end
s.m_on = median(m_on);  s.m_off = median(m_off);
s.vn_on = median(vn_on); s.vn_off = median(vn_off);
s.vO = median(vO);       s.iL = median(iL);
end
