%% p6_identificar_ft - Identificacion de FT de 2do orden: Modelo / CEuP / OHSIM
% Identifica, para cada fuente, la FT incremental duty -> Vo.
% Antes del ajuste, cada fuente se lleva a variables incrementales:
%   DeltaVo = Vo - Vo0, DeltaIL = IL - IL0, DeltaD = D - D0,
% de modo que las tres respuestas parten de cero y el ajuste describe la
% dinamica, no las diferencias de offset entre fuentes:
%
%        b0
% G(s)= -----------------
%       s^2 + a1*s + a0
%
% y compara:
%   1) coeficientes identificados: a2=1, a1, a0, b0 y ganancia DC K0
%   2) parametros fisicos efectivos R, L, C del modelo no ideal del buck
%   3) forma fisica no normalizada:
%
%             Veq
% Gvd(s)= -------------------------------------------
%          LC*s^2 + (L/R + Rs*C)*s + (1 + Rs/R)
%
% donde Veq = Vi - Vsw + Vd.
%
% IMPORTANTE:
% - Usar ensayos de ESCALON DE DUTY CON CARGA FIJA (E1a, E1b, E3a, E3b).
% - No usar escalones de carga para Gvd: al cambiar R cambia la propia planta.
% - OHSIM puede tener artefactos al principio/final del buffer o un evento de
%   fin de ensayo. La identificacion usa solo una ventana alrededor de t=0,
%   por lo que esos eventos quedan deliberadamente fuera.
% - Como L depende de iL, la L obtenida es una L EFECTIVA local del transitorio.
%
% Requiere System Identification Toolbox (tfest, iddata).

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

%clear; clc; close all;

%% Entorno del proyecto
addpath('cfg');
addpath('func');

buck   = buck_params();
simcfg = simulacion_cfg();
med    = medicion_cfg();

%% ===================== CONFIGURACION =====================
% Escalones de duty con carga fija (E1b se excluye: su corriente quedo con otra escala).
idcfg.ensayos = ensayos_disponibles({'E1a','E3a','E3b'}, med);   % solo los que tienen capturas

% Ventana usada para identificar la dinamica alrededor del escalon principal.
% Con esto se ignoran los picos/eventos de OHSIM pegados al principio/final
% del buffer y, en particular, cualquier segundo escalon de fin de ensayo.
idcfg.pre_ms  = 1.5;
idcfg.post_ms = 18.0;

% Suavizado de la envolvente antes de identificar. Un periodo PWM elimina la
% mayor parte del rizado de conmutacion sin alterar apreciablemente la dinamica
% lenta RLC.
idcfg.suavizado_periodos = 1;

% Remuestreo uniforme para tfest. Los CSV tienen muchisimas muestras; no hace
% falta identificar a la frecuencia original del osciloscopio.
idcfg.Ts_id = 20e-6;          % [s] 50 kHz

% Fuente usada como referencia para diferencias porcentuales.
idcfg.referencia = 'CEuP';

% Guardar tablas y figuras.
idcfg.guardar = true;

% Si true, ademas del RLC libre se calcula L,C fijando R al valor conocido del
% ensayo. Esta segunda estimacion es bastante mas robusta experimentalmente.
idcfg.calcular_R_conocida = true;

%% Comprobacion de toolbox
if exist('tfest','file') ~= 2 || exist('iddata','file') ~= 2
    error(['Este script requiere System Identification Toolbox: ' ...
           'no se encontraron tfest/iddata.']);
end

%% Contenedores de resultados
% Usar templates con los mismos campos en todas las filas.  Inicializar con
% struct([]) y luego asignar un struct con campos puede producir
% "Subscripted assignment between dissimilar structures" en MATLAB.
coef_template = struct( ...
    'Ensayo','', 'Fuente','', ...
    'a2',NaN, 'a1',NaN, 'a0',NaN, 'b0',NaN, 'Kdc',NaN, ...
    'wn_rad_s',NaN, 'zeta',NaN, 'fit_pct',NaN, 'RMSE_mV',NaN, ...
    'corr',NaN, 'Vo0_V',NaN, 'iL0_A',NaN);

