%% p4 - Comparacion Modelo (Simulink) / CEuP / OHSIM por ensayo
% Para cada ensayo:
%   - una figura con las tres fuentes, version cruda y suavizada
%   - niveles inicial/final promediados y rizado de iL de cada fuente
%   - offset relativo de OHSIM (a Modelo y a CEuP) en el nivel asentado
%   - similitud: fit (compare), RMSE y correlacion, Modelo vs CEuP y OHSIM vs CEuP

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)
clear; clc; close all;

%% Setear entorno
addpath('cfg');
addpath('func');

%% Cargar parámetros
buck   = buck_params();
simcfg = simulacion_cfg();
med    = medicion_cfg();
col    = colores();
per    = simcfg.suavizado_periodos;
simcfg.comparar = ensayos_disponibles(simcfg.comparar, med);   % solo los que tienen capturas

%% Simular y comparar
niveles = {};
ajuste  = {};

for nombre = simcfg.comparar
    e = simcfg.ensayos(strcmp({simcfg.ensayos.nombre}, nombre{1}));
    tpost = min(e.post_ms, 60) / 1e3;

    m = simular_buck(buck, simcfg, e.R0, e.D0, e.R1, e.D1, simcfg.pre_ms/1e3, tpost);
    c = cargar_ceup(e, med);
    o = cargar_ohsim(e, med);
    fuentes = {'Modelo', m, col.modelo;  'CEuP', c, col.ceup;  'OHSIM', o, col.ohsim};

    %% ---------- figura: crudo y suavizado en la misma ventana ----------
    figure('Name', ['Comparacion  ' e.nombre]);
    tl = tiledlayout(2,2,'TileSpacing','compact');
    title(tl, sprintf('%s   D: %.2f\\rightarrow%.2f   R: %g\\rightarrow%g \\Omega', ...
        e.nombre, e.D0, e.D1, e.R0, e.R1));
    ax = gobjects(1,4);
    canales = {'vO','V_o [V]'; 'iL','i_L [A]'};
    titulos = {'crudo','suavizado'};
    for ch = 1:2
        for modo = 1:2
            k = (ch-1)*2 + modo;
            ax(k) = nexttile(k); hold on; grid on;
            for f = 1:3
                d = fuentes{f,2};
                y = d.(canales{ch,1});
                if modo == 2, y = suavizar(d.t, y, buck.fsw, per); end
                plot(ax(k), d.t*1e3, y, 'Color', fuentes{f,3}, ...
                    'LineWidth', 0.4 + 1.0*(modo==2), 'DisplayName', fuentes{f,1});
            end
            xline(ax(k), 0, '--k', 'HandleVisibility','off');
            xlim(ax(k), [-simcfg.pre_ms, tpost*1e3]);
            ylabel(ax(k), canales{ch,2});
            if ch == 1, title(ax(k), titulos{modo}); end
        end
    end
    xlabel(ax(3),'tiempo [ms]'); xlabel(ax(4),'tiempo [ms]');
    legend(ax(1),'Location','best'); linkaxes(ax,'x');

    %% ---------- niveles, rizado y offsets ----------
    v_ini = [-1.5e-3 -0.3e-3];
    v_fin = [0.75*tpost tpost];
    Vo_i = zeros(1,3); Vo_f = zeros(1,3); IL_i = zeros(1,3); IL_f = zeros(1,3); riz = zeros(1,3);
    for f = 1:3
        d = fuentes{f,2};
        vo_s = suavizar(d.t, d.vO, buck.fsw, per);
        il_s = suavizar(d.t, d.iL, buck.fsw, per);
        Vo_i(f) = media_ventana(d.t, vo_s, v_ini);  Vo_f(f) = media_ventana(d.t, vo_s, v_fin);
        IL_i(f) = media_ventana(d.t, il_s, v_ini);  IL_f(f) = media_ventana(d.t, il_s, v_fin);
        riz(f)  = rizado_pp(d.t, d.iL, buck.fsw, v_fin);
    end

    off_Vo = [Vo_f(3)-Vo_f(1), Vo_f(3)-Vo_f(2)];   % OHSIM vs Modelo, OHSIM vs CEuP
    off_IL = [IL_f(3)-IL_f(1), IL_f(3)-IL_f(2)];
    niveles(end+1,:) = [{e.nombre}, num2cell([Vo_i Vo_f IL_i IL_f riz off_Vo off_IL])]; %#ok<SAGROW>

    fprintf('\n===== %s =====\n', e.nombre);
    fprintf('             Modelo    CEuP     OHSIM\n');
    fprintf('Vo inicial  %7.3f  %7.3f  %7.3f  V\n', Vo_i);
    fprintf('Vo final    %7.3f  %7.3f  %7.3f  V\n', Vo_f);
    fprintf('iL inicial  %7.4f  %7.4f  %7.4f  A\n', IL_i);
    fprintf('iL final    %7.4f  %7.4f  %7.4f  A\n', IL_f);
    fprintf('rizado iL   %7.4f  %7.4f  %7.4f  A  (regimen final)\n', riz);
    fprintf('offset OHSIM  Vo: %+.3f V vs Modelo   %+.3f V vs CEuP\n', off_Vo);
    fprintf('              iL: %+.4f A vs Modelo   %+.4f A vs CEuP\n', off_IL);

    %% ---------- fit / RMSE / correlacion (envolvente, ventana post-evento) ----------
    tg = (0:2e-6:tpost).';
    ref_Vo = envolvente(c, 'vO', tg, buck.fsw, per);
    ref_iL = envolvente(c, 'iL', tg, buck.fsw, per);
    for f = [1 3]
        d = fuentes{f,2};
        x_Vo = envolvente(d, 'vO', tg, buck.fsw, per);
        x_iL = envolvente(d, 'iL', tg, buck.fsw, per);
        [fV,rV,RV] = ajuste_fit(x_Vo, ref_Vo);
        [fI,rI,RI] = ajuste_fit(x_iL, ref_iL);
        ajuste(end+1,:) = {e.nombre, fuentes{f,1}, fV, 1e3*rV, RV, fI, 1e3*rI, RI}; %#ok<SAGROW>
        fprintf('%-6s vs CEuP:  Vo fit %5.1f%%  RMSE %5.1f mV  R %.3f   |   iL fit %5.1f%%  RMSE %5.1f mA  R %.4f\n', ...
            fuentes{f,1}, fV, 1e3*rV, RV, fI, 1e3*rI, RI);
    end
