import importlib.util
import json
import os
import pathlib
import unittest


BRIDGE_PATH = pathlib.Path(__file__).parents[1] / "runtime" / "fjar_bridge.py"

os.environ.setdefault(
    "FJAR_WALLET",
    "fjarcode:qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq",
)

SPEC = importlib.util.spec_from_file_location("fjar_bridge", BRIDGE_PATH)
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


class FakeSocket:
    def __init__(self):
        self.sent = []

    def sendall(self, payload):
        self.sent.append(payload)


class DevFeeScheduleTests(unittest.TestCase):
    def setUp(self):
        self.schedule = BRIDGE.DevFeeSchedule(
            "153300000144|RGB-153300000144",
            fee_basis_points=100,
            cycle_seconds=6000,
        )
        self.origin = -self.schedule.phase_offset

    def test_exact_one_percent_window(self):
        modes = [
            self.schedule.mode_at(self.origin + second)
            for second in range(6000)
        ]
        self.assertEqual(modes.count(BRIDGE.DEV_MODE), 60)
        self.assertEqual(modes.count(BRIDGE.USER_MODE), 5940)

    def test_boundaries_and_next_switch(self):
        self.assertEqual(
            self.schedule.mode_at(self.origin),
            BRIDGE.USER_MODE,
        )
        self.assertEqual(
            self.schedule.mode_at(self.origin + 5939.999),
            BRIDGE.USER_MODE,
        )
        self.assertEqual(
            self.schedule.mode_at(self.origin + 5940),
            BRIDGE.DEV_MODE,
        )
        self.assertEqual(
            self.schedule.mode_at(self.origin + 5999.999),
            BRIDGE.DEV_MODE,
        )
        self.assertEqual(
            self.schedule.mode_at(self.origin + 6000),
            BRIDGE.USER_MODE,
        )
        self.assertAlmostEqual(
            self.schedule.seconds_until_switch(self.origin),
            5940,
        )
        self.assertAlmostEqual(
            self.schedule.seconds_until_switch(self.origin + 5940),
            60,
        )

    def test_phase_is_stable_and_identity_specific(self):
        same = BRIDGE.DevFeeSchedule(
            "153300000144|RGB-153300000144",
            fee_basis_points=100,
            cycle_seconds=6000,
        )
        other = BRIDGE.DevFeeSchedule(
            "153300000957|RGB-153300000957",
            fee_basis_points=100,
            cycle_seconds=6000,
        )
        self.assertEqual(self.schedule.phase_offset, same.phase_offset)
        self.assertNotEqual(self.schedule.phase_offset, other.phase_offset)


class ConfigurationTests(unittest.TestCase):
    def test_user_wallet_is_required(self):
        original = BRIDGE.USER_WALLET
        try:
            BRIDGE.USER_WALLET = ""
            with self.assertRaisesRegex(ValueError, "FJAR_WALLET is required"):
                BRIDGE.validate_configuration()
        finally:
            BRIDGE.USER_WALLET = original

    def test_confirmed_developer_wallet(self):
        self.assertEqual(
            BRIDGE.DEV_WALLET,
            "fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l",
        )
        self.assertEqual(
            BRIDGE.wallet_for_mode(BRIDGE.DEV_MODE),
            BRIDGE.DEV_WALLET,
        )


class SubmissionTests(unittest.TestCase):
    def setUp(self):
        BRIDGE.submit_id = 100
        BRIDGE.pending_submits.clear()

    def test_submit_uses_wallet_recorded_on_job(self):
        sock = FakeSocket()
        job = {
            "username": "fjarcode:qexampleuserwallet.worker1",
            "job_id": "job-123",
            "extranonce2": "0000000000000000",
            "ntime": "12345678",
            "fee_mode": BRIDGE.USER_MODE,
        }

        BRIDGE.submit(sock, job, 0x1234ABCD)

        message = json.loads(sock.sent[0].decode())
        self.assertEqual(message["id"], 100)
        self.assertEqual(message["method"], "mining.submit")
        self.assertEqual(message["params"][0], job["username"])
        self.assertEqual(message["params"][4], "1234abcd")
        self.assertEqual(
            BRIDGE.pending_submits[100]["fee_mode"],
            BRIDGE.USER_MODE,
        )


if __name__ == "__main__":
    unittest.main()
