# v0.4.0-beta — 525 MHz FK33 fleet release

This release advances the standalone six-card FK33 fleet from 500 MHz to a
timing-clean 525 MHz image. It retains the authenticated 500 MHz image for
rollback and keeps the one-bridge, per-card miner service architecture.

## Verified fleet result

| Metric | Result |
|---|---:|
| Six-card effective pool hashrate | **3.172 GH/s** |
| Measured 500 MHz baseline | **2.887 GH/s** |
| Improvement over baseline | **+9.87%** |
| Average per FK33 | **528.67 MH/s** |
| Clock-derived six-card design rate | **3.150 GH/s** |
| Short-window clock efficiency | **100.70%** |
| Submitted / accepted shares | **680 / 680** |
| Rejects / duplicates / runtime faults | **0 / 0 / 0** |
| Measurement window | **660 seconds** |

The result was derived from the exact target attached to each submitted share.
The 100.70% figure is ordinary short-window share variance and should not be
interpreted as operation beyond the 525 MHz design rate.

## Hardware

- SQRL FK33 XCVU33P target
- Initiation-interval-one SHA3-256T engine at 525 MHz
- Routed WNS `+0.056 ns`, TNS `0.000 ns`, WHS `+0.010 ns`
- Fully routed design with zero routing errors
- Authenticated uncompressed 525 MHz image:
  `64e0a7d21a10b4aa04b340c826af7d75363b5d5ba5e39330fe28c42ff103821c`
- Authenticated 500 MHz rollback image retained
- Complete source and Vivado 2026.1 build evidence included

## Runtime and fleet safety

The packaged runtime is the version physically exercised during the 525 MHz
fleet validation. Submission accounting requires the exact difficulty attached
to the dispatched job. The systemd readiness helper validates that the expected
serial is mapped to the expected TCP port and that fleet programming completed
before the corresponding Python miner starts.

Fresh `extranonce2` work remains dispatched every 7.5 seconds, before a
525 MH/s engine exhausts its 32-bit nonce range. Hardware/Python digest checks,
target checks, duplicate suppression, and the disclosed developer-fee policy
remain active.

## Power disclosure

No contemporaneous whole-rig power measurement was available for the 525 MHz
sample. The earlier 306 W measurement belongs to the 500 MHz validation and
must not be used as a measured 525 MHz efficiency result.

This remains experimental mining hardware software. Verify checksums, cooling,
card order, firewalling, and the developer-fee policy before use. No voltage
change is performed by this release.
