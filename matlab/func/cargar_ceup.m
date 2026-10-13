function d = cargar_ceup(ensayo, med)
%CARGAR_CEUP  Lee un ensayo del CEuP (CSV combinado del Rigol MHO934) y lo
% deja con el evento en t=0.  CH1=vSw, CH2=Vo, CH3=pinza, CH4=cambio de carga.
%
%   d.t, d.vSw, d.vO, d.iL           magnitudes fisicas
%   d.iL_crudo                       corriente antes de la compensacion de cero

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

archivo = fullfile(med.raiz, med.carpeta_ceup, [ensayo.nombre '.csv']);
[t, canales] = leer_csv_rigol(archivo);

d.vSw = canales(:,1);
d.vO  = canales(:,2);
p = med.pinza;
d.iL_crudo = p.signo * (canales(:,3) - p.cero) / p.ganancia;
d.iL       = d.iL_crudo - p.compensacion_A;

if ensayo.D0 ~= ensayo.D1
    t0 = alinear_evento(t, d.vSw, med.alineacion.duty);
elseif ensayo.R0 ~= ensayo.R1
    t0 = alinear_evento(t, canales(:,4), med.alineacion.carga);
else
    t0 = 0;
end
d.t = t - t0;
end
