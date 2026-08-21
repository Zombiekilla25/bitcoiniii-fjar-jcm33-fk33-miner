#!/usr/bin/env python3
"""Apply the two validated raw USER1/USER2 patches to the SQRL bridge."""

from __future__ import annotations

import hashlib
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

SOURCE_SHA256 = "4381283543d0c39650463f7ad8a91874eaeb0c5b2884be263fc4f9ab7bd19ec5"
OUTPUT_SHA256 = "8c7230f0bf586e9297dc0e568bd19278aeeb7cff8dbb3dde150811f11393218a"

PATCHES = (
    (
        0x210F6,
        bytes.fromhex("48 8b 7f 10 41 89 cd 4d 89 c6 48 85 ff 74 73"),
        bytes.fromhex("41 89 cd 4d 89 c6 e9 1f 01 00 00 90 90 90 90"),
        "V2 bulk read: CoE FIFO -> raw USER1",
    ),
    (
        0x2144C,
        bytes.fromhex("0f 84 5e 01 00 00"),
        bytes.fromhex("e9 d6 00 00 00 90"),
        "V1 bulk write: CoE command 0x1204 -> raw USER2",
    ),
)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} ORIGINAL OUTPUT")

    source = Path(sys.argv[1])
    output = Path(sys.argv[2])
    original = source.read_bytes()

    if digest(original) != SOURCE_SHA256:
        raise SystemExit("Refused: source SHA256 does not match the validated artifact")

    sections = subprocess.check_output(
        ["readelf", "-W", "-S", str(source)], text=True
    )
    match = re.search(
        r"\[\s*\d+\]\s+\.text\s+\S+\s+"
        r"([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+([0-9a-fA-F]+)",
        sections,
    )
    if not match:
        raise SystemExit("Could not locate ELF .text section")

    text_address, text_offset, text_size = (
        int(value, 16) for value in match.groups()
    )
    data = bytearray(original)

    for address, expected, replacement, description in PATCHES:
        if not (
            text_address <= address
            and address + len(expected) <= text_address + text_size
        ):
            raise SystemExit(f"Patch outside .text: {description}")
        offset = text_offset + address - text_address
        actual = bytes(data[offset : offset + len(expected)])
        if actual != expected:
            raise SystemExit(f"Original bytes differ at 0x{address:x}: {description}")
        data[offset : offset + len(replacement)] = replacement
        print(f"patched 0x{address:x}: {description}")

    result = bytes(data)
    if digest(result) != OUTPUT_SHA256:
        raise SystemExit("Refused: patched output checksum is unexpected")

    output.write_bytes(result)
    os.chmod(output, stat.S_IMODE(source.stat().st_mode))
    print(f"{OUTPUT_SHA256}  {output}")


if __name__ == "__main__":
    main()
