#!/usr/bin/env python3
"""Regression tests for the FJAR extranonce2 work roller."""

import importlib.util
import json
import struct
import unittest
from pathlib import Path


RUNTIME = (
    Path(__file__).resolve().parents[1] / "runtime" / "fjar_bridge.py"
)


def load_runtime():
    spec = importlib.util.spec_from_file_location("fjar_bridge_under_test", RUNTIME)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FakeSocket:
    def __init__(self):
        self.writes = []

    def sendall(self, data):
        self.writes.append(data)


class FakeHardware:
    def __init__(self, shares=()):
        self.shares = list(shares)

    def pop_share(self):
        if not self.shares:
            return None
        return self.shares.pop(0)


class ExtranonceRollTests(unittest.TestCase):
    def setUp(self):
        self.bridge = load_runtime()
        self.bridge.extranonce1 = "a1b2c3d4"
        self.bridge.extranonce2_size = 4
        self.bridge.difficulty = 1.0
        self.bridge.tag_counter = 0
        self.bridge.jobs.clear()
        self.bridge.submitted_shares.clear()
        self.bridge.pending_submits.clear()

        self.notify = [
            "job-123",
            "00" * 32,
            "01000000",
            "ffffffff",
            [],
            "20000000",
            "1d00ffff",
            "66000000",
            True,
        ]

    def make_job(self, counter):
        return self.bridge.build_job(
            self.notify,
            "fjarcode:qqqqqqqqqqqqqqqqqqqq",
            self.bridge.USER_MODE,
            counter,
        )

    def test_extranonce_encoding_uses_pool_width_and_wraps(self):
        self.assertEqual(self.bridge.encode_extranonce2(0), "00000000")
        self.assertEqual(self.bridge.encode_extranonce2(1), "00000001")
        self.assertEqual(
            self.bridge.encode_extranonce2(0x1_0000_0001),
            "00000001",
        )

    def test_roll_changes_header_but_preserves_pool_job(self):
        first = self.make_job(0)
        second = self.make_job(1)

        self.assertEqual(first["extranonce2"], "00000000")
        self.assertEqual(second["extranonce2"], "00000001")
        self.assertEqual(first["job_id"], second["job_id"])
        self.assertEqual(first["ntime"], second["ntime"])
        self.assertEqual(first["target"], second["target"])
        self.assertEqual(first["difficulty"], 1.0)
        self.assertNotEqual(first["tag"], second["tag"])
        self.assertNotEqual(first["prefix"], second["prefix"])
        self.assertEqual(len(first["prefix"]), 76)

    def test_submit_carries_rolled_extranonce2(self):
        job = self.make_job(7)
        sock = FakeSocket()

        self.bridge.submit(sock, job, 0x12345678)
        request = json.loads(sock.writes[0])

        self.assertEqual(request["method"], "mining.submit")
        self.assertEqual(request["params"][1], "job-123")
        self.assertEqual(request["params"][2], "00000007")
        self.assertEqual(request["params"][3], "66000000")
        self.assertEqual(request["params"][4], "12345678")
        self.assertEqual(
            self.bridge.pending_submits[request["id"]]["difficulty"],
            1.0,
        )

    def test_duplicate_key_includes_extranonce2(self):
        first = self.make_job(0)
        second = self.make_job(1)
        nonce = 0x01020304

        def candidate(job):
            digest = self.bridge.sha3t(
                job["prefix"] + struct.pack("<I", nonce)
            ).hex()
            return job["tag"], nonce, digest

        # Maximum target makes both software-verified candidates submit.
        first["target"] = (1 << 256) - 1
        second["target"] = (1 << 256) - 1
        hardware = FakeHardware((candidate(first), candidate(second)))
        sock = FakeSocket()

        self.bridge.check_share(sock, hardware)
        self.bridge.check_share(sock, hardware)

        self.assertEqual(len(sock.writes), 2)
        requests = [json.loads(write) for write in sock.writes]
        self.assertEqual(requests[0]["params"][2], "00000000")
        self.assertEqual(requests[1]["params"][2], "00000001")


if __name__ == "__main__":
    unittest.main(verbosity=2)
