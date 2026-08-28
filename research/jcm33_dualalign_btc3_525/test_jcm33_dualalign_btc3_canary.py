#!/usr/bin/env python3
"""Offline tests for the JCM33 dual-alignment BitcoinIII canary."""

import importlib.util
import json
import os
from pathlib import Path
import sys
import unittest


ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
MINER_PATH = ROOT / "jcm33_btc3_dual_miner.py"
TRANSPORT_PATH = ROOT / "fk33_bscan_transport.sv"
RUNNER_PATH = ROOT / "run_jcm33_dualalign_btc3_canary.sh"
BUILD_PATH = ROOT / "build_jcm33_dualalign_bscan_525.tcl"
os.environ.setdefault(
    "BTC3_WALLET", "bc1q0000000000000000000000000000000000000000"
)
SPEC = importlib.util.spec_from_file_location("jcm33_btc3_dual", MINER_PATH)
miner = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(miner)


class FakeHardware:
    def __init__(self):
        self.pairs = []

    def send_job_pair(self, job_a, job_b):
        self.pairs.append((job_a, job_b))


class FakePoolSocket:
    def __init__(self):
        self.writes = []

    def sendall(self, data):
        self.writes.append(data)


class DualMinerTests(unittest.TestCase):
    def setUp(self):
        miner.extranonce1 = ""
        miner.extranonce2_size = 8
        miner.difficulty = 0.01
        miner.tag_counter = 0
        miner.jobs.clear()
        miner.submitted_shares.clear()
        miner.pending_submits.clear()

    def notify_params(self):
        return [
            "job-1",
            "00" * 32,
            "",
            "",
            [],
            "00000001",
            "1d00ffff",
            "65000000",
            True,
        ]

    def test_crc16_standard_vector(self):
        self.assertEqual(miner.crc16(b"123456789"), 0x29B1)

    def test_bitcoiniii_developer_fee_is_visible_and_network_specific(self):
        schedule = miner.DevFeeSchedule("test-jcm33")
        self.assertEqual(miner.DEV_FEE_BPS, 100)
        self.assertEqual((schedule.user_seconds, schedule.dev_seconds), (5940, 60))
        self.assertEqual(
            miner.DEV_WALLET,
            "bc1qwcusej0umav5dw9k9f6cuy6mhzsdj9su4rayqu",
        )
        self.assertEqual(miner.wallet_for_mode(miner.USER_MODE), miner.USER_WALLET)
        self.assertEqual(miner.wallet_for_mode(miner.DEV_MODE), miner.DEV_WALLET)
        self.assertEqual(miner.worker_for_mode(miner.USER_MODE), miner.WORKER)
        self.assertTrue(miner.worker_for_mode(miner.DEV_MODE).endswith("-DEVFEE"))

    def test_production_job_wire_frame_is_117_bytes(self):
        job_a, _ = miner.build_job_pair(
            self.notify_params(), miner.USER_WALLET, miner.USER_MODE, 0
        )
        frame = miner.job_wire_frame(job_a)
        self.assertEqual(len(frame), 117)
        self.assertEqual(frame[:6], b"FJ\x01\x01m\x00")

    def test_pair_uses_distinct_tags_and_extranonces(self):
        job_a, job_b = miner.build_job_pair(
            self.notify_params(), miner.USER_WALLET, miner.USER_MODE, 0
        )
        self.assertEqual((job_a["tag"], job_b["tag"]), (1, 2))
        self.assertEqual((job_a["device"], job_b["device"]), ("A", "B"))
        self.assertEqual(job_a["extranonce2"], "0000000000000000")
        self.assertEqual(job_b["extranonce2"], "0000000000000001")

    def test_dispatch_preserves_independent_a_then_b_order(self):
        job_a, job_b = miner.build_job_pair(
            self.notify_params(), miner.USER_WALLET, miner.USER_MODE, 0
        )
        hardware = FakeHardware()
        miner.dispatch_job_pair(hardware, job_a, job_b)
        self.assertEqual(hardware.pairs, [(job_a, job_b)])

    def test_atomic_pair_fits_xvc_limit(self):
        job_a, job_b = miner.build_job_pair(
            self.notify_params(), miner.USER_WALLET, miner.USER_MODE, 0
        )
        a = miner.build_per_byte_write(0, miner.job_wire_frame(job_a))
        b = miner.build_per_byte_write(1, miner.job_wire_frame(job_b))
        pair = miner.concatenate_programs(a, b)
        self.assertEqual(len(pair.tms), 3852)
        self.assertLess(len(pair.tms), 4096)

    def test_share_decoder_keeps_lane_identity(self):
        payload = bytes((0x51,)) + (7).to_bytes(4, "little") + bytes(range(32))
        frame = miner.encode_frame(miner.FRAME_SHARE, payload)
        transport = miner.HardwareTransport("unused", 1)
        transport.buffers["B"].extend(frame)
        frame_type, decoded = transport._pop_frame("B")
        self.assertEqual(frame_type, miner.FRAME_SHARE)
        self.assertEqual(decoded, payload)

    def test_valid_share_submission_contains_assigned_job(self):
        job_a, _ = miner.build_job_pair(
            self.notify_params(), miner.USER_WALLET, miner.USER_MODE, 0
        )
        nonce = 3
        digest = miner.sha3t(
            job_a["prefix"] + nonce.to_bytes(4, "little")
        ).hex()
        # Ensure the synthetic job accepts the valid software-matched digest.
        job_a["target"] = (1 << 256) - 1
        pool = FakePoolSocket()
        miner.check_one_share(pool, "A", job_a["tag"], nonce, digest)
        self.assertEqual(len(pool.writes), 1)
        message = json.loads(pool.writes[0])
        self.assertEqual(message["method"], "mining.submit")
        self.assertEqual(message["params"][2], job_a["extranonce2"])

    def test_launcher_accepts_resolved_system_libraries(self):
        launcher = RUNNER_PATH.read_text()
        self.assertNotIn("missing compatibility library:", launcher)
        self.assertIn("ldd \"$BRIDGE\"", launcher)
        self.assertIn("grep -q 'not found'", launcher)


