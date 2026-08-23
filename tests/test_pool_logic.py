#!/usr/bin/env python3
"""Offline fee-boundary, configuration, and submission tests."""

import importlib.util
import json
import os
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
BRIDGE_PATH = ROOT / "runtime" / "fjar_bridge.py"

os.environ.setdefault(
    "FJAR_WALLET",
    "fjarcode:qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
)

SPEC = importlib.util.spec_from_file_location("fjar_bridge", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class FakeSocket:
    def __init__(self):
        self.sent = []

    def sendall(self, payload):
        self.sent.append(payload)


class FeeTests(unittest.TestCase):
    def setUp(self):
        self.schedule = bridge.DevFeeSchedule("card-a|worker-a")
        self.origin = -self.schedule.phase_offset

    def test_exact_window_and_boundaries(self):
        modes = [
            self.schedule.mode_at(self.origin + second)
            for second in range(6000)
        ]
        self.assertEqual(modes.count(bridge.USER_MODE), 5940)
        self.assertEqual(modes.count(bridge.DEV_MODE), 60)
        self.assertEqual(
            self.schedule.mode_at(self.origin + 5939.999),
            bridge.USER_MODE,
        )
        self.assertEqual(
            self.schedule.mode_at(self.origin + 5940),
            bridge.DEV_MODE,
        )
        self.assertEqual(
            self.schedule.mode_at(self.origin + 6000),
            bridge.USER_MODE,
        )

    def test_phase_is_stable_and_identity_specific(self):
        same = bridge.DevFeeSchedule("card-a|worker-a")
        other = bridge.DevFeeSchedule("card-b|worker-b")
        self.assertEqual(self.schedule.phase_offset, same.phase_offset)
        self.assertNotEqual(self.schedule.phase_offset, other.phase_offset)


class ConfigurationTests(unittest.TestCase):
    def test_user_wallet_is_required(self):
        original = bridge.USER_WALLET
        try:
            bridge.USER_WALLET = ""
            with self.assertRaisesRegex(ValueError, "FJAR_WALLET is required"):
                bridge.validate_configuration()
        finally:
            bridge.USER_WALLET = original

    def test_developer_wallet_is_confirmed(self):
        self.assertEqual(
            bridge.DEV_WALLET,
            "fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l",
        )


class SubmissionTests(unittest.TestCase):
    def test_submit_uses_the_job_wallet_and_nonce_order(self):
        bridge.submit_id = 100
        bridge.pending_submits.clear()
        sock = FakeSocket()
        job = {
            "username": "fjarcode:qexampleuserwallet.worker1",
            "job_id": "job-123",
            "extranonce2": "0000000000000000",
            "ntime": "12345678",
            "fee_mode": bridge.USER_MODE,
            "difficulty": 16.0,
        }

        bridge.submit(sock, job, 0x1234ABCD)
        message = json.loads(sock.sent[0].decode())
        self.assertEqual(message["params"][0], job["username"])
        self.assertEqual(message["params"][4], "1234abcd")
        self.assertEqual(
            bridge.pending_submits[100]["fee_mode"],
            bridge.USER_MODE,
        )
        self.assertEqual(
            bridge.pending_submits[100]["difficulty"],
            16.0,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
