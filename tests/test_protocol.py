#!/usr/bin/env python3
"""Offline framing tests for the standalone FK33 FJAR transport."""

import importlib.util
import os
from pathlib import Path
import socket
import tempfile
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

    def test_fleet_mapping_accepts_exact_serial_port_pair(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "fleet.env"
            log = Path(directory) / "sqrl.log"
            config.write_text("FJAR_FLEET_SERIALS=111111,222222\n")
            log.write_text(
                "Device with serial 111111A matches filter\n"
                "Opened virtual TCP serial port 22000\n"
                "Device with serial 222222A matches filter\n"
                "Opened virtual TCP serial port 22001\n"
                "Bitstream Loaded\nBitstream Loaded\n"
            )
            bridge.validate_fleet_mapping(
                "111111", 22000, str(config), str(log)
            )

    def test_fleet_mapping_rejects_a_later_cards_port(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "fleet.env"
            log = Path(directory) / "sqrl.log"
            config.write_text("FJAR_FLEET_SERIALS=111111,222222\n")
            log.write_text(
                "Device with serial 111111A matches filter\n"
                "Opened virtual TCP serial port 22000\n"
                "Device with serial 222222A matches filter\n"
                "Opened virtual TCP serial port 22001\n"
                "Bitstream Loaded\nBitstream Loaded\n"
            )
            with self.assertRaises(bridge.HardwareDisconnected):
                bridge.validate_fleet_mapping(
                    "111111", 22001, str(config), str(log)
                )


if __name__ == "__main__":
    unittest.main(verbosity=2)