class DualAlignmentTests(unittest.TestCase):
    @staticmethod
    def decode_stream(raw_words):
        alignment = None
        decoded = []
        for raw_word in raw_words:
            low = raw_word & 0xFF
            high = (raw_word >> 1) & 0xFF
            if alignment is None:
                if low == 0x46:
                    alignment = "low"
                elif high == 0x46:
                    alignment = "high"
                else:
                    continue
            decoded.append(low if alignment == "low" else high)
        return alignment, bytes(decoded)

    def test_low_and_high_chain_positions_decode_same_frame(self):
        frame = b"FJ\x01\x01m\x00" + bytes(range(32))
        low_alignment, low_frame = self.decode_stream(list(frame))
        high_alignment, high_frame = self.decode_stream(
            [value << 1 for value in frame]
        )
        self.assertEqual(low_alignment, "low")
        self.assertEqual(high_alignment, "high")
        self.assertEqual(low_frame, frame)
        self.assertEqual(high_frame, frame)

    def test_hdl_collects_all_nine_bits_and_locks_on_magic(self):
        hdl = TRANSPORT_PATH.read_text()
        self.assertIn("logic [8:0] rx_word2", hdl)
        self.assertIn("rx_bit_count2 == 4'd8", hdl)
        self.assertIn("completed_rx_low2 == 8'h46", hdl)
        self.assertIn("completed_rx_high2 == 8'h46", hdl)
        self.assertIn("consume_job_byte(completed_rx_low2)", hdl)
        self.assertIn("consume_job_byte(completed_rx_high2)", hdl)
        self.assertNotIn("logic [7:0] rx_shift2", hdl)

    def test_build_is_timing_gated_and_uncompressed(self):
        build = BUILD_PATH.read_text()
        self.assertIn("TIMING GATE PASS", build)
        self.assertIn("negative setup slack", build)
        self.assertIn("negative hold slack", build)
        self.assertIn("BITSTREAM.GENERAL.COMPRESS FALSE", build)
        self.assertIn("jcm33_dualalign_bscan_525.bit", build)

    def test_runner_requires_both_devices_and_has_no_restore(self):
        runner = RUNNER_PATH.read_text()
        self.assertIn("(( accepted_a > 0 ))", runner)
        self.assertIn("(( accepted_b > 0 ))", runner)
        self.assertIn("build_jcm33_dualalign_bscan_525.tcl", runner)
        self.assertNotIn("restore_jcm33_350", runner)
        self.assertNotIn("fk33_fjar_bscan_350", runner)
        self.assertNotIn('"$BRIDGE" -v ', runner)
        self.assertNotIn('"$BRIDGE" -V ', runner)


if __name__ == "__main__":
    unittest.main(verbosity=2)
