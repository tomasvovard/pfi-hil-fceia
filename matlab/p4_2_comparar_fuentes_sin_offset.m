%% p4_2 - Comparacion DINAMICA sin offset: Modelo / CEuP / OHSIM
% Compara las tres fuentes para todos los ensayos de simcfg.comparar.
%
% Idea principal:
%   - a cada fuente se le resta SU PROPIO nivel inicial pre-evento
%       DeltaVo = Vo - Vo0
%       DeltaiL = iL - iL0
%   - NO se vuelve a quitar la media de toda la respuesta: una diferencia
%     real de ganancia/amplitud final debe penalizar el fit.
%   - las metricas usan solamente la ventana util alrededor del evento.
%     El extremo final de OHSIM se excluye para evitar el segundo escalon / 
%     artefacto de logging que aparece cuando termina el ensayo.
%
% Para cada ensayo genera:
%   1) Figura 2x2:
%        - DeltaVo de las tres fuentes
%        - error DeltaVo respecto de CEuP
%        - DeltaiL de las tres fuentes
%        - error DeltaiL respecto de CEuP
%   2) Tabla por fuente con:
%        nivel inicial absoluto restado, delta final, rise time 10-90%,
%        settling time 2%, sobrepico, pico/tiempo al pico y rizado de iL.
%   3) Tabla por pares (Modelo-CEuP, OHSIM-CEuP, OHSIM-Modelo) con:
%        fit NRMSE tipo compare(), correlacion de Pearson, RMSE, MAE,
%        error maximo, RMSE/rango, error de valor final y diferencias de
%        rise time, settling time, overshoot y peak time.
%   4) Resumen promedio de las metricas principales para cada par.
%
% Salidas:
%   output/p4_2_fuentes.csv
%   output/p4_2_metricas_pares.csv
%   output/p4_2_resumen.csv
%   output/p4_2_<ensayo>.png

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

clear; clc; close all;

%% Entorno
addpath('cfg');
addpath('func');

buck   = buck_params();
simcfg = simulacion_cfg();
med    = medicion_cfg();
col    = colores();
per    = simcfg.suavizado_periodos;
simcfg.comparar = ensayos_disponibles(simcfg.comparar, med);   % solo los que tienen capturas

%% Configuracion de esta comparacion
cmp.pre_ref_s       = [-1.5e-3 -0.3e-3]; % ventana para estimar Vo0/iL0
cmp.pre_plot_ms     = 2.0;               % solo mostrar entorno cercano al evento
cmp.margen_final_ms = 4.0;               % ignora final de captura (artefacto OHSIM)
cmp.dt_grid_s       = 2e-6;              % grilla comun para comparar fuentes
cmp.final_frac      = 0.20;              % ultimo 20% -> nivel final
cmp.settle_frac     = 0.02;              % banda de asentamiento +/-2%
cmp.guardar         = true;

% Pares: primera columna = fuente evaluada; segunda = referencia.
pair_idx = [1 2;   % Modelo vs CEuP
            3 2;   % OHSIM  vs CEuP
            3 1];  % OHSIM  vs Modelo

%% Templates: evita estructuras incompatibles al crecer tablas
src_template = struct( ...
    'Ensayo','', 'Fuente','', ...
    'Vo0_abs_V',NaN, 'iL0_abs_A',NaN, ...
    'dVo_final_V',NaN, 'Vo_rise10_90_ms',NaN, 'Vo_settle2_ms',NaN, ...
    'Vo_overshoot_pct',NaN, 'Vo_peak_V',NaN, 'Vo_peak_ms',NaN, ...
    'diL_final_A',NaN, 'iL_rise10_90_ms',NaN, 'iL_settle2_ms',NaN, ...
    'iL_overshoot_pct',NaN, 'iL_peak_A',NaN, 'iL_peak_ms',NaN, ...
    'iL_ripple_pp_A',NaN);

