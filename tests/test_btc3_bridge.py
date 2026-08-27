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


if __name__ == "__main__":
    unittest.main()
