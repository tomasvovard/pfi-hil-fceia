# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Tomás Vovard
# pfi-hil-fceia: OHSIM + modelo de buck (PFI Ingeniería Electrónica, FCEIA-UNR)

import unittest

from ohsim_cli import parse_fields


class ParseFieldsTests(unittest.TestCase):
    def test_result_line(self):
        line = (
            "OK RESULT=WARNING TEST=11 SAMPLES=3340 IL_MIN_RAW=73 "
            "FLAGS=IL_NEAR_ZERO,CAL_REQUIRED"
        )
        self.assertEqual(
            parse_fields(line),
            {
                "RESULT": "WARNING",
                "TEST": "11",
                "SAMPLES": "3340",
                "IL_MIN_RAW": "73",
                "FLAGS": "IL_NEAR_ZERO,CAL_REQUIRED",
            },
        )

    def test_event_line(self):
        fields = parse_fields("!EVT STATE=ARMED TEST=31")
        self.assertEqual(fields["STATE"], "ARMED")
        self.assertEqual(fields["TEST"], "31")


if __name__ == "__main__":
    unittest.main()
