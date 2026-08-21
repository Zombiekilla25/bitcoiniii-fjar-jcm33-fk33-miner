#!/usr/bin/env python3
"""Live 117-byte-in / 45-byte-out protocol test for the FK33 probe image."""

import importlib.util
import os
from pathlib import Path
import time


ROOT = Path(__file__).resolve().parents[1]
BRIDGE_PATH = ROOT / "runtime" / "fjar_bridge.py"

os.environ.setdefault(
    "FJAR_WALLET",
    "fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l",
)

SPEC = importlib.util.spec_from_file_location("fjar_bridge_bscan", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


def main():
    host = os.environ.get("FJAR_HW_HOST", "127.0.0.1")
    port = int(os.environ.get("FJAR_HW_PORT", "22000"))
    transport = bridge.HardwareTransport(host, port)

    tag = 0xA7
    prefix = bytes(range(76))
    target_bytes = bytes(range(0x80, 0xA0))
    target = int.from_bytes(target_bytes, "little")
    job = {"tag": tag, "prefix": prefix, "target": target}

    expected = (
        tag,
        int.from_bytes(target_bytes[:4], "little"),
        prefix[:32][::-1].hex(),
    )

    try:
        transport.send_job(job)
        print("sent complete job frame: 117 bytes")
        deadline = time.monotonic() + 30
        received = None
        while time.monotonic() < deadline:
            received = transport.pop_share()
            if received is not None:
                break
            time.sleep(0.02)
    finally:
        transport.close()

    print(f"expected: tag={expected[0]:02x} nonce={expected[1]:08x}")
    print(f"expected digest={expected[2]}")
    if received is None:
        raise SystemExit("PROTOCOL PROBE FAIL: no complete share frame")
    print(f"received: tag={received[0]:02x} nonce={received[1]:08x}")
    print(f"received digest={received[2]}")
    if received != expected:
        raise SystemExit("PROTOCOL PROBE FAIL: payload or byte order mismatch")

    print("PROTOCOL PROBE PASS — 117 BYTES IN, 45 BYTES OUT")


if __name__ == "__main__":
    main()
