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

    def test_bitcoiniii_developer_fee_policy(self):
        schedule = btc3.DevFeeSchedule(
            "test-card", fee_basis_points=btc3.DEV_FEE_BPS
        )
        self.assertEqual(btc3.DEV_FEE_BPS, 100)
        self.assertEqual(schedule.user_seconds, 5940)
        self.assertEqual(schedule.dev_seconds, 60)
        self.assertEqual(
            btc3.DEV_WALLET,
            "bc1qwcusej0umav5dw9k9f6cuy6mhzsdj9su4rayqu",
        )
        self.assertEqual(btc3.wallet_for_mode(btc3.USER_MODE), btc3.USER_WALLET)
        self.assertEqual(btc3.wallet_for_mode(btc3.DEV_MODE), btc3.DEV_WALLET)

    def test_developer_worker_is_visibly_labeled(self):
        self.assertEqual(btc3.worker_for_mode(btc3.USER_MODE), btc3.WORKER)
        dev_worker = btc3.worker_for_mode(btc3.DEV_MODE)
        self.assertTrue(dev_worker.endswith("-DEVFEE"))
        self.assertLessEqual(len(dev_worker), 64)

        original_worker = btc3.WORKER
        try:
            btc3.WORKER = "x" * 64
            self.assertEqual(len(btc3.worker_for_mode(btc3.DEV_MODE)), 64)
            self.assertTrue(
                btc3.worker_for_mode(btc3.DEV_MODE).endswith("-DEVFEE")
            )
        finally:
            btc3.WORKER = original_worker

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

    def test_fleet_keeps_525_default_and_pins_650_opt_in(self):
        self.assertIn(
            "64e0a7d21a10b4aa04b340c826af7d75363b5d5ba5e39330fe28c42ff103821c",
            self.fleet,
        )
        self.assertIn(
            "bd494ba2ea697a5e916b51caf4bdab8e5c620cd121bfd4b2e9a806deb5596c39",
            self.fleet,
        )
        self.assertIn('BITSTREAM="$STABLE_BITSTREAM"', self.fleet)
        self.assertIn("--qualified-650", self.fleet)
        self.assertNotIn("experimental-550", self.fleet)


if __name__ == "__main__":
    unittest.main()
