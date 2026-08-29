# v0.5.0-beta — native FK33 650 MHz one-card qualification

This release publishes the exact native eight-bit FK33 650 MHz SHA3-256T image
with SHA-256
`bd494ba2ea697a5e916b51caf4bdab8e5c620cd121bfd4b2e9a806deb5596c39`.
It is distinct from the JCM33 dual-device 650 MHz image.

The selected route is timing-clean with setup WNS `+0.002 ns` and hold WHS
`+0.007 ns`. A 60-minute BitcoinIII soak on one physical FK33 produced 740
hardware share frames, suppressed 65 byte-identical duplicate candidates, and
submitted 675 shares. All 675 were accepted. There were zero rejected shares,
hardware/software digest mismatches, or protocol errors.

The card began at `27.646 C` and reported `41.076 C` during the post-soak
rollback load. Observed VCCINT was `0.809 V` initially and `0.803 V` after the
soak. No voltage command was used. The exact qualified 525 MHz image was
restored successfully.

The 650 MHz image is one-card qualified, not yet multi-card fleet-qualified.
For that reason 525 MHz remains the default. Portable launchers require
`--qualified-650`; installed systemd fleets require the explicit
`FJAR_FLEET_BITSTREAM=650` setting. Both paths authenticate the image before
programming. Set the systemd selection back to `525` for rollback.

No 650 MHz fleet hashrate or wall-power measurement is claimed.

---

# JCM33 650 MHz hardware-qualified update — 2026-08-29

The JCM33 production image is now the dual-alignment 650 MHz BitcoinIII build.
The exact `0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1` image passed a 5-minute canary and a 60-minute soak with
2,742 accepted shares, zero rejects, and zero hardware/software digest
mismatches. Final routed setup WNS and hold WHS are both `+0.010 ns`; maximum
reported temperature was `30.133 C`; no voltage command was used.

This update does not promote the JCM33 image to FK33. The platforms retain
different physical JTAG transports. The validated 550 MHz and 525 MHz JCM33
images remain fallbacks, and the qualification runner carries the exact 587.5
MHz rollback image. No contemporaneous 650 MHz wall-power measurement was
recorded, so no new efficiency claim is made.

---

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