pair_template = struct( ...
    'Ensayo','', 'Comparacion','', 'Fuente','', 'Referencia','', ...
    'Vo_fit_pct',NaN, 'Vo_corr',NaN, 'Vo_RMSE_mV',NaN, 'Vo_MAE_mV',NaN, ...
    'Vo_MaxErr_mV',NaN, 'Vo_RMSE_span_pct',NaN, 'Vo_final_err_pct',NaN, ...
    'Vo_dRise_ms',NaN, 'Vo_dSettle_ms',NaN, 'Vo_dOvershoot_pp',NaN, 'Vo_dPeakTime_ms',NaN, ...
    'iL_fit_pct',NaN, 'iL_corr',NaN, 'iL_RMSE_mA',NaN, 'iL_MAE_mA',NaN, ...
    'iL_MaxErr_mA',NaN, 'iL_RMSE_span_pct',NaN, 'iL_final_err_pct',NaN, ...
    'iL_dRise_ms',NaN, 'iL_dSettle_ms',NaN, 'iL_dOvershoot_pp',NaN, 'iL_dPeakTime_ms',NaN);

src_rows  = repmat(src_template, 0, 1);
pair_rows = repmat(pair_template, 0, 1);
figs = gobjects(0);
fig_names = {};

%% ===================== COMPARACION =====================
for in = 1:numel(simcfg.comparar)
    nombre = simcfg.comparar{in};
    idx = find(strcmp({simcfg.ensayos.nombre}, nombre), 1);
    if isempty(idx)
        warning('Ensayo %s no existe en simulacion_cfg.m. Se omite.', nombre);
        continue;
    end
    e = simcfg.ensayos(idx);

    % Ventana completa que usa p4, pero se reserva un margen al final para
    % no incluir el retorno/segundo evento que puede aparecer en OHSIM.
    tpost_full = min(e.post_ms, 60) / 1e3;
    tpost = tpost_full - cmp.margen_final_ms/1e3;
    if tpost <= 0.5*tpost_full
        tpost = 0.8*tpost_full;
    end

    fprintf('\n============================================================\n');
    fprintf('%s   D %.3f -> %.3f   R %.3f -> %.3f ohm\n', ...
        e.nombre, e.D0, e.D1, e.R0, e.R1);
    fprintf('Ventana dinamica usada: 0 ... %.2f ms (%.2f ms finales ignorados)\n', ...
        1e3*tpost, 1e3*(tpost_full-tpost));

    % Mismo flujo de datos que p4.
    m = simular_buck(buck, simcfg, e.R0, e.D0, e.R1, e.D1, ...
        simcfg.pre_ms/1e3, tpost_full);
    c = cargar_ceup(e, med);
    o = cargar_ohsim(e, med);

    fuentes = {'Modelo', m, col.modelo; ...
               'CEuP',   c, col.ceup;   ...
               'OHSIM',  o, col.ohsim};

    % -------- Restar SOLO el punto de operacion inicial de cada fuente --------
    Vo0 = NaN(1,3); iL0 = NaN(1,3);
    for f = 1:3
        d = fuentes{f,2};
        [d, Vo0(f), iL0(f)] = hacer_incremental(d, buck, per, cmp.pre_ref_s);
        fuentes{f,2} = d;
    end

    % Grilla comun post-evento para todas las metricas dinamicas.
    tg = (0:cmp.dt_grid_s:tpost).';
    Vo = cell(1,3); IL = cell(1,3);
    fVo = repmat(carac_vacia(), 1, 3);
    fIL = repmat(carac_vacia(), 1, 3);

    v_fin = [(1-cmp.final_frac)*tpost, tpost];

    for f = 1:3
        d = fuentes{f,2};
        Vo{f} = envolvente(d, 'vO', tg, buck.fsw, per);
        IL{f} = envolvente(d, 'iL', tg, buck.fsw, per);

        fVo(f) = caracteristicas_respuesta(tg, Vo{f}, cmp.final_frac, cmp.settle_frac);
        fIL(f) = caracteristicas_respuesta(tg, IL{f}, cmp.final_frac, cmp.settle_frac);

        riz = rizado_pp(d.t, d.iL, buck.fsw, v_fin);

        r = src_template;
        r.Ensayo = e.nombre;
        r.Fuente = fuentes{f,1};
        r.Vo0_abs_V = Vo0(f);
        r.iL0_abs_A = iL0(f);
        r.dVo_final_V = fVo(f).final;
        r.Vo_rise10_90_ms = 1e3*fVo(f).rise;
        r.Vo_settle2_ms = 1e3*fVo(f).settle;
        r.Vo_overshoot_pct = fVo(f).overshoot;
        r.Vo_peak_V = fVo(f).peak;
        r.Vo_peak_ms = 1e3*fVo(f).tpeak;
        r.diL_final_A = fIL(f).final;
        r.iL_rise10_90_ms = 1e3*fIL(f).rise;
        r.iL_settle2_ms = 1e3*fIL(f).settle;
        r.iL_overshoot_pct = fIL(f).overshoot;
        r.iL_peak_A = fIL(f).peak;
        r.iL_peak_ms = 1e3*fIL(f).tpeak;
        r.iL_ripple_pp_A = riz;
        src_rows(end+1) = r; %#ok<SAGROW>
    end

    % --------------------- Comparaciones por pares ---------------------
    for kp = 1:size(pair_idx,1)
        itest = pair_idx(kp,1);
        iref  = pair_idx(kp,2);
        test_name = fuentes{itest,1};
        ref_name  = fuentes{iref,1};

        mv = metricas_par(tg, Vo{itest}, Vo{iref}, cmp.final_frac);
        mi = metricas_par(tg, IL{itest}, IL{iref}, cmp.final_frac);

        r = pair_template;
        r.Ensayo = e.nombre;
        r.Comparacion = [test_name '_vs_' ref_name];
        r.Fuente = test_name;
        r.Referencia = ref_name;

        r.Vo_fit_pct = mv.fit;
        r.Vo_corr = mv.corr;
        r.Vo_RMSE_mV = 1e3*mv.rmse;
        r.Vo_MAE_mV = 1e3*mv.mae;
        r.Vo_MaxErr_mV = 1e3*mv.maxerr;
        r.Vo_RMSE_span_pct = mv.rmse_span_pct;
        r.Vo_final_err_pct = mv.final_err_pct;
        r.Vo_dRise_ms = 1e3*(fVo(itest).rise - fVo(iref).rise);
        r.Vo_dSettle_ms = 1e3*(fVo(itest).settle - fVo(iref).settle);
        r.Vo_dOvershoot_pp = fVo(itest).overshoot - fVo(iref).overshoot;
        r.Vo_dPeakTime_ms = 1e3*(fVo(itest).tpeak - fVo(iref).tpeak);

        r.iL_fit_pct = mi.fit;
        r.iL_corr = mi.corr;
        r.iL_RMSE_mA = 1e3*mi.rmse;
        r.iL_MAE_mA = 1e3*mi.mae;
        r.iL_MaxErr_mA = 1e3*mi.maxerr;
        r.iL_RMSE_span_pct = mi.rmse_span_pct;
        r.iL_final_err_pct = mi.final_err_pct;
        r.iL_dRise_ms = 1e3*(fIL(itest).rise - fIL(iref).rise);
        r.iL_dSettle_ms = 1e3*(fIL(itest).settle - fIL(iref).settle);
        r.iL_dOvershoot_pp = fIL(itest).overshoot - fIL(iref).overshoot;
        r.iL_dPeakTime_ms = 1e3*(fIL(itest).tpeak - fIL(iref).tpeak);

        pair_rows(end+1) = r; %#ok<SAGROW>

        fprintf('%-15s  Vo: fit %6.1f%%  corr %.4f  RMSE %7.2f mV  final %+6.2f%%', ...
            r.Comparacion, r.Vo_fit_pct, r.Vo_corr, r.Vo_RMSE_mV, r.Vo_final_err_pct);
        fprintf('  |  iL: fit %6.1f%%  corr %.4f  RMSE %7.2f mA  final %+6.2f%%\n', ...
            r.iL_fit_pct, r.iL_corr, r.iL_RMSE_mA, r.iL_final_err_pct);
    end

    % --------------------------- Figura ---------------------------
    fig = figure('Name', ['p4_2 ' e.nombre]);
    figs(end+1) = fig; %#ok<SAGROW>
    fig_names{end+1} = e.nombre; %#ok<SAGROW>
    tl = tiledlayout(2,2,'TileSpacing','compact','Padding','compact');
    title(tl, sprintf('%s   D %.2f\\rightarrow%.2f   R %g\\rightarrow%g \\Omega   (comparacion incremental)', ...
        e.nombre, e.D0, e.D1, e.R0, e.R1));

    % Delta Vo
    ax1 = nexttile(1); hold(ax1,'on'); grid(ax1,'on');
    for f = 1:3
        d = fuentes{f,2};
        y = suavizar(d.t, d.vO, buck.fsw, per);
        plot(ax1, d.t*1e3, y, 'Color', fuentes{f,3}, 'LineWidth',1.2, ...
            'DisplayName',fuentes{f,1});
    end
    xline(ax1,0,'--k','HandleVisibility','off');
    xlim(ax1,[-cmp.pre_plot_ms 1e3*tpost]);
    ylabel(ax1,'\DeltaV_o [V]');
    title(ax1,'Respuesta');
    legend(ax1,'Location','best');

    % Error Vo respecto de CEuP
    ax2 = nexttile(2); hold(ax2,'on'); grid(ax2,'on');
    plot(ax2,tg*1e3,1e3*(Vo{1}-Vo{2}), 'Color',col.modelo, 'LineWidth',1.1, ...
        'DisplayName','Modelo - CEuP');
    plot(ax2,tg*1e3,1e3*(Vo{3}-Vo{2}), 'Color',col.ohsim, 'LineWidth',1.1, ...
        'DisplayName','OHSIM - CEuP');
    yline(ax2,0,':k','HandleVisibility','off');
    xlim(ax2,[0 1e3*tpost]);
    ylabel(ax2,'error \DeltaV_o [mV]');
    title(ax2,'Error respecto de CEuP');
    legend(ax2,'Location','best');

    % Delta iL
    ax3 = nexttile(3); hold(ax3,'on'); grid(ax3,'on');
    for f = 1:3
        d = fuentes{f,2};
        y = suavizar(d.t, d.iL, buck.fsw, per);
        plot(ax3, d.t*1e3, y, 'Color', fuentes{f,3}, 'LineWidth',1.2, ...
            'DisplayName',fuentes{f,1});
    end
    xline(ax3,0,'--k','HandleVisibility','off');
    xlim(ax3,[-cmp.pre_plot_ms 1e3*tpost]);
    ylabel(ax3,'\Deltai_L [A]');
    xlabel(ax3,'tiempo [ms]');

    % Error iL respecto de CEuP
    ax4 = nexttile(4); hold(ax4,'on'); grid(ax4,'on');
    plot(ax4,tg*1e3,1e3*(IL{1}-IL{2}), 'Color',col.modelo, 'LineWidth',1.1, ...
        'DisplayName','Modelo - CEuP');
    plot(ax4,tg*1e3,1e3*(IL{3}-IL{2}), 'Color',col.ohsim, 'LineWidth',1.1, ...
        'DisplayName','OHSIM - CEuP');
    yline(ax4,0,':k','HandleVisibility','off');
    xlim(ax4,[0 1e3*tpost]);
    ylabel(ax4,'error \Deltai_L [mA]');
    xlabel(ax4,'tiempo [ms]');
    legend(ax4,'Location','best');
