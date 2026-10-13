# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

import csv
import tempfile
import unittest
from pathlib import Path

from verify_demo import EXPECTED, audit_capture, sample_tolerance, write_markdown


FIELDS = (
    "RESULT", "TEST", "STEPS", "SAMPLES", "IL_MIN_RAW", "IL_MAX_RAW",
    "IL_MEAN_RAW", "VO_MIN_RAW", "VO_MAX_RAW", "VO_MEAN_RAW",
    "IL_ZERO_RAW", "VO_ZERO_RAW", "ADC_OVF", "ISR_MAX_TICKS", "FLAGS",
)


class DemoAuditTests(unittest.TestCase):
    def make_complete_run(self, root: Path, combined: bool = False) -> None:
        with (root / "results.csv").open("w", newline="", encoding="utf-8") as stream:
            writer = csv.DictWriter(stream, fieldnames=FIELDS)
            writer.writeheader()
            for item in EXPECTED:
                writer.writerow(
                    {
                        "RESULT": "PASS",
                        "TEST": item.test_id,
                        "STEPS": 1,
                        "SAMPLES": item.samples,
                        "ADC_OVF": 0,
                        "FLAGS": "NONE",
                    }
                )
        (root / "transcript.jsonl").write_text('{"line":"ok"}\n', encoding="utf-8")
        for item in EXPECTED:
            test_dir = root / item.key
            test_dir.mkdir()
            if combined:
                (test_dir / f"{item.key}.csv").write_text(
                    "CH1V,CH2V,CH3V,t0=0,tInc=1e-6\n" + "0,0,0\n" * 8
                )
            else:
                for channel in (1, 2, 3):
                    (test_dir / f"{item.key}_CH{channel}.csv").write_text("x" * 64)
        (root / "E1a" / "E1a_ILA.csv").write_text("x" * 64)

    def test_complete_run_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_complete_run(root)
            rows, errors, warnings = audit_capture(root)
            self.assertFalse(errors)
            self.assertEqual(len(rows), 8)
            self.assertEqual(len(warnings), 7)  # ILA is optional after E1a.
            report = root / "evidence_report.md"
            write_markdown(report, root, rows, errors, warnings)
            self.assertIn("Overall: **PASS**", report.read_text(encoding="utf-8"))

    def test_complete_combined_mho900_run_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_complete_run(root, combined=True)
            rows, errors, warnings = audit_capture(root)
            self.assertFalse(errors)
            self.assertEqual(rows[0]["Captures"], "CH1-3,ILA")
            self.assertEqual(len(warnings), 7)

    def test_observed_e1a_sample_latency_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_complete_run(root)
            results = root / "results.csv"
            with results.open(encoding="utf-8") as stream:
                rows = list(csv.DictReader(stream))
            rows[0]["SAMPLES"] = "3349"
            with results.open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=FIELDS)
                writer.writeheader()
                writer.writerows(rows)
            _report_rows, errors, _warnings = audit_capture(root)
            self.assertFalse(any("SAMPLES=3349" in item for item in errors))
            self.assertGreaterEqual(sample_tolerance(3340), 9)

    def test_overflow_and_missing_waveform_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.make_complete_run(root)
            with (root / "results.csv").open(encoding="utf-8") as stream:
                rows = list(csv.DictReader(stream))
            rows[0]["ADC_OVF"] = "1"
            with (root / "results.csv").open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=FIELDS)
                writer.writeheader()
                writer.writerows(rows)
            (root / "E2" / "E2_CH2.csv").unlink()
            _report_rows, errors, _warnings = audit_capture(root)
            self.assertTrue(any("ADC_OVF=1" in item for item in errors))
            self.assertTrue(any("E2_CH2.csv" in item for item in errors))


if __name__ == "__main__":
    unittest.main()
