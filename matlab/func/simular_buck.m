function r = simular_buck(buck, simcfg, R0, D0, R1, D1, t_pre, t_post)
%SIMULAR_BUCK  Corre el Simulink 'buck_no_ideal' con un escalon de carga/duty
% en t=0 (para un barrido estatico usar R1=R0, D1=D0). 
% Arranca en el punto de trabajo (R0,D0). 
% Devuelve las variables de estado crudas (conmutadas):
%   r.t, r.vSw, r.pwm, r.vO, r.iL, r.R

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

% Parámetros
switch buck.L.tipo
    case 'const', L_inv = 1/buck.L.const; m_inv = 0;            L_sat = inf;
    case 'lin',   L_inv = buck.L.b_inv;   m_inv = buck.L.a_inv; L_sat = inf;
    case 'knee',  L_inv = buck.L.b_inv;   m_inv = buck.L.a_inv; L_sat = buck.L.knee_max;
end

Tsim = t_pre + t_post;

% Punto de operación
x0   = punto_periodico(buck, R0, D0);

% Contrucción de vectores de escalón
dt_ev = buck.Tsw/1000;
t_cmd = [0 t_pre t_pre+dt_ev Tsim];
Duty  = setinterpmethod(timeseries([D0 D0 D1 D1], t_cmd), 'zoh');
Rload = setinterpmethod(timeseries([R0 R0 R1 R1], t_cmd), 'zoh');

% Carga parámetros en simulación
in = Simulink.SimulationInput(simcfg.modelo);
in = in.setVariable('vin', buck.Vi);
in = in.setVariable('vsw', buck.Vsw);
in = in.setVariable('vd',  buck.Vd);
in = in.setVariable('Rs',  buck.Rs);
in = in.setVariable('C',   buck.C);
in = in.setVariable('fsw', buck.fsw);
in = in.setVariable('L_inv', L_inv);
in = in.setVariable('m_inv', m_inv);
in = in.setVariable('L_sat', L_sat);
in = in.setVariable('Duty_cmd',  Duty);
in = in.setVariable('Rload_cmd', Rload);
in = in.setModelParameter('StopTime', num2str(Tsim), 'MaxStep', num2str(buck.Tsw/simcfg.pasos_solver_por_periodo));
in = in.setBlockParameter([simcfg.modelo '/Integrator'],  'InitialCondition', num2str(x0(1)));
in = in.setBlockParameter([simcfg.modelo '/Integrator1'], 'InitialCondition', num2str(x0(2)*buck.C));

out = sim(in);
y = out.simout;

% El solver deja instantes repetidos en el escalon (interpolacion ZOH); se
% conserva el ultimo valor de cada instante.
[t, iu] = unique(out.tout(:), 'last');
r.t = t - t_pre;
r.vSw = y(iu,1); r.pwm = y(iu,2); r.vO = y(iu,3); r.iL = y(iu,4); r.R = y(iu,5);
end