end

%% ===================== TABLAS / RESUMEN =====================
Tsrc  = struct2table(src_rows);
Tpair = struct2table(pair_rows);
Tres  = resumen_pares(Tpair);

fprintf('\n\n================ PARAMETROS POR FUENTE ================\n');
disp(Tsrc);
fprintf('\n================ METRICAS POR PARES ================\n');
disp(Tpair);
fprintf('\n================ RESUMEN PROMEDIO ================\n');
disp(Tres);

fprintf(['\nInterpretacion:\n' ...
    '  * el offset absoluto NO participa: cada fuente arranca en Delta=0.\n' ...
    '  * el fit SI penaliza diferencias reales de ganancia/amplitud final.\n' ...
    '  * corr mide semejanza de forma, aun si la amplitud no coincide.\n' ...
    '  * RMSE/MAE/MaxErr conservan unidades fisicas.\n' ...
    '  * dRise/dSettle/dPeakTime comparan directamente la velocidad de la dinamica.\n']);

%% Guardar
if cmp.guardar
    out = 'output';
    if ~isfolder(out), mkdir(out); end

    writetable(Tsrc,  fullfile(out,'p4_2_fuentes.csv'));
    writetable(Tpair, fullfile(out,'p4_2_metricas_pares.csv'));
    writetable(Tres,  fullfile(out,'p4_2_resumen.csv'));

    for k = 1:numel(figs)
        saveas(figs(k), fullfile(out, ['p4_2_' fig_names{k} '.png']));
    end

    fprintf('\nResultados -> output/p4_2_*.csv y output/p4_2_*.png\n');
