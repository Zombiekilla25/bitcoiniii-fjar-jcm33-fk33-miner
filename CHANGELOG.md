# Changelog

## 0.3.0-beta — 2026-08-22

- Added a hardware-validated 500 MHz initiation-interval-one SHA3T engine.
- Added the authenticated uncompressed 500 MHz prebuilt FK33 bitstream.
- Added complete source, simulation, route, timing, utilization, and congestion evidence.
- Added 7.5-second extranonce2 rolling before 32-bit nonce-space exhaustion.
- Preserved hardware/Python digest verification and fail-closed fleet mapping.
- Validated six cards at 2.887 GH/s effective pool hashrate, a 91.95% gain over
  the 1.504 GH/s pre-fix measurement, with zero measured rejected shares.
- Measured 306 W whole-rig AC power, equal to 9.43 MH/s/W at the wall.

## 0.2.1-beta — 2026-08-21

- Replaced per-card SQRL processes with one shared fleet bridge.
- Added consecutive fleet ports and fail-closed serial-to-port validation.
- Added shared bridge and per-card miner systemd units.
- Added fleet start, stop, status, FTDI-release, and readiness helpers.
- Added serial-specific udev-rule generation and optional linger setup.
- Validated five cards, five accepted-share streams, and a real cold service
  restart after host reboot without Vivado.
- Bundled the authorized patched SQRL bridge and documented upstream
  provenance, exact byte changes, checksums, and the maintainer's
  redistribution-permission representation.
- Continued to exclude legacy ncurses/tinfo ABI libraries.

## 0.2.0-beta — 2026-08-21

- Replaced the continuous Vivado/VIO runtime with a standalone framed BSCAN
  transport over the SQRL raw-JTAG TCP bridge.
- Added full host-to-FPGA job frames and FPGA-to-host share frames with
  CRC-16/CCITT-FALSE validation and stream resynchronization.
- Added a timing-clean, fully routed, uncompressed 350 MHz standalone image.
- Physically validated framed transport, matching digests, and accepted shares.
- Added initial standalone installation and service tooling.
- Kept the disclosed 1% time-based developer-fee policy.

## 0.1.0-beta — 2026-08-20

- First Vivado/VIO public beta for FK33 FJARCODE mining.