phys_template = struct( ...
    'Ensayo','', 'Fuente','', ...
    'R_fit_ohm',NaN, 'L_fit_mH',NaN, 'C_fit_uF',NaN, ...
    'R_nom_ohm',NaN, 'L_local_modelo_mH',NaN, 'C_medido_uF',NaN, ...
    'L_Rconocida_mH',NaN, 'C_Rconocida_uF',NaN, ...
    'residuo_fisico_pct',NaN, 'A2_LC',NaN, 'A1',NaN, 'A0',NaN, ...
    'B0_Veq',NaN, 'escala_fisica',NaN);

coef_rows = repmat(coef_template, 0, 1);
phys_rows = repmat(phys_template, 0, 1);
figs = gobjects(0);

%% ===================== IDENTIFICACION =====================
for ie = 1:numel(idcfg.ensayos)
    nombre = idcfg.ensayos{ie};
    idx = find(strcmp({simcfg.ensayos.nombre}, nombre), 1);
    if isempty(idx)
        error('Ensayo %s no existe en simulacion_cfg.m.', nombre);
    end
    e = simcfg.ensayos(idx);

    % Para identificar Gvd la entrada debe ser duty y la carga debe permanecer fija.
    if e.D0 == e.D1
        error('%s no tiene escalon de duty. Elegir E1a/E1b/E3a/E3b.', e.nombre);
    end
    if e.R0 ~= e.R1
        error('%s cambia la carga durante el ensayo; no es valido para una unica Gvd LTI.', e.nombre);
    end

    du = e.D1 - e.D0;
    fprintf('\n============================================================\n');
    fprintf('Ensayo %s: D %.4f -> %.4f (DeltaD=%+.4f), R = %.3f ohm\n', ...
        e.nombre, e.D0, e.D1, du, e.R0);

    % Simular el mismo ensayo y cargar las dos mediciones.
    tpost_sim = max(e.post_ms, idcfg.post_ms) / 1e3;
    m = simular_buck(buck, simcfg, e.R0, e.D0, e.R1, e.D1, ...
        simcfg.pre_ms/1e3, tpost_sim);
    c = cargar_ceup(e, med);
    o = cargar_ohsim(e, med);

    fuentes = {'Modelo', m; 'CEuP', c; 'OHSIM', o};

    % Figura de validacion de los tres ajustes.
    f = figure('Name', ['FT 2do orden - ' e.nombre]);
    figs(end+1) = f; %#ok<SAGROW>
    tl = tiledlayout(3,1,'TileSpacing','compact');
    title(tl, sprintf('%s: identificacion G_{vd}(s), D %.3f \\rightarrow %.3f, R=%.1f \\Omega', ...
        e.nombre, e.D0, e.D1, e.R0));

    for is = 1:size(fuentes,1)
        fuente = fuentes{is,1};
        d      = fuentes{is,2};

        % Preparar senales incrementales y remuestreadas.
        p = preparar_datos(d, du, buck, idcfg);

        % Modelo continuo de 2 polos y 0 ceros.
        z = iddata(p.y, p.u, idcfg.Ts_id);
        z.InputName  = {'duty'};
        z.OutputName = {'Vo'};
        z.TimeUnit   = 'seconds';
        z.InterSample = 'zoh';

        % Forzar modelo CONTINUO: los coeficientes se interpretan en s.
        sys_id = tfest(z, 2, 0, 'Ts', 0);
        G = tf(sys_id);

        [num, den] = tfdata(G, 'v');
        [num, den] = normalizar_polinomios(num, den);

        if numel(den) ~= 3
            error('%s/%s: se esperaba denominador de segundo orden.', e.nombre, fuente);
        end

        a2 = den(1);             % por normalizacion, = 1
        a1 = den(2);
        a0 = den(3);
        b0 = num(end);           % nz=0 -> numerador constante
        K0 = dcgain(G);

        if a0 > 0
            wn = sqrt(a0);
            zeta = a1/(2*wn);
        else
            wn = NaN;
            zeta = NaN;
        end

        % Respuesta del modelo identificado sobre la misma entrada real DeltaD.
        % lsim trabaja mas limpiamente con una grilla que arranca en t=0;
        % el eje fisico p.t sigue conservando el evento principal en 0 ms.
        yhat = lsim(G, p.u, p.t - p.t(1));
        [fit_pct, rmse_V, corr_R] = metricas_ajuste(p.y, yhat);

        % Parametros fisicos efectivos.
        % Se usa el valor local de L(iL) del modelo solo como semilla/criterio
        % para elegir la rama fisicamente razonable de la solucion.
        L_ref = inductancia(buck, p.iL0);
        phys = extraer_rlc(a1, a0, b0, buck, e.R0, L_ref, idcfg.calcular_R_conocida);

        % Forma fisica no normalizada de LA MISMA FT identificada.
        % tfest entrega denominador monico. Para recuperar una escala fisica
        % unica usamos que, para el buck promediado no ideal, el numerador
        % incremental duty->Vo es Veq = Vi - Vsw + Vd. Entonces:
        %   alpha = Veq/b0 = LC
        %   [A2 A1 A0] = alpha*[1 a1 a0].
        Veq = buck.Vi - buck.Vsw + buck.Vd;
        if isfinite(b0) && abs(b0) > eps
            alpha_fis = Veq / b0;
            A2 = alpha_fis;
            A1 = alpha_fis * a1;
            A0 = alpha_fis * a0;
        else
            alpha_fis = NaN; A2 = NaN; A1 = NaN; A0 = NaN;
        end
        B0 = Veq;

        % Guardar coeficientes identificados.
        r = coef_template;
        r.Ensayo = e.nombre;
        r.Fuente = fuente;
        r.a2 = a2;
        r.a1 = a1;
        r.a0 = a0;
        r.b0 = b0;
        r.Kdc = K0;
        r.wn_rad_s = wn;
        r.zeta = zeta;
        r.fit_pct = fit_pct;
        r.RMSE_mV = 1e3*rmse_V;
        r.corr = corr_R;
        r.Vo0_V = p.y0;
        r.iL0_A = p.iL0;
        coef_rows(end+1) = r; %#ok<SAGROW>

        % Guardar parametros fisicos.
        q = phys_template;
        q.Ensayo = e.nombre;
        q.Fuente = fuente;
        q.R_fit_ohm = phys.R;
        q.L_fit_mH = 1e3*phys.L;
        q.C_fit_uF = 1e6*phys.C;
        q.R_nom_ohm = e.R0;
        q.L_local_modelo_mH = 1e3*L_ref;
        q.C_medido_uF = 1e6*buck.C;
        q.L_Rconocida_mH = 1e3*phys.L_Rknown;
        q.C_Rconocida_uF = 1e6*phys.C_Rknown;
        q.residuo_fisico_pct = 100*phys.residuo;
        q.A2_LC = A2;
        q.A1 = A1;
        q.A0 = A0;
        q.B0_Veq = B0;
        q.escala_fisica = alpha_fis;
        phys_rows(end+1) = q; %#ok<SAGROW>

        % Mostrar FT identificada.
        fprintf('\n%-7s\n', fuente);
        fprintf('  G(s) = %.6g / (s^2 + %.6g s + %.6g)\n', b0, a1, a0);
        fprintf('  Kdc = %.6g   wn = %.3f rad/s   zeta = %.4f\n', K0, wn, zeta);
        fprintf('  fit = %.2f %%   RMSE = %.3f mV   corr = %.5f\n', fit_pct, 1e3*rmse_V, corr_R);
        fprintf('  RLC libre: R = %.3f ohm, L = %.4f mH, C = %.1f uF\n', ...
            phys.R, 1e3*phys.L, 1e6*phys.C);
        if idcfg.calcular_R_conocida
            fprintf('  R conocida (%.3f ohm): L = %.4f mH, C = %.1f uF\n', ...
                e.R0, 1e3*phys.L_Rknown, 1e6*phys.C_Rknown);
        end

        % Validacion grafica fuente por fuente.
        ax = nexttile(is); hold(ax,'on'); grid(ax,'on');
        plot(ax, p.t*1e3, p.y, 'LineWidth', 1.1, 'DisplayName',[fuente ' datos']);
        plot(ax, p.t*1e3, yhat, '--', 'LineWidth', 1.2, 'DisplayName','FT 2do orden');
        xline(ax,0,':k','HandleVisibility','off');
        ylabel(ax,'\DeltaV_o [V]');
        legend(ax,'Location','best');
        title(ax, sprintf('%s   fit %.1f%%   \\zeta=%.3f   \\omega_n=%.0f rad/s', ...
            fuente, fit_pct, zeta, wn));
    end
    xlabel(nexttile(3),'tiempo [ms]');
