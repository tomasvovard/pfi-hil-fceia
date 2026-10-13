// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Tomás Vovard
// pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// ad5328_driver.v
//
// Driver SPI para Analog Devices AD5328 (DAC octal, 12 bits, doble buffer).
// Actualiza un rango consecutivo de canales de UN AD5328 como conjunto:
//   1) escribe N_CHANNELS desde FIRST_CHANNEL via SPI (16 bits c/u)
//   2) pulsa LDAC para transferir los input registers a los DAC registers
//      de forma SIMULTANEA ("asynchronous LDAC",
//      datasheet AD5308/AD5318/AD5328 Rev.F, seccion
//      "Load DAC Input (LDAC) Function" / Figura 2, traza LDAC1).
//
// No se escribe ningun "control word" (Bit15=1 del formato de trama).
// Se deja el dispositivo en su configuracion de Power-On Reset, que
// coincide con lo que necesitamos (seccion "Power-On Reset" del
// datasheet):
//   - LDAC mode bits = "LDAC high" (default) -> el pin LDAC fisico es
//     quien controla cuando los input registers pasan a los DAC
//     registers (esto es justo el modo "asincrono" que usamos).
//   - Referencia sin buffer, rango de salida 0V a VREF (GAIN=+1).
//   - Todos los registros (input y DAC) arrancan en 0.
// Si en el futuro se necesita referencia buffered o gain=2, hace falta
// agregar el envio de un "control word" adicional (no implementado a
// proposito).
//
// -----------------------------------------------------------------------
// Formato de la palabra serie (16 bits, se transmite MSB primero, es
// decir Bit15 va primero en el tiempo):
//
//   Bit15    D/C   -> 0 = DAC write (no es un control word)
//   Bit14:12 A2:A0 -> direccion de canal, Tabla 6 del datasheet:
//                       000 A   001 B   010 C   011 D
//                       100 E   101 F   110 G   111 H
//   Bit11:0  D11:D0-> dato de 12 bits, codificacion binaria recta.
//                     AD5328 usa los 12 bits completos (a diferencia de
//                     AD5308/AD5318 que ignoran algunos LSB).
//
// -----------------------------------------------------------------------
// Timing (Tabla 3 "Timing Characteristics" del datasheet, version A/B,
// rango -40..+125 C, que es el peor caso especificado):
//
//   t1  >= 33   ns  SCLK periodo minimo          (=> f_SCLK <= 30.3 MHz)
//   t2  >= 13   ns  SCLK tiempo en alto minimo
//   t3  >= 13   ns  SCLK tiempo en bajo minimo
//   t4  >= 15   ns  SYNC bajo -> primer flanco de bajada de SCLK (setup)
//   t5  >= 5    ns  DIN debe estar estable antes del flanco de bajada
//   t6  >= 4.5  ns  DIN debe mantenerse estable despues del flanco de bajada
//   t7  >= 0    ns  ultimo flanco de bajada de SCLK -> SYNC vuelve a alto
//   t8  >= 50   ns  SYNC en alto, minimo entre dos transferencias
//   t9  >= 20   ns  ancho minimo del pulso de LDAC
//   t10/t11         Solo aplican al modo LDAC "sincrono" (LDAC referido a
//                   flancos de SCLK). No aplican a este diseno porque
//                   LDAC se pulsa varios ciclos de sys_clk despues de que
//                   SYNC del ultimo canal ya volvio a alto (modo async,
//                   traza LDAC1 de la Figura 2 del datasheet).
//
// -----------------------------------------------------------------------
// Estrategia de clocking en la FPGA (un unico dominio de reloj, sys_clk):
//
//   SCLK se genera dividiendo sys_clk por 2 mediante un flip-flop que
//   togglea en cada flanco de subida de sys_clk. Esto es logica
//   SECUENCIAL (no un reloj derivado combinacionalmente) y dac_sclk sale
//   directamente de un registro. Con sys_clk = 30 MHz esto da
//   SCLK = 15 MHz (periodo 66.67 ns): mas del doble del minimo t1
//   (33 ns), con t2/t3 (33.3 ns cada semiperiodo) tambien> 2x el minimo
//   (13 ns).
//
//   DIN se actualiza (nuevo bit) sincronizado con el flanco de SUBIDA de
//   SCLK y permanece estable durante toda la fase alta; el AD5328 lo
//   captura en el flanco de BAJADA siguiente. Esto deja ~33 ns de margen
//   de setup (t5 exige solo 5 ns) y ~33 ns de margen de hold antes del
//   proximo cambio de DIN (t6 exige solo 4.5 ns). Margen > 6x en ambos
//   casos: se prioriza la robustez sobre la velocidad.
//
//   SYNC se mantiene bajo 1 ciclo de sys_clk (33.3 ns) antes del primer
//   flanco de SCLK (>> t4 = 15 ns), y en alto >=3 ciclos (100 ns) entre
//   canales (>> t8 = 50 ns). El pulso de LDAC dura >=2 ciclos (66.7 ns,
//   >> t9 = 20 ns).
//
// Criterios de RTL sintetizable respetados: sin '#' delays, sin relojes
// generados por logica combinacional, sin latches, sin multiples
// drivers, un unico always secuencial por bloque, reset sincrono.
//////////////////////////////////////////////////////////////////////////////

