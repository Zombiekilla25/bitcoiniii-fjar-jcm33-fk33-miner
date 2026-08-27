import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).parents[1] / "runtime" / "btc3_bridge.py"
SPEC = importlib.util.spec_from_file_location("btc3_bridge", MODULE_PATH)
btc3 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(btc3)


class Btc3ConfigurationTests(unittest.TestCase):
    def test_bc3_address_shape_is_accepted(self):
        self.assertIsNotNone(btc3.ADDRESS_RE.fullmatch("bc1q" + "q" * 38))

    def test_fjar_address_is_rejected(self):
        self.assertIsNone(
            btc3.ADDRESS_RE.fullmatch(
                "fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l"
            )
        )

    def test_canary_has_no_developer_wallet_rotation(self):
        schedule = btc3.DevFeeSchedule(
            "test-card", fee_basis_points=btc3.DEV_FEE_BPS
        )
        self.assertEqual(schedule.dev_seconds, 0)
        for timestamp in (0, 1, 5999, 6000, 123456789):
            self.assertEqual(schedule.mode_at(timestamp), btc3.USER_MODE)
            self.assertEqual(
                btc3.wallet_for_mode(schedule.mode_at(timestamp)),
                btc3.USER_WALLET,
            )

    def test_sha3t_is_three_sha3_256_rounds(self):
        import hashlib

        payload = bytes(range(80))
        expected = payload
        for _ in range(3):
            expected = hashlib.sha3_256(expected).digest()
        self.assertEqual(btc3.sha3t(payload), expected)


class Btc3LauncherTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        root = pathlib.Path(__file__).parents[1]
        cls.canary = (root / "start-btc3-canary.sh").read_text()
        cls.fleet = (root / "start-btc3.sh").read_text()

    def test_canary_still_requires_exactly_one_card(self):
        self.assertIn(
            "BTC3 canary requires exactly one --serials value", self.canary
        )

    def test_fleet_accepts_a_serial_list(self):
        self.assertNotIn("requires exactly one --serials value", self.fleet)
        self.assertIn("Comma/space-separated FK33 USB serials", self.fleet)

    def test_fleet_requires_explicit_canary_acknowledgement(self):
        self.assertIn("--canary-passed", self.fleet)
        self.assertIn("CANARY_PASSED", self.fleet)

    def test_fleet_stays_on_pinned_525_image(self):
        self.assertIn(
            "64e0a7d21a10b4aa04b340c826af7d75363b5d5ba5e39330fe28c42ff103821c",
            self.fleet,
        )
        self.assertNotIn("experimental-550", self.fleet)


if __name__ == "__main__":
    unittest.main()