end

%% Outputs
Tn = cell2table(niveles, 'VariableNames', {'Ensayo', ...
    'Vo_ini_Mod','Vo_ini_CEuP','Vo_ini_OH','Vo_fin_Mod','Vo_fin_CEuP','Vo_fin_OH', ...
    'iL_ini_Mod','iL_ini_CEuP','iL_ini_OH','iL_fin_Mod','iL_fin_CEuP','iL_fin_OH', ...
    'rizado_Mod','rizado_CEuP','rizado_OH', ...
    'offVo_OH_Mod','offVo_OH_CEuP','offiL_OH_Mod','offiL_OH_CEuP'});
Ta = cell2table(ajuste, 'VariableNames', {'Ensayo','Fuente', ...
    'Vo_fit_pct','Vo_RMSE_mV','Vo_R','iL_fit_pct','iL_RMSE_mA','iL_R'});

out = 'output'; if ~isfolder(out), mkdir(out); end
writetable(Tn, fullfile(out,'p4_niveles.csv'));
writetable(Ta, fullfile(out,'p4_ajuste.csv'));
fprintf('\nTablas -> output/p4_niveles.csv , output/p4_ajuste.csv\n');

%% Funciones
% -------------------------------------------------------------------------
function v = media_ventana(t, y, ventana)
v = mean(y(t >= ventana(1) & t <= ventana(2)), 'omitnan');
end

function y = envolvente(d, campo, tg, fsw, per)
%ENVOLVENTE  Senal suavizada de la fuente d, remuestreada en la grilla tg.
[t, iu] = unique(d.t);
y = interp1(t, suavizar(t, d.(campo)(iu), fsw, per), tg, 'linear');
end

function v = rizado_pp(t, x, fsw, ventana)
%RIZADO_PP  Mediana del pico a pico de x periodo a periodo dentro de la ventana.
sel = t >= ventana(1) & t <= ventana(2);
t = t(sel); x = x(sel);
if numel(t) < 20, v = NaN; return; end
bordes = t(1):1/fsw:t(end);
pp = zeros(numel(bordes)-1, 1);
for k = 1:numel(pp)
    m = t >= bordes(k) & t < bordes(k+1);
    if any(m), pp(k) = max(x(m)) - min(x(m)); end
end
v = median(pp(pp > 0));
end