module ad5328_driver #(
    parameter integer FIRST_CHANNEL    = 0,  // primer canal enviado (direccion A=0..H=7). DEFAULT=0 (A).
    parameter integer N_CHANNELS       = 8,  // canales consecutivos enviados antes de LDAC. Debe cumplirse 1<=N_CHANNELS y FIRST_CHANNEL+N_CHANNELS<=8.
    parameter integer SYNC_HIGH_CYCLES = 3,  // ciclos de sys_clk con SYNC en alto entre canales (>= t8/T_sysclk = 50/33.33 ~ 1.5 -> margen x2)
    parameter integer LDAC_LOW_CYCLES  = 2   // ciclos de sys_clk con LDAC en bajo            (>= t9/T_sysclk = 20/33.33 ~ 0.6 -> margen x3)
) (
    input  wire        clk,      // sys_clk, 30 MHz
    input  wire        resetn,   // reset sincrono, activo en bajo

    input  wire [11:0] ch0_data, // canal A
    input  wire [11:0] ch1_data, // canal B
    input  wire [11:0] ch2_data, // canal C
    input  wire [11:0] ch3_data, // canal D
    input  wire [11:0] ch4_data, // canal E
    input  wire [11:0] ch5_data, // canal F
    input  wire [11:0] ch6_data, // canal G
    input  wire [11:0] ch7_data, // canal H

    input  wire        start,    // pulso de 1 ciclo: inicia un frame
    output reg          busy,     // en alto mientras se procesa la actualizacion completa
    output reg          done,     // pulso de 1 ciclo al completar (incluye el pulso de LDAC)

    output reg          dac_din,
    output reg          dac_sclk,
    output reg          dac_sync,  // activo en bajo
    output reg          dac_ldac   // activo en bajo
);

    // -------------------------------------------------------------------
    // Estados de la FSM
    // -------------------------------------------------------------------
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_LOAD       = 4'd1,  // captura atomica de los 8 canales de entrada
        S_SYNC_SETUP = 4'd2,  // SYNC baja, carga la palabra del canal actual
        S_SHIFT_HIGH = 4'd3,  // SCLK en alto (DIN estable, esperando flanco de bajada)
        S_SHIFT_LOW  = 4'd4,  // SCLK en bajo (flanco de bajada: el DAC captura DIN)
        S_SYNC_HIGH  = 4'd5,  // SYNC vuelve a alto, se sostiene >= t8
        S_LDAC_LOW   = 4'd6,  // pulso LDAC bajo, >= t9
        S_LDAC_HIGH  = 4'd7,  // LDAC vuelve a alto
        S_DONE       = 4'd8;

    reg [3:0] state;

    // Registros locales de los 8 canales (double buffer software: evita
    // que ch*_data cambie a mitad de una actualizacion ya en curso)
    reg [11:0] ch_reg [0:7];

    // indice de canal en transmision (0..7 <=> direcciones A..H)
    reg [2:0]  chan_idx;

    // shift register de 16 bits: contiene {D/C, A2:A0, D11:D0}
    reg [15:0] shift_reg;

    // contador de bits ya muestreados por el DAC (0..15)
    reg [3:0]  bit_cnt;

    // contador auxiliar para los tiempos de espera (SYNC alto / LDAC bajo)
    reg [3:0]  wait_cnt;

    integer i;

    // -------------------------------------------------------------------
    // FSM principal (un unico dominio de reloj)
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            state     <= S_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            dac_din   <= 1'b0;
            dac_sclk  <= 1'b0;   // SCLK en reposo = bajo
            dac_sync  <= 1'b1;   // SYNC inactivo  = alto
            dac_ldac  <= 1'b1;   // LDAC inactivo  = alto
            chan_idx  <= 3'd0;
            bit_cnt   <= 4'd0;
            wait_cnt  <= 4'd0;
            shift_reg <= 16'd0;
            for (i = 0; i < 8; i = i + 1) ch_reg[i] <= 12'd0;
        end else begin
            done <= 1'b0; // pulso de 1 ciclo por defecto, se levanta solo en S_DONE

            case (state)
                // -----------------------------------------------------
                S_IDLE: begin
                    dac_sync <= 1'b1;
                    dac_ldac <= 1'b1;
                    dac_sclk <= 1'b0;
                    busy     <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_LOAD;
                    end
                end

                // Captura atomica de los 8 canales al inicio de la
                // actualizacion (un solo ciclo de latencia extra).
                S_LOAD: begin
                    ch_reg[0] <= ch0_data;
                    ch_reg[1] <= ch1_data;
                    ch_reg[2] <= ch2_data;
                    ch_reg[3] <= ch3_data;
                    ch_reg[4] <= ch4_data;
                    ch_reg[5] <= ch5_data;
                    ch_reg[6] <= ch6_data;
                    ch_reg[7] <= ch7_data;
                    chan_idx  <= FIRST_CHANNEL[2:0];
                    state     <= S_SYNC_SETUP;
                end

                // SYNC baja y se carga la palabra de 16 bits del canal
                // actual en el shift register. El primer flanco de SCLK
                // recien ocurre en el proximo estado (S_SHIFT_HIGH), 1
                // ciclo (33.3 ns) despues: cumple t4 (>=15 ns) con
                // amplio margen.
                S_SYNC_SETUP: begin
                    dac_sync  <= 1'b0;
                    shift_reg <= {1'b0, chan_idx, ch_reg[chan_idx]}; // D/C=0, addr, data[11:0]
                    bit_cnt   <= 4'd0;
                    state     <= S_SHIFT_HIGH;
                end

                // SCLK sube y, en el MISMO flanco, se presenta en DIN el
                // bit actual (MSB vigente de shift_reg). Es importante
                // que DIN cambie aca (junto con el flanco de SUBIDA) y
                // NUNCA en S_SHIFT_LOW: si cambiara junto con el flanco
                // de BAJADA (el que el AD5328 usa para muestrear) se
                // arriesgaria el cumplimiento de t5/t6 por quedar los
                // dos flancos coincidentes en el mismo borde de reloj.
                // Con este esquema, DIN queda estable durante TODA la
                // fase alta (~33.3 ns, >> t5 = 5 ns) y sigue estable
                // hasta el proximo cambio, un ciclo despues del proximo
                // flanco de bajada (~33.3 ns, >> t6 = 4.5 ns).
                S_SHIFT_HIGH: begin
                    dac_sclk <= 1'b1;
                    dac_din  <= shift_reg[15];
                    state    <= S_SHIFT_LOW;
                end

                // SCLK baja: este es el flanco que el AD5328 usa para
                // capturar DIN (DIN no cambia en este estado). Si ya se
                // completaron los 16 bits se pasa a SYNC_HIGH; si no, se
                // desplaza el shift register para dejar preparado el
                // proximo bit, que se presentara recien en el proximo
                // S_SHIFT_HIGH (flanco de subida siguiente).
                S_SHIFT_LOW: begin
                    dac_sclk <= 1'b0;
                    if (bit_cnt == 4'd15) begin
                        // ya se transmitieron y muestrearon los 16 bits
                        state    <= S_SYNC_HIGH;
                        wait_cnt <= 4'd0;
                    end else begin
                        shift_reg <= {shift_reg[14:0], 1'b0};
                        bit_cnt   <= bit_cnt + 1'b1;
                        state     <= S_SHIFT_HIGH;
                    end
                end

                // SYNC sube (fin de la transferencia del canal actual,
                // cumple t7 con margen). Se sostiene en alto
                // SYNC_HIGH_CYCLES ciclos (>= t8) antes de iniciar el
                // siguiente canal.
                S_SYNC_HIGH: begin
                    dac_sync <= 1'b1;
                    dac_sclk <= 1'b0;
                    if (wait_cnt == SYNC_HIGH_CYCLES - 1) begin
                        if (chan_idx == (FIRST_CHANNEL + N_CHANNELS - 1)) begin
                            state    <= S_LDAC_LOW;
                            wait_cnt <= 4'd0;
                        end else begin
                            chan_idx <= chan_idx + 1'b1;
                            state    <= S_SYNC_SETUP;
                        end
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end

                // El rango seleccionado ya fue escrito. Se pulsa LDAC
                // para actualizar simultaneamente las salidas; los
                // canales no escritos conservan su input register.
                S_LDAC_LOW: begin
                    dac_ldac <= 1'b0;
                    if (wait_cnt == LDAC_LOW_CYCLES - 1) begin
                        state    <= S_LDAC_HIGH;
                        wait_cnt <= 4'd0;
                    end else begin
                        wait_cnt <= wait_cnt + 1'b1;
                    end
                end

                S_LDAC_HIGH: begin
                    dac_ldac <= 1'b1;
                    state    <= S_DONE;
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
