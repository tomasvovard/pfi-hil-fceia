# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

"""Prove that the C presets exactly match experiments/experiments.csv."""

from __future__ import annotations

import csv
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CSV_PATH = ROOT / "experiments" / "experiments.csv"
C_PATH = ROOT / "ohsim_controller_cpu1" / "src" / "test_presets.c"

LOADS = {
    "LOAD_16P6_OHM": "00",
    "LOAD_25_OHM": "01",
    "LOAD_HOLD": "10",
    "LOAD_50_OHM": "11",
}
TRIGGERS = {
    "TRIGGER_NONE": "NONE",
    "TRIGGER_DUTY": "DUTY",
    "TRIGGER_LOAD": "LOAD",
}
KINDS = {
    "SEGMENT_PRECONDITION": "PRECONDITION",
    "SEGMENT_PRETRIGGER": "PRETRIGGER",
    "SEGMENT_STEP": "STEP",
}


def csv_recipes() -> dict[int, tuple[str, list[tuple[int, int, str, str, str]]]]:
    recipes: dict[int, tuple[str, list[tuple[int, int, str, str, str]]]] = {}
    with CSV_PATH.open(newline="", encoding="utf-8") as stream:
        for row in csv.DictReader(stream):
            test_id = int(row["test_id"])
            name, segments = recipes.setdefault(test_id, (row["test_name"], []))
            if name != row["test_name"]:
                raise AssertionError(f"TEST {test_id} changes name within CSV")
            segments.append(
                (
                    int(row["duty_ppm"]),
                    int(row["hold_us"]),
                    row["load_gray"],
                    row["trigger"],
                    row["phase"],
                )
            )
    return recipes


def c_recipes() -> dict[int, tuple[str, list[tuple[int, int, str, str, str]]]]:
    source = C_PATH.read_text(encoding="utf-8")
    arrays: dict[str, list[tuple[int, int, str, str, str]]] = {}
    for match in re.finditer(
        r"static\s+const\s+TestSegment\s+(\w+)\[\]\s*=\s*\{(.*?)\};",
        source,
        re.DOTALL,
    ):
        segments = []
        for item in re.finditer(
            r"\{\s*(\d+)UL\s*,\s*(\d+)UL\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*\}",
            match.group(2),
        ):
            duty, hold, load, trigger, kind = item.groups()
            segments.append(
                (int(duty), int(hold), LOADS[load], TRIGGERS[trigger], KINDS[kind])
            )
        arrays[match.group(1)] = segments

    result = {}
    preset_block = re.search(
        r"static\s+const\s+TestPreset\s+presets\[\]\s*=\s*\{(.*?)\};",
        source,
        re.DOTALL,
    )
    if preset_block is None:
        raise AssertionError("presets[] not found")
    for item in re.finditer(
        r"\{\s*(\d+)U\s*,\s*\"([^\"]+)\"\s*,\s*(\w+)\s*,",
        preset_block.group(1),
    ):
        test_id, name, array = item.groups()
        result[int(test_id)] = (name, arrays[array])
    return result


class RecipeConsistencyTests(unittest.TestCase):
    def test_c_presets_equal_csv(self) -> None:
        self.assertEqual(c_recipes(), csv_recipes())


if __name__ == "__main__":
    unittest.main()
