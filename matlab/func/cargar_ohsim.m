function d = cargar_ohsim(ensayo, med)
%CARGAR_OHSIM  Lee un ensayo de OHSIM (CSV del osciloscopio) y lo deja con el
% evento en t=0.  CH1=trigger, CH2=Vo por DAC, CH3=iL por DAC.
%
%   d.t, d.vO, d.iL

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

archivo = fullfile(med.raiz, med.carpeta_ohsim, [ensayo.nombre '.csv']);
[t, canales] = leer_csv_rigol(archivo);

o = med.ohsim;
offset = o.compensar_offset_software * o.offset_Vo_dac;   % 0 si la compensacion vive en el RTL
d.vO = (canales(:,2) - offset) * o.ganancia_Vo;            % offset en crudo, ANTES de escalar
d.iL = canales(:,3) * o.ganancia_iL;

t0 = alinear_evento(t, canales(:,1), med.alineacion.ohsim);
d.t = t - t0;
end
