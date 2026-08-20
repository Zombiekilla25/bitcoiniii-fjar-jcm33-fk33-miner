#!/usr/bin/env python3
"""Monitor one or more FK33 VIO status files without pool credentials."""

import argparse
import sys
import time
from pathlib import Path


# One 256-nonce stride evaluates 80 pipes * 3 active contexts.
HASHES_PER_NONCE_STRIDE = 240 / 256


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "root",
        nargs="?",
        type=Path,
        default=Path.home() / ".local/state/fk33-fjar-miner",
        help="directory containing one subdirectory per FK serial",
    )
    parser.add_argument(
        "--serial",
        action="append",
        default=[],
        help="FK serial to monitor; repeat for multiple cards",
    )
    parser.add_argument("--stale-seconds", type=float, default=10.0)
    parser.add_argument("--once", action="store_true")
    return parser.parse_args()


def discover_serials(root):
    return sorted(
        path.name
        for path in root.iterdir()
        if path.is_dir() and (path / "vio_status.txt").is_file()
    )


def new_sample():
    return {
        "mtime": None,
        "tag": None,
        "nonce": None,
        "sample_time": None,
        "mh": None,
        "age": None,
    }


def update_sample(path, sample, monotonic_now, wall_now):
    try:
        stat = path.stat()
    except FileNotFoundError:
        sample["age"] = None
        return

    sample["age"] = max(0.0, wall_now - stat.st_mtime)
    if sample["mtime"] == stat.st_mtime_ns:
        return

    sample["mtime"] = stat.st_mtime_ns
    try:
        tag_text, nonce_text, _pending = path.read_text().strip().split(":")
        tag = int(tag_text, 16)
        nonce = int(nonce_text, 16)
    except (OSError, ValueError):
        return

    if sample["tag"] != tag:
        sample["tag"] = tag
        sample["nonce"] = nonce
        sample["sample_time"] = monotonic_now
        sample["mh"] = None
        return

    if sample["nonce"] is not None and sample["sample_time"] is not None:
        delta_nonce = (nonce - sample["nonce"]) & 0xFFFFFFFF
        delta_time = monotonic_now - sample["sample_time"]
        if delta_nonce and delta_time > 0:
            sample["mh"] = (
                delta_nonce * HASHES_PER_NONCE_STRIDE / delta_time / 1e6
            )

    sample["nonce"] = nonce
    sample["sample_time"] = monotonic_now


def render(root, serials, state, stale_seconds):
    if sys.stdout.isatty():
        print("\033[H\033[J", end="")
    print("FJAR FK33 80-pipe TOKEN3 status")
    print(f"root: {root}")
    print()
    print(f"{'SERIAL':16s} {'RATE':>13s} {'TAG':>5s} {'AGE':>8s}")
    print("-" * 47)

    fleet = 0.0
    valid = 0
    for serial in serials:
        sample = state[serial]
        age = sample["age"]
        stale = age is None or age > stale_seconds

        if sample["mh"] is None:
            rate = "waiting..."
        elif stale:
            rate = "STALE"
        else:
            rate = f"{sample['mh']:8.2f} MH/s"
            fleet += sample["mh"]
            valid += 1

        tag = "--" if sample["tag"] is None else f"{sample['tag']:02x}"
        age_text = "--" if age is None else f"{age:5.1f}s"
        print(f"{serial:16s} {rate:>13s} {tag:>5s} {age_text:>8s}")

    print("-" * 47)
    if valid:
        print(f"Measured ({valid}/{len(serials)}): {fleet:8.2f} MH/s")
        if valid > 1:
            print(f"Fleet:                   {fleet / 1000:8.3f} GH/s")
    else:
        print("Waiting for two fresh samples under one job tag...")


def main():
    args = parse_args()
    if not args.root.is_dir():
        raise SystemExit(f"status root does not exist: {args.root}")

    serials = sorted(set(args.serial or discover_serials(args.root)))
    if not serials:
        raise SystemExit("no FK33 serial directories found")

    state = {serial: new_sample() for serial in serials}
    while True:
        monotonic_now = time.monotonic()
        wall_now = time.time()
        for serial in serials:
            update_sample(
                args.root / serial / "vio_status.txt",
                state[serial],
                monotonic_now,
                wall_now,
            )

        render(args.root, serials, state, args.stale_seconds)
        if args.once:
            return
        time.sleep(0.25)


if __name__ == "__main__":
    main()