end

%% ===================== FUNCIONES LOCALES =====================
function [d, Vo0, iL0] = hacer_incremental(d, buck, per, ventana)
%HACER_INCREMENTAL Resta a Vo e iL el promedio pre-evento de SU fuente.
%El promedio se calcula sobre la envolvente suavizada para ser robusto al
%rizado de conmutacion, pero se resta de la senal cruda.
    vo_s = suavizar(d.t, d.vO, buck.fsw, per);
    il_s = suavizar(d.t, d.iL, buck.fsw, per);

    Vo0 = media_ventana(d.t, vo_s, ventana);
    iL0 = media_ventana(d.t, il_s, ventana);

    if ~isfinite(Vo0) || ~isfinite(iL0)
        error('No se pudo estimar el nivel inicial en la ventana pre-evento.');
    end

    d.vO = d.vO - Vo0;
    d.iL = d.iL - iL0;
end

function v = media_ventana(t, y, ventana)
    t = t(:); y = y(:);
    sel = t >= ventana(1) & t <= ventana(2) & isfinite(y);
    if nnz(sel) < 3
        v = NaN;
    else
        v = mean(y(sel), 'omitnan');
    end
end

function y = envolvente(d, campo, tg, fsw, per)
%ENVOLVENTE Suaviza y remuestrea sin extrapolar a una grilla comun.
    t = d.t(:);
    x = d.(campo);
    x = x(:);
    ok = isfinite(t) & isfinite(x);
    t = t(ok); x = x(ok);
    [t, ord] = sort(t);
    x = x(ord);
    [t, iu] = unique(t, 'stable');
    x = x(iu);
    xs = suavizar(t, x, fsw, per);
    y = interp1(t, xs, tg, 'linear', NaN);