end

%% ===================== TABLAS =====================
Tcoef = struct2table(coef_rows);
Tphys = struct2table(phys_rows);

% Diferencias porcentuales respecto de CEuP, ensayo por ensayo.
Tcoef = agregar_diferencias(Tcoef, idcfg.referencia, ...
    {'a1','a0','b0','Kdc','wn_rad_s','zeta'});
Tphys = agregar_diferencias(Tphys, idcfg.referencia, ...
    {'A2_LC','A1','A0','R_fit_ohm','L_fit_mH','C_fit_uF', ...
     'L_Rconocida_mH','C_Rconocida_uF'});

% Resumen de dispersion entre las tres fuentes: (max-min)/|media|.
Tres = resumen_dispersion(Tcoef, Tphys);

fprintf('\n\n================ COEFICIENTES IDENTIFICADOS ================\n');
disp(Tcoef);
fprintf('\n================ PARAMETROS FISICOS ================\n');
disp(Tphys);
fprintf('\n================ DISPERSION ENTRE FUENTES ================\n');
disp(Tres);

fprintf(['\nNOTA: la identificacion se hace en variables incrementales: ' ...
         'DeltaVo=Vo-Vo0, DeltaIL=IL-IL0 y DeltaD=D-D0. ' ...
         'Los offsets absolutos entre fuentes no participan del ajuste dinamico.\n']);
