#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

"""Serial runner and audit logger for the OHSIM LaunchPad firmware."""

from __future__ import annotations

import argparse
import csv
import json
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Callable, Iterable

try:
    import serial
    from serial.tools import list_ports
except ImportError:  # Keep --help and parser tests usable without pyserial.
    serial = None
    list_ports = None


TEST_IDS = (11, 12, 2, 31, 32, 41, 42, 5)
RESULT_FIELDS = (
    "RESULT", "TEST", "STEPS", "SAMPLES", "IL_MIN_RAW", "IL_MAX_RAW",
    "IL_MEAN_RAW", "VO_MIN_RAW", "VO_MAX_RAW", "VO_MEAN_RAW",
    "IL_ZERO_RAW", "VO_ZERO_RAW", "ADC_OVF", "ISR_MAX_TICKS", "FLAGS",
)


class ProtocolError(RuntimeError):
    """The controller timed out or returned an invalid protocol response."""


def parse_fields(line: str) -> dict[str, str]:
    fields: dict[str, str] = {}
    for token in line.strip().split():
        if "=" in token:
            key, value = token.split("=", 1)
            fields[key] = value
    return fields


@dataclass
class ReceivedLine:
    timestamp_utc: str
    direction: str
    line: str


class AuditLog:
    def __init__(self, output_dir: Path) -> None:
        output_dir.mkdir(parents=True, exist_ok=True)
        self.output_dir = output_dir
        self.transcript_path = output_dir / "transcript.jsonl"
        self.summary_path = output_dir / "results.csv"

    def record(self, direction: str, line: str) -> None:
        item = ReceivedLine(
            timestamp_utc=datetime.now(timezone.utc).isoformat(),
            direction=direction,
            line=line,
        )
        with self.transcript_path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(asdict(item), ensure_ascii=False) + "\n")

    def append_result(self, fields: dict[str, str]) -> None:
        exists = self.summary_path.exists()
        with self.summary_path.open("a", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=RESULT_FIELDS)
            if not exists:
                writer.writeheader()
            writer.writerow({name: fields.get(name, "") for name in RESULT_FIELDS})


class OhsimController:
    def __init__(self, port: str, baud: int, audit: AuditLog | None) -> None:
        if serial is None:
            raise RuntimeError(
                "pyserial no esta instalado. Ejecute: "
                "py -m pip install -r host\\requirements.txt"
            )
        self.audit = audit
        self.request_id = 1
        self.link = serial.Serial(port=port, baudrate=baud, timeout=0.1)
        self.link.reset_input_buffer()

    def close(self) -> None:
        self.link.close()

    def _record(self, direction: str, line: str) -> None:
        print(f"{direction} {line}")
        if self.audit is not None:
            self.audit.record(direction, line)

    def _read_line(self, deadline: float) -> str:
        while time.monotonic() < deadline:
            raw = self.link.readline()
            if not raw:
                continue
            line = raw.decode("ascii", errors="replace").strip()
            if line:
                self._record("RX", line)
                return line
        raise ProtocolError("Timeout esperando una linea del firmware")

    def command(self, command: str, timeout: float = 2.0) -> str:
        request_id = self.request_id
        self.request_id += 1
        prefix = f"@{request_id}"
        wire_line = f"{prefix} {command}"
        self._record("TX", wire_line)
        self.link.write((wire_line + "\n").encode("ascii"))
        self.link.flush()

        deadline = time.monotonic() + timeout
        while True:
            line = self._read_line(deadline)
            if line.startswith(prefix + " "):
                response = line[len(prefix) + 1 :]
                if response.startswith("ERR"):
                    raise ProtocolError(f"{command}: {response}")
                return response

    def wait_event(
        self,
        predicate: Callable[[str, dict[str, str]], bool],
        timeout: float,
    ) -> tuple[str, dict[str, str]]:
        deadline = time.monotonic() + timeout
        while True:
            line = self._read_line(deadline)
            if not line.startswith("!EVT "):
                continue
            fields = parse_fields(line)
            if predicate(line, fields):
                return line, fields

    def run_test(self, test_id: int, arm_prompt: bool) -> dict[str, str]:
        self.command("SAFE")
        self.command(f"PREPARE {test_id}")
        self.wait_event(
            lambda _line, fields: fields.get("STATE") == "ARMED"
            and fields.get("TEST") == str(test_id),
            timeout=3.0,
        )

        if arm_prompt:
            input(
                f"Ensayo {test_id} ARMED. Arme ILA/osciloscopio y presione Enter "
                "para aplicar el escalon..."
            )

        self.command("RUN")
        _line, done = self.wait_event(
            lambda _line, fields: fields.get("STATE") == "DONE"
            and fields.get("TEST") == str(test_id),
            timeout=3.0,
        )
        response = self.command("RESULT")
        result = parse_fields(response)
        if result.get("TEST") != str(test_id):
            raise ProtocolError(
                f"RESULT devolvio TEST={result.get('TEST')} para el ensayo {test_id}"
            )
        if "RESULT" not in result or "SAMPLES" not in result:
            raise ProtocolError(f"RESULT incompleto: {response}")
        if done.get("RESULT") != result.get("RESULT"):
            raise ProtocolError(
                f"Veredicto inconsistente: evento={done.get('RESULT')} "
                f"respuesta={result.get('RESULT')}"
            )
        return result