end

function m = metricas_par(t, test, ref, final_frac)
%METRICAS_PAR Compara dos respuestas incrementales sobre la misma grilla.
%Fit tipo compare/System Identification:
%   fit = 100*(1 - ||ref-test|| / ||ref-mean(ref)||)
%Una coincidencia perfecta da 100%. Puede ser negativo si el ajuste es malo.
    t = t(:); test = test(:); ref = ref(:);
    ok = isfinite(t) & isfinite(test) & isfinite(ref);
    t = t(ok); test = test(ok); ref = ref(ok);

    m.fit = NaN; m.corr = NaN; m.rmse = NaN; m.mae = NaN;
    m.maxerr = NaN; m.rmse_span_pct = NaN; m.final_err_pct = NaN;
    if numel(t) < 5
        return;
    end

    err = test - ref;
    den = norm(ref - mean(ref));
    if den > eps
        m.fit = 100*(1 - norm(err)/den);
    end

    cc = corrcoef(test, ref);
    if all(size(cc) == [2 2])
        m.corr = cc(1,2);
    end

    m.rmse = sqrt(mean(err.^2));
    m.mae = mean(abs(err));
    m.maxerr = max(abs(err));

    span = max(ref) - min(ref);
    if span > eps
        m.rmse_span_pct = 100*m.rmse/span;
    end

    tf0 = t(end) - final_frac*(t(end)-t(1));
    sf = t >= tf0;
    yf_test = mean(test(sf), 'omitnan');
    yf_ref  = mean(ref(sf),  'omitnan');
    if abs(yf_ref) > eps
        m.final_err_pct = 100*(yf_test-yf_ref)/abs(yf_ref);
    end
end

function c = carac_vacia()
    c = struct('final',NaN,'rise',NaN,'settle',NaN,'overshoot',NaN, ...
               'peak',NaN,'tpeak',NaN);
end