fprintf(['\nNOTA: a2 vale 1 en las tres fuentes porque tfest expresa el denominador ' ...
         'en forma monica.\n']);
fprintf(['Para comparar el termino fisico de s^2, usar A2_LC de Tphys; ' ...
         'A1 y A0 son los otros coeficientes de la forma fisica no normalizada.\n']);
fprintf(['El RLC libre usa tambien la ganancia/numerador para inferir R. Como Rs es ' ...
         'pequena frente a R, R_fit puede ser sensible al ruido. Para L y C suele ' ...
         'ser mas robusta la columna con R conocida.\n']);

%% Guardar resultados
if idcfg.guardar
    out = 'output';
    if ~isfolder(out), mkdir(out); end

    writetable(Tcoef, fullfile(out,'p6_ft_coeficientes.csv'));
    writetable(Tphys, fullfile(out,'p6_ft_fisicos.csv'));
    writetable(Tres,  fullfile(out,'p6_ft_dispersion.csv'));

    for k = 1:numel(figs)
        nombre_fig = idcfg.ensayos{k};
        saveas(figs(k), fullfile(out, ['p6_ft_' nombre_fig '.png']));
    end

    fprintf('\nResultados guardados en output/p6_ft_*.csv y output/p6_ft_*.png\n');
end