def make_output_dir(argument: str | None) -> Path:
    if argument:
        return Path(argument)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return Path("captures") / stamp


def show_ports() -> int:
    if list_ports is None:
        raise RuntimeError("pyserial no esta instalado")
    ports = list(list_ports.comports())
    if not ports:
        print("No se encontraron puertos serie.")
        return 1
    for port in ports:
        print(f"{port.device}\t{port.description}\t{port.hwid}")
    return 0


def run_serial_command(args: argparse.Namespace) -> int:
    output_dir = (
        make_output_dir(args.output)
        if args.command in {"run", "run-all"}
        else None
    )
    audit = AuditLog(output_dir) if output_dir is not None else None
    controller = OhsimController(args.port, args.baud, audit)
    try:
        if args.command == "ping":
            controller.command("PING")
        elif args.command == "status":
            controller.command("STATUS")
        elif args.command == "adc-read":
            controller.command("ADC READ")
        elif args.command == "cal-zero":
            controller.command("CAL ZERO", timeout=2.0)
        else:
            test_ids: Iterable[int]
            test_ids = (args.test_id,) if args.command == "run" else TEST_IDS
            for test_id in test_ids:
                try:
                    result = controller.run_test(test_id, args.arm_prompt)
                    assert audit is not None
                    audit.append_result(result)
                finally:
                    controller.command("SAFE")
            print(f"Resultados: {audit.summary_path}")
            print(f"Transcripcion: {audit.transcript_path}")
    finally:
        controller.close()
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", help="Puerto serie del XDS100 (COMn en Windows)")
    parser.add_argument("--baud", type=int, default=115200)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("ports", help="Listar puertos serie")
    subparsers.add_parser("ping")
    subparsers.add_parser("status")
    subparsers.add_parser("adc-read")
    subparsers.add_parser("cal-zero")
    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("test_id", type=int, choices=TEST_IDS)
    run_parser.add_argument("--arm-prompt", action="store_true")
    run_parser.add_argument("--output", help="Directorio para los resultados")
    all_parser = subparsers.add_parser("run-all")
    all_parser.add_argument("--arm-prompt", action="store_true")
    all_parser.add_argument("--output", help="Directorio para los resultados")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "ports":
            return show_ports()
        if not args.port:
            raise RuntimeError("Falta --port (use 'ports' para enumerarlos)")
        return run_serial_command(args)
    except (ProtocolError, RuntimeError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
