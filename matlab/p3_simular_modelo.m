%% p3 - Barrido estatico del modelo en Simulink
% Para cada carga y duty (en MCC) corre el modelo, compara el nivel y el
% rizado simulados contra el valor teorico (punto_operacion) y grafica el
% ultimo tramo de cada corrida.

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
n_reg  = simcfg.periodos_regimen;
n_graf = 4; % periodos que se grafican

%% Simular
filas = [];
for R = simcfg.cargas
    figure('Name', sprintf('Modelo estatico  R = %.1f ohm', R));
    tiledlayout(2,1,'TileSpacing','compact');
    axVo = nexttile; hold on; grid on; ylabel('V_o [V]');
    axIL = nexttile; hold on; grid on; ylabel('i_L [A]'); xlabel('tiempo [us]');
    title(axVo, sprintf('R = %.1f ohm', R));

    for D = simcfg.duties
        op = punto_operacion(buck, R, D);
        if ~op.es_mcc
            fprintf('R=%5.1f D=%.2f : MCD (iL_min teorico %.3f A), omitido\n', R, D, op.iL_min);
            continue
        end
        r = simular_buck(buck, simcfg, R, D, R, D, 0, n_reg*buck.Tsw);

        ult = r.t >= r.t(end) - n_graf*buck.Tsw;
        tt  = (r.t(ult) - r.t(find(ult,1))) * 1e6;
        plot(axVo, tt, r.vO(ult), 'DisplayName', sprintf('D=%.2f', D));
        plot(axIL, tt, r.iL(ult), 'DisplayName', sprintf('D=%.2f', D));

        Vo  = mean(r.vO(ult));   IL = mean(r.iL(ult));
        riz = max(r.iL(ult)) - min(r.iL(ult));
        filas(end+1,:) = [R D op.Vo Vo op.IL IL op.rizado_pp riz]; %#ok<SAGROW>
        fprintf('R=%5.1f D=%.2f | Vo %.3f/%.3f V (teor/sim) | IL %.4f/%.4f A | rizado %.3f/%.3f A\n', ...
            R, D, op.Vo, Vo, op.IL, IL, op.rizado_pp, riz);
    end
    legend(axVo, 'Location','best'); legend(axIL, 'Location','best');
end

tabla = array2table(filas, 'VariableNames', ...
    {'R_ohm','Duty','Vo_teor','Vo_sim','IL_teor','IL_sim','rizado_teor','rizado_sim'});
out = 'output'; if ~isfolder(out), mkdir(out); end
writetable(tabla, fullfile(out, 'p3_modelo_estatico.csv'));