%% ===================== FUNCIONES LOCALES =====================
function p = preparar_datos(d, du, buck, cfg)
%PREPARAR_DATOS Suaviza, recorta alrededor del evento principal, resta el
%nivel inicial y remuestrea uniformemente para identificacion.

    t = d.t(:);
    vo = d.vO(:);
    il = d.iL(:);

    % Quitar NaN/Inf y ordenar por tiempo.
    ok = isfinite(t) & isfinite(vo) & isfinite(il);
    t = t(ok); vo = vo(ok); il = il(ok);
    [t, ord] = sort(t);
    vo = vo(ord); il = il(ord);
    [t, iu] = unique(t, 'stable');
    vo = vo(iu); il = il(iu);

    vo_s = suavizar(t, vo, buck.fsw, cfg.suavizado_periodos);
    il_s = suavizar(t, il, buck.fsw, cfg.suavizado_periodos);

    tmin = -cfg.pre_ms/1e3;
    tmax =  cfg.post_ms/1e3;

    % Esta ventana central es la proteccion principal contra el pico/segundo
    % evento de OHSIM al comienzo o al final de la adquisicion completa.
    sel = t >= tmin & t <= tmax & isfinite(vo_s) & isfinite(il_s);
    t = t(sel); vo_s = vo_s(sel); il_s = il_s(sel);

    if isempty(t) || min(t) >= 0 || max(t) <= 0
        error('La fuente no contiene suficientes datos antes y despues de t=0.');
    end

    % Offset inicial incremental: usar la mitad final de la ventana pre-evento
    % para evitar cualquier irregularidad pegada al borde izquierdo.
    pre1 = -cfg.pre_ms/1e3;
    pre2 = -0.20e-3;
    ipre = t >= pre1 & t <= pre2;
    if nnz(ipre) < 5
        ipre = t < 0;
    end
    y0  = mean(vo_s(ipre), 'omitnan');
    iL0 = mean(il_s(ipre), 'omitnan');
    % Trabajar SIEMPRE en variables incrementales para identificar solo la
    % dinamica y no el offset/punto de operacion absoluto:
    %   DeltaVo = Vo - Vo0, DeltaIL = IL - IL0, DeltaD = D - D0.
    % y0/iL0 se conservan por separado para interpretar el punto de operacion.
    vo_s = vo_s - y0;
    il_s = il_s - iL0;

    % Grilla comun y uniforme. Evita que tfest trabaje con cientos de miles
    % o millones de puntos del osciloscopio.
    tg = (ceil(tmin/cfg.Ts_id)*cfg.Ts_id : cfg.Ts_id : ...
          floor(tmax/cfg.Ts_id)*cfg.Ts_id).';
    yg = interp1(t, vo_s, tg, 'linear', NaN);
    ig = interp1(t, il_s, tg, 'linear', NaN);

    good = isfinite(yg) & isfinite(ig);
    tg = tg(good); yg = yg(good); ig = ig(good);

    ug = zeros(size(tg));
    ug(tg >= 0) = du;

    p.t = tg;
    p.y = yg;
    p.u = ug;
    p.iL = ig;            % Delta iL
    p.y0 = y0;            % Vo absoluto inicial, solo informativo
    p.iL0 = iL0;          % iL absoluto inicial, para L(iL)
end

