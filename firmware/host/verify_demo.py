#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

"""Audit a complete OHSIM run and generate a concise evidence report."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class ExpectedTest:
    test_id: int
    key: str
    samples: int


EXPECTED = (
    ExpectedTest(11, "E1a", 3340),
    ExpectedTest(12, "E1b", 3340),
    ExpectedTest(2, "E2", 3340),
    ExpectedTest(31, "E3a", 6020),
    ExpectedTest(32, "E3b", 6020),
    ExpectedTest(41, "E4a", 6020),
    ExpectedTest(42, "E4b", 3340),
    ExpectedTest(5, "E5", 6020),
)
CRITICAL_FLAGS = {"ADC_SATURATION", "ADC_OVERFLOW", "NO_SAMPLES"}
SAMPLE_TOLERANCE_FRACTION = 0.005
SAMPLE_TOLERANCE_MINIMUM = 20


def sample_tolerance(expected: int) -> int:
    """Allow bounded main-loop latency without accepting gross timing errors."""
    return max(SAMPLE_TOLERANCE_MINIMUM, round(expected * SAMPLE_TOLERANCE_FRACTION))


def valid_combined_rigol(path: Path) -> bool:
    """Recognize the combined MHO900 CSV without loading a large capture."""
    if not path.is_file() or path.stat().st_size <= 50:
        return False
    try:
        with path.open("rb") as stream:
            header = stream.readline(512).decode("ascii", errors="ignore")
    except OSError:
        return False
    columns = {token.strip() for token in header.split(",")}
    return {"CH1V", "CH2V", "CH3V"}.issubset(columns)


def read_results(path: Path) -> tuple[dict[int, dict[str, str]], list[str]]:
    errors: list[str] = []
    rows: dict[int, dict[str, str]] = {}
    if not path.is_file():
        return rows, [f"Falta {path.name}"]
    with path.open(newline="", encoding="utf-8-sig") as stream:
        for row_number, row in enumerate(csv.DictReader(stream), start=2):
            try:
                test_id = int(row.get("TEST", ""))
            except ValueError:
                errors.append(f"results.csv fila {row_number}: TEST invalido")
                continue
            if test_id in rows:
                errors.append(f"TEST {test_id} aparece mas de una vez en results.csv")
            rows[test_id] = row
    return rows, errors


def audit_capture(
    capture_dir: Path,
    require_waveforms: bool = True,
    require_ila_all: bool = False,
) -> tuple[list[dict[str, str]], list[str], list[str]]:
    results, errors = read_results(capture_dir / "results.csv")
    warnings: list[str] = []
    report_rows: list[dict[str, str]] = []

    transcript = capture_dir / "transcript.jsonl"
    if not transcript.is_file() or transcript.stat().st_size == 0:
        errors.append("Falta transcript.jsonl o esta vacio")

    expected_ids = {item.test_id for item in EXPECTED}
    unexpected = sorted(set(results) - expected_ids)
    if unexpected:
        errors.append(f"TEST inesperados en results.csv: {unexpected}")

    for item in EXPECTED:
        row = results.get(item.test_id)
        verdict = "MISSING"
        samples_text = ""
        overflow = ""
        flags_text = ""
        captures = ""
        if row is None:
            errors.append(f"Falta TEST {item.test_id} ({item.key})")
        else:
            verdict = row.get("RESULT", "")
            samples_text = row.get("SAMPLES", "")
            overflow = row.get("ADC_OVF", "")
            flags_text = row.get("FLAGS", "")

            if verdict == "FAIL" or verdict == "":
                errors.append(f"TEST {item.test_id}: RESULT={verdict or 'vacio'}")
            elif verdict != "PASS":
                warnings.append(f"TEST {item.test_id}: RESULT={verdict}, FLAGS={flags_text}")

            try:
                samples = int(samples_text)
                tolerance = sample_tolerance(item.samples)
                if abs(samples - item.samples) > tolerance:
                    errors.append(
                        f"TEST {item.test_id}: SAMPLES={samples}, "
                        f"esperado {item.samples}+/-{tolerance}"
                    )
            except ValueError:
                errors.append(f"TEST {item.test_id}: SAMPLES invalido")

            if overflow != "0":
                errors.append(f"TEST {item.test_id}: ADC_OVF={overflow or 'vacio'}")

            flags = set() if flags_text in {"", "NONE"} else set(flags_text.split(","))
            critical = sorted(flags & CRITICAL_FLAGS)
            if critical:
                errors.append(f"TEST {item.test_id}: flags criticos {critical}")

        test_dir = capture_dir / item.key
        found = []
        if require_waveforms:
            combined = test_dir / f"{item.key}.csv"
            if valid_combined_rigol(combined):
                found.append("CH1-3")
            else:
                for channel in (1, 2, 3):
                    path = test_dir / f"{item.key}_CH{channel}.csv"
                    if path.is_file() and path.stat().st_size > 50:
                        found.append(f"CH{channel}")
                    else:
                        errors.append(
                            "Falta captura valida: "
                            f"{combined.relative_to(capture_dir)} o "
                            f"{path.relative_to(capture_dir)}"
                        )

            ila = test_dir / f"{item.key}_ILA.csv"
            ila_required = require_ila_all or item.key == "E1a"
            if ila.is_file() and ila.stat().st_size > 50:
                found.append("ILA")
            elif ila_required:
                errors.append(f"Falta ILA requerido: {ila.relative_to(capture_dir)}")
            else:
                warnings.append(f"{item.key}: sin ILA (opcional tras validar E1a)")
        captures = ",".join(found) if found else ("N/A" if not require_waveforms else "MISSING")

        report_rows.append(
            {
                "TEST": str(item.test_id),
                "Key": item.key,
                "Result": verdict,
                "Samples": samples_text,
                "ADC_OVF": overflow,
                "Flags": flags_text,
                "Captures": captures,
            }
        )
    return report_rows, errors, warnings


def write_markdown(
    path: Path,
    capture_dir: Path,
    rows: list[dict[str, str]],
    errors: list[str],
    warnings: list[str],
) -> None:
    lines = [
        "# OHSIM run evidence",
        "",
        f"Capture directory: `{capture_dir}`",
        "",
        "| TEST | Key | Result | Samples | ADC_OVF | Flags | Captures |",
        "|---:|---|---|---:|---:|---|---|",
    ]
    for row in rows:
        lines.append(
            "| {TEST} | {Key} | {Result} | {Samples} | {ADC_OVF} | {Flags} | {Captures} |".format(
                **row
            )
        )
    lines.extend(["", f"Overall: **{'FAIL' if errors else 'PASS'}**", ""])
    if errors:
        lines.extend(["## Errors", ""] + [f"- {item}" for item in errors] + [""])
    if warnings:
        lines.extend(["## Warnings", ""] + [f"- {item}" for item in warnings] + [""])
    path.write_text("\n".join(lines), encoding="utf-8")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("capture_dir", type=Path)
    parser.add_argument(
        "--no-waveforms",
        action="store_true",
        help="Audit only firmware results/transcript",
    )
    parser.add_argument(
        "--require-ila-all",
        action="store_true",
        help="Require one ILA CSV for every test (E1a is always required)",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    capture_dir = args.capture_dir.resolve()
    rows, errors, warnings = audit_capture(
        capture_dir,
        require_waveforms=not args.no_waveforms,
        require_ila_all=args.require_ila_all,
    )
    report = capture_dir / "evidence_report.md"
    capture_dir.mkdir(parents=True, exist_ok=True)
    write_markdown(report, capture_dir, rows, errors, warnings)
    print(f"Evidence report: {report}")
    for item in errors:
        print(f"ERROR: {item}")
    for item in warnings:
        print(f"WARNING: {item}")
    print("OVERALL: " + ("FAIL" if errors else "PASS"))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
