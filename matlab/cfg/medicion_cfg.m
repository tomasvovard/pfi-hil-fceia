function med = medicion_cfg()
%MEDICION_CFG  Instrumentacion: pinza de corriente, escalas del DAC de OHSIM,
% rutas a los CSV y alineacion temporal. Editar aca al recalibrar.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

% --- Rutas a los datos ---
% Relativas a la carpeta matlab/ del repositorio (Current Folder de MATLAB).
med.raiz = fullfile('..', 'data', 'E1a');
med.carpeta_ceup  = 'ceup';    % <ensayo>.csv del CEuP (CH1..CH4)
med.carpeta_ohsim = 'ohsim';   % <ensayo>.csv de OHSIM (CH1..CH3)
% Puntos (iL, L) de todos los ensayos del CEuP, para p1_inductancia.
med.puntos_L = fullfile('..', 'data', 'inductancia', 'puntos_L_ceup.csv');

% --- Pinza de corriente (CEuP, canal CH3) ---
% Conversion:  iL = (CH3 - cero) / ganancia
% Nominal: sensibilidad 0.100 V/A, 5 vueltas, sonda x10  ->  ganancia = 5.0 V/A.
% Si se calibra con dos corrientes conocidas (ver func/calibrar_pinza), poner
% aca los valores medidos.
med.pinza.ganancia = 0.100 * 5 * 10;   % [V/A]
med.pinza.cero     = 0;                 % [V]  lectura de CH3 a corriente nula
med.pinza.signo    = +1;                % -1 si la captura quedo invertida
% Compensacion adicional del cero (hipotesis, mientras no se mida el cero real).
% Se resta a la corriente del CEuP; no se aplica a OHSIM.
med.pinza.compensacion_A = 0.172;

% --- Escalas del DAC de OHSIM (osciloscopio) ---
%   Vo_real = (CH2 - offset_Vo_dac) * ganancia_Vo ;  iL_real = CH3 * ganancia_iL
med.ohsim.ganancia_Vo = 40/3;
med.ohsim.ganancia_iL = 2.5/3;
% offset_Vo_dac: offset de cero del DAC, medido en CRUDO (el mismo punto y
% escala que CH2, ANTES de multiplicar por ganancia_Vo) -- es lo que da un
% tester tocando directamente la salida del DAC. NO poner aca el offset ya
% referido a Vo fisico: eso se obtiene multiplicando por ganancia_Vo, y las
% funciones que lo usan (cargar_ohsim, r3_parametros_verilog) ya lo hacen.
%
% Se estimo comparando OHSIM contra el Modelo (misma fisica nominal que el
% RTL, sin el ruido de medir el CEuP) con p4_comparar_fuentes: la media de
% las 12 diferencias de nivel inicial y final de los seis ensayos es de unos
% 280 mV FISICOS, bastante constante entre ensayos. El valor medido con
% tester en la puesta a punto (43 mV) no reproduce esa diferencia.
med.ohsim.offset_Vo_dac = 0.0210257578133257; % [V] crudo, estimado con p4 (12 niveles ini/fin)
% Fondo de escala fisico del canal Vo del DAC (r3_parametros_verilog lo usa
% para convertir el offset, ya en Vo fisico, a codigo de 12 bits para dac_scaler.v).
med.ohsim.Vmax_Vo = 40;   % [V]

% Compensar offset_Vo_dac tambien en el post-procesamiento (cargar_ohsim.m).
% En false porque la compensacion va a vivir en el RTL (dac_scaler.v) -- si
% se deja en true ademas de eso, se resta el offset DOS veces.
med.ohsim.compensar_offset_software = false;

% --- Alineacion temporal ---
% CEuP: en escalon de duty se busca el flanco de vSw (CH1) mas cercano al
%       trigger; en escalon de carga, el cambio estable de CH4.
% OHSIM: flanco del pulso de trigger (CH1) mas cercano a t=0.
med.alineacion.duty  = 'flanco';
med.alineacion.carga = 'carga';
med.alineacion.ohsim = 'flanco';
end