function [num, den] = normalizar_polinomios(num, den)
%NORMALIZAR_POLINOMIOS Fuerza denominador monico y limpia ceros numericos.
    num = real(num(:).');
    den = real(den(:).');
    if den(1) == 0
        error('Denominador invalido: coeficiente principal nulo.');
    end
    k = den(1);
    den = den/k;
    num = num/k;
end

function [fit_pct, rmse, R] = metricas_ajuste(y, yhat)
%METRICAS_AJUSTE Mismas ideas que compare(): NRMSE-fit, RMSE y correlacion.
    y = y(:); yhat = yhat(:);
    ok = isfinite(y) & isfinite(yhat);
    y = y(ok); yhat = yhat(ok);

    den = norm(y - mean(y));
    if den > eps
        fit_pct = 100*(1 - norm(y-yhat)/den);
    else
        fit_pct = NaN;
    end
    rmse = sqrt(mean((y-yhat).^2));
    cc = corrcoef(y,yhat);
    if numel(cc) >= 4
        R = cc(1,2);
    else
        R = NaN;
    end
end

function phys = extraer_rlc(a1, a0, b0, buck, Rnom, Lref, calc_Rknown)
%EXTRAER_RLC Convierte los coeficientes monicos de Gvd a R,L,C efectivos.
%
% Modelo fisico local no ideal:
%   Gvd = Veq / [LC s^2 + (L/R + Rs C)s + (1 + Rs/R)]
%
% Monico:
%   a1 = 1/(RC) + Rs/L
%   a0 = (1 + Rs/R)/(LC)
%   b0 = Veq/(LC)
%
% Con Rs != 0, las tres ecuaciones permiten inferir R,L,C, aunque R puede
% ser numericamente sensible porque normalmente Rs/R << 1.

    Veq = buck.Vi - buck.Vsw + buck.Vd;
    Rs  = buck.Rs;

    phys.R = NaN; phys.L = NaN; phys.C = NaN;
    phys.L_Rknown = NaN; phys.C_Rknown = NaN;
    phys.residuo = NaN;

    % ----- Solucion libre R,L,C -----
    valido = isfinite(a1) && isfinite(a0) && isfinite(b0) && ...
             a1 > 0 && a0 > 0 && b0 > 0 && Rs > 0;

    if valido
        P = Veq / b0;                   % LC
        q = a0*P - 1;                   % Rs/R
        R = Rs / q;

        if P > 0 && q > 0 && R > 0
            aa = Rs/P;
            bb = -a1;
            cc = 1/R;
            disc = bb^2 - 4*aa*cc;
            if disc >= 0
                Croots = [(-bb + sqrt(disc))/(2*aa), ...
                          (-bb - sqrt(disc))/(2*aa)];
                Croots = Croots(isfinite(Croots) & Croots > 0);
                if ~isempty(Croots)
                    % Hay dos ramas matematicas. Elegir la fisicamente cercana
                    % a la capacidad medida del banco.
                    [~,k] = min(abs(log(Croots/buck.C)));
                    C = Croots(k);
                    L = P/C;
                    if L > 0
                        phys.R = R; phys.L = L; phys.C = C;
                    end
                end
            end
        end
    end

    % Si la solucion exacta no es fisicamente valida por ruido/identificacion,
    % buscar el RLC positivo que mejor reproduzca a1,a0,b0 en escala relativa.
    if ~all(isfinite([phys.R phys.L phys.C]))
        x0 = log([Rnom, max(Lref,1e-6), buck.C]);
        opt = optimset('Display','off','TolX',1e-10,'TolFun',1e-12,'MaxIter',3000);
        x = fminsearch(@(xx) costo_rlc(exp(xx), a1, a0, b0, Veq, Rs), x0, opt);
        p = exp(x);
        phys.R = p(1); phys.L = p(2); phys.C = p(3);
    end

    phys.residuo = sqrt(costo_rlc([phys.R phys.L phys.C], a1, a0, b0, Veq, Rs));

    % ----- Solucion mas robusta con R conocida -----
    if calc_Rknown
        [Lk, Ck] = extraer_lc_Rconocida(a1, a0, Rnom, Rs, buck.C, Lref);
        phys.L_Rknown = Lk;
        phys.C_Rknown = Ck;
    end
end

function J = costo_rlc(p, a1, a0, b0, Veq, Rs)
%COSTO_RLC Error relativo cuadratico entre FT fisica y FT identificada.
    R = p(1); L = p(2); C = p(3);
    if any(~isfinite(p)) || any(p <= 0)
        J = 1e12; return;
    end

    a1p = 1/(R*C) + Rs/L;
    a0p = (1 + Rs/R)/(L*C);
    b0p = Veq/(L*C);

    esc = max(abs([a1 a0 b0]), [1e-12 1e-12 1e-12]);
    rr = ([a1p a0p b0p] - [a1 a0 b0]) ./ esc;
    J = sum(rr.^2);
end

function [L, C] = extraer_lc_Rconocida(a1, a0, R, Rs, Cref, Lref)
%EXTRAER_LC_RCONOCIDA Estima L,C usando R conocida y solo el denominador.
    L = NaN; C = NaN;
    if ~(a1 > 0 && a0 > 0 && R > 0)
        return;
    end

    P = (1 + Rs/R)/a0;          % LC

    if Rs <= eps
        C = 1/(R*a1);
        L = P/C;
        return;
    end

    aa = Rs/P;
    bb = -a1;
    cc = 1/R;
    disc = bb^2 - 4*aa*cc;

    if disc >= 0 && P > 0
        Croots = [(-bb + sqrt(disc))/(2*aa), ...
                  (-bb - sqrt(disc))/(2*aa)];
        Croots = Croots(isfinite(Croots) & Croots > 0);
        if ~isempty(Croots)
            [~,k] = min(abs(log(Croots/Cref)));
            C = Croots(k);
            L = P/C;
        end
    end

    if ~(isfinite(L) && isfinite(C) && L > 0 && C > 0)
        x0 = log([max(Lref,1e-6), Cref]);
        opt = optimset('Display','off','TolX',1e-10,'TolFun',1e-12,'MaxIter',2000);
        x = fminsearch(@(xx) costo_lc(exp(xx), a1, a0, R, Rs), x0, opt);
        p = exp(x);
        L = p(1); C = p(2);
    end
end

function J = costo_lc(p, a1, a0, R, Rs)
    L = p(1); C = p(2);
    if any(~isfinite(p)) || any(p <= 0)
        J = 1e12; return;
    end
    a1p = 1/(R*C) + Rs/L;
    a0p = (1 + Rs/R)/(L*C);
    rr = [(a1p-a1)/max(abs(a1),1e-12), ...
          (a0p-a0)/max(abs(a0),1e-12)];
    J = sum(rr.^2);
end

function T = agregar_diferencias(T, refname, vars)
%AGREGAR_DIFERENCIAS Agrega columnas *_vs_CEuP_pct por ensayo.
    for iv = 1:numel(vars)
        nueva = [vars{iv} '_vs_' refname '_pct'];
        T.(nueva) = NaN(height(T),1);
    end

    ensayos = unique(T.Ensayo, 'stable');
    for ie = 1:numel(ensayos)
        mE = strcmp(T.Ensayo, ensayos{ie});
        mR = mE & strcmp(T.Fuente, refname);
        if nnz(mR) ~= 1
            continue;
        end
        for iv = 1:numel(vars)
            vref = T.(vars{iv})(mR);
            if isfinite(vref) && abs(vref) > eps
                T.([vars{iv} '_vs_' refname '_pct'])(mE) = ...
                    100*(T.(vars{iv})(mE)-vref)/vref;
            end
        end
    end
end

function Tres = resumen_dispersion(Tcoef, Tphys)
%RESUMEN_DISPERSION Spread relativo entre Modelo/CEuP/OHSIM por ensayo.
    ensayos = unique(Tcoef.Ensayo, 'stable');
    rows = cell(numel(ensayos), 13);
    for k = 1:numel(ensayos)
        e = ensayos{k};
        mc = strcmp(Tcoef.Ensayo,e);
        mp = strcmp(Tphys.Ensayo,e);
        rows{k,1}  = e;
        rows{k,2}  = spread_pct(Tcoef.a1(mc));
        rows{k,3}  = spread_pct(Tcoef.a0(mc));
        rows{k,4}  = spread_pct(Tcoef.b0(mc));
        rows{k,5}  = spread_pct(Tcoef.Kdc(mc));
        % Coeficientes fisicos NO normalizados del denominador:
        % A2*s^2 + A1*s + A0. A2=LC es el termino de s^2 que se pierde
        % al escribir la FT en forma monica.
        rows{k,6}  = spread_pct(Tphys.A2_LC(mp));
        rows{k,7}  = spread_pct(Tphys.A1(mp));
        rows{k,8}  = spread_pct(Tphys.A0(mp));
        rows{k,9}  = spread_pct(Tphys.R_fit_ohm(mp));
        rows{k,10} = spread_pct(Tphys.L_fit_mH(mp));
        rows{k,11} = spread_pct(Tphys.C_fit_uF(mp));
        rows{k,12} = spread_pct(Tphys.L_Rconocida_mH(mp));
        rows{k,13} = spread_pct(Tphys.C_Rconocida_uF(mp));
    end
    Tres = cell2table(rows, 'VariableNames', ...
        {'Ensayo','spread_a1_pct','spread_a0_pct','spread_b0_pct','spread_Kdc_pct', ...
         'spread_A2_LC_pct','spread_A1_fis_pct','spread_A0_fis_pct', ...
         'spread_R_pct','spread_L_pct','spread_C_pct', ...
         'spread_L_Rconocida_pct','spread_C_Rconocida_pct'});
end

function s = spread_pct(x)
%SPREAD_PCT (max-min)/|mean| * 100.
    x = x(isfinite(x));
    if isempty(x) || abs(mean(x)) <= eps
        s = NaN;
    else
        s = 100*(max(x)-min(x))/abs(mean(x));
    end
end
