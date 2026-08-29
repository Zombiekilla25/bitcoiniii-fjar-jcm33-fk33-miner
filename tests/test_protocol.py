#!/usr/bin/env python3
"""Offline framing tests for the standalone FK33 FJAR transport."""

import importlib.util
import os
from pathlib import Path
import socket
import unittest


ROOT = Path(__file__).resolve().parents[1]
BRIDGE_PATH = ROOT / "runtime" / "fjar_bridge.py"

os.environ.setdefault(
    "FJAR_WALLET",
    "fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l",
)

SPEC = importlib.util.spec_from_file_location("fjar_bridge_bscan", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class ProtocolTests(unittest.TestCase):
    def test_crc16_standard_vector(self):
        self.assertEqual(bridge.crc16(b"123456789"), 0x29B1)

    def test_job_frame_layout_and_byte_order(self):
        prefix = bytes(range(76))
        target = int.from_bytes(bytes(range(32)), "little")
        payload = bytes((0xA7,)) + prefix + target.to_bytes(32, "little")
        frame = bridge.encode_frame(bridge.FRAME_JOB, payload)

        self.assertEqual(len(payload), 109)
        self.assertEqual(len(frame), 117)
        self.assertEqual(frame[:6], b"FJ\x01\x01\x6d\x00")
        self.assertEqual(frame[6], 0xA7)
        self.assertEqual(frame[7:83], prefix)
        self.assertEqual(frame[83:115], bytes(range(32)))
        self.assertEqual(
            int.from_bytes(frame[-2:], "little"),
            bridge.crc16(payload),
        )

    def test_share_frame_stream_decode(self):
        reader, writer = socket.socketpair()
        self.addCleanup(reader.close)
        self.addCleanup(writer.close)

        transport = bridge.HardwareTransport("unused", 1)
        transport.sock = reader
        reader.setblocking(False)

        tag = 0x5C
        nonce = 0x78563412
        digest = bytes(range(32))
        payload = bytes((tag,)) + nonce.to_bytes(4, "little") + digest
        frame = bridge.encode_frame(bridge.FRAME_SHARE, payload)

        # Exercise resynchronization and fragmented TCP delivery.
        writer.sendall(b"noise" + frame[:11])
        self.assertIsNone(transport.pop_share())
        writer.sendall(frame[11:])

        self.assertEqual(
            transport.pop_share(),
            (tag, nonce, digest.hex()),
        )

    def test_bad_crc_is_discarded(self):
        transport = bridge.HardwareTransport("unused", 1)
        payload = bytes((1,)) + bytes(36)
        frame = bytearray(bridge.encode_frame(bridge.FRAME_SHARE, payload))
        frame[-1] ^= 0x80
        transport.buffer.extend(frame)
        self.assertIsNone(transport._pop_frame())
        self.assertEqual(transport.buffer, bytearray())

    def test_dev_fee_is_exactly_one_percent(self):
        schedule = bridge.DevFeeSchedule("test-card")
        self.assertEqual(schedule.cycle_seconds, 6000)
        self.assertEqual(schedule.dev_seconds, 60)
        self.assertEqual(schedule.user_seconds, 5940)

    def test_fleet_mapping_is_enforced_by_readiness_helper(self):
        helper = (ROOT / "runtime" / "wait-fleet-card.sh").read_text()
        self.assertIn("mapping_ready()", helper)
        self.assertIn("Device with serial ", helper)
        self.assertIn("Opened virtual TCP serial port ", helper)
        self.assertIn("LOADED >= EXPECTED_LOADS", helper)

    def test_readiness_helper_runs_before_python_miner(self):
        unit = (
            ROOT / "systemd" / "fjar-fk33-fleet@.service"
        ).read_text()
        preflight = "ExecStartPre=%h/.local/share/fk33-fjar-miner/"
        self.assertIn(preflight, unit)
        self.assertIn("wait-fleet-card.sh %i ${FJAR_HW_PORT}", unit)
        self.assertLess(
            unit.index("ExecStartPre="),
            unit.index("ExecStart=/usr/bin/python3"),
        )

    def test_systemd_fleet_bitstream_selection_is_pinned(self):
        launcher = (ROOT / "runtime" / "start-sqrl-fleet.sh").read_text()
        self.assertIn("FJAR_FLEET_BITSTREAM:-525", launcher)
        self.assertIn("fk33_fjar_bscan_525.bit", launcher)
        self.assertIn("fk33_native_bscan_650_validated.bit", launcher)
        self.assertIn(
            "64e0a7d21a10b4aa04b340c826af7d75363b5d5ba5e39330fe28c42ff103821c",
            launcher,
        )
        self.assertIn(
            "bd494ba2ea697a5e916b51caf4bdab8e5c620cd121bfd4b2e9a806deb5596c39",
            launcher,
        )
        self.assertIn("Mining bitstream checksum mismatch", launcher)

    def test_installer_records_explicit_fleet_bitstream(self):
        installer = (ROOT / "install.sh").read_text()
        self.assertIn("--bitstream 525|650", installer)
        self.assertIn("FJAR_FLEET_BITSTREAM=%s", installer)


if __name__ == "__main__":
    unittest.main(verbosity=2)