function c = caracteristicas_respuesta(t, y, final_frac, settle_frac)
%CARACTERISTICAS_RESPUESTA Caracteristicas de una respuesta incremental.
%Funciona tanto para escalones positivos como negativos. Rise time = primera
%transicion 10->90% en la direccion del valor final. Settling = primer instante
%despues del cual TODA la respuesta restante queda dentro de +/-2% del final.
    c = carac_vacia();
    t = t(:); y = y(:);
    ok = isfinite(t) & isfinite(y);
    t = t(ok); y = y(ok);
    if numel(t) < 5
        return;
    end

    tf0 = t(end) - final_frac*(t(end)-t(1));
    sf = t >= tf0;
    yf = mean(y(sf), 'omitnan');
    c.final = yf;

    A = abs(yf);
    if A <= max(1e-12, 1e-6*max(abs(y)))
        return;
    end

    sgn = sign(yf);
    yd = sgn*y;  % respuesta en direccion positiva, aunque el escalon sea negativo

    % Rise time 10-90%.
    i10 = find(yd >= 0.10*A, 1, 'first');
    i90 = find(yd >= 0.90*A, 1, 'first');
    if ~isempty(i10) && ~isempty(i90) && i90 >= i10
        c.rise = t(i90) - t(i10);
    end

    % Pico y sobrepico en la direccion de la respuesta final.
    [pkd, ipk] = max(yd);
    c.peak = sgn*pkd;
    c.tpeak = t(ipk);
    c.overshoot = max(0, 100*(pkd-A)/A);

    % Settling time al 2% del cambio final.
    tol = settle_frac*A;
    outside = abs(y-yf) > tol;
    ilast = find(outside, 1, 'last');
    if isempty(ilast)
        c.settle = 0;
    elseif ilast < numel(t)
        c.settle = t(ilast+1);
    end
end

function v = rizado_pp(t, x, fsw, ventana)
%RIZADO_PP Mediana del pico a pico por periodo PWM en regimen final.
%Restar un offset no altera el rizado, por lo que sirve tambien con DeltaiL.
    t = t(:); x = x(:);
    sel = t >= ventana(1) & t <= ventana(2) & isfinite(x);
    t = t(sel); x = x(sel);
    if numel(t) < 20
        v = NaN; return;
    end

    bordes = t(1):1/fsw:t(end);
    pp = NaN(max(numel(bordes)-1,0),1);
    for k = 1:numel(pp)
        mk = t >= bordes(k) & t < bordes(k+1);
        if nnz(mk) >= 2
            pp(k) = max(x(mk)) - min(x(mk));
        end
    end
    pp = pp(isfinite(pp) & pp > 0);
    if isempty(pp)
        v = NaN;
    else
        v = median(pp);
    end
end

function T = resumen_pares(Tp)
%RESUMEN_PARES Promedio entre ensayos para cada comparacion.
    if isempty(Tp)
        T = table();
        return;
    end

    pares = unique(Tp.Comparacion, 'stable');
    rows = cell(numel(pares),11);
    for k = 1:numel(pares)
        m = strcmp(Tp.Comparacion, pares{k});
        rows{k,1}  = pares{k};
        rows{k,2}  = mean(Tp.Vo_fit_pct(m), 'omitnan');
        rows{k,3}  = mean(Tp.Vo_corr(m), 'omitnan');
        rows{k,4}  = mean(Tp.Vo_RMSE_mV(m), 'omitnan');
        rows{k,5}  = mean(abs(Tp.Vo_final_err_pct(m)), 'omitnan');
        rows{k,6}  = mean(abs(Tp.Vo_dRise_ms(m)), 'omitnan');
        rows{k,7}  = mean(Tp.iL_fit_pct(m), 'omitnan');
        rows{k,8}  = mean(Tp.iL_corr(m), 'omitnan');
        rows{k,9}  = mean(Tp.iL_RMSE_mA(m), 'omitnan');
        rows{k,10} = mean(abs(Tp.iL_final_err_pct(m)), 'omitnan');
        rows{k,11} = mean(abs(Tp.iL_dRise_ms(m)), 'omitnan');
    end

    T = cell2table(rows, 'VariableNames', { ...
        'Comparacion', ...
        'Vo_fit_mean_pct','Vo_corr_mean','Vo_RMSE_mean_mV','Vo_abs_final_err_mean_pct','Vo_abs_dRise_mean_ms', ...
        'iL_fit_mean_pct','iL_corr_mean','iL_RMSE_mean_mA','iL_abs_final_err_mean_pct','iL_abs_dRise_mean_ms'});
end
