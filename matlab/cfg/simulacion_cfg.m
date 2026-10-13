function sim = simulacion_cfg()
%SIMULACION_CFG  Solver, ventanas de tiempo, suavizado y tabla de ensayos.

% SPDX-License-Identifier: MIT
% Copyright (c) 2026 Tomás Vovard
% pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

sim.modelo = 'buck_no_ideal';      % nombre del .slx
sim.pasos_solver_por_periodo = 100;% MaxStep = Tsw / este valor
sim.periodos_regimen = 60;         % periodos a simular en un barrido estatico
sim.pre_ms  = 10;                  % tiempo antes del evento (deja asentar la condicion inicial)
sim.suavizado_periodos = 1;        % media movil (en periodos PWM) para la envolvente

% Barrido estatico de p3 (modelo sin escalones).
sim.cargas = [50 25 16.6];
sim.duties = [0.30 0.45 0.70 0.80];

% Ensayos: escalon de duty y/o de carga. Una fila por ensayo.
%   nombre | id firmware | D0 | D1 | R0 | R1 | ventana posterior [ms]
datos = {
    'E1a', 11, 0.45, 0.46, 16.6, 16.6,  22
    'E1b', 12, 0.46, 0.45, 16.6, 16.6,  22
    'E2',   2, 0.30, 0.30, 25.0, 16.6,  22
    'E3a', 31, 0.80, 0.81, 25.0, 25.0,  22
    'E3b', 32, 0.808383, 0.80, 25.0, 25.0,  22
    'E4a', 41, 0.70, 0.70, 50.0, 25.0,  22
    'E4b', 42, 0.70, 0.70, 25.0, 16.6,  22
    'E5',   5, 0.70, 0.70, 16.6, 25.0, 180
    };
for k = 1:size(datos,1)
    sim.ensayos(k).nombre  = datos{k,1};
    sim.ensayos(k).id      = datos{k,2};
    sim.ensayos(k).D0      = datos{k,3};
    sim.ensayos(k).D1      = datos{k,4};
    sim.ensayos(k).R0      = datos{k,5};
    sim.ensayos(k).R1      = datos{k,6};
    sim.ensayos(k).post_ms = datos{k,7};
end

% Ensayos que se comparan contra CEuP y OHSIM.
sim.comparar = {'E1a','E2','E3a','E3b','E4a','E4b'};
end
