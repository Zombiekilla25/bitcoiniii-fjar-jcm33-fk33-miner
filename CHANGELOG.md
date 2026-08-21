# Changelog

## 0.2.0-beta — 2026-08-21

- Replaced the continuous Vivado/VIO runtime with a standalone framed BSCAN
  transport over the SQRL raw-JTAG TCP bridge.
- Added full host-to-FPGA job frames and FPGA-to-host share frames with
  CRC-16/CCITT-FALSE validation and stream resynchronization.
- Added a timing-clean, fully routed, uncompressed 350 MHz standalone image.
- Physically validated a 117-byte job frame and 45-byte share frame.
- Validated matching FPGA/Python digests and accepted FJAR pool shares without
  Vivado on the mining host.
- Added writable per-card SQRL run directories and configurable unique TCP
  ports for multi-card hosts.
- Added standalone installer, start, stop, status, verification, and systemd
  tooling.
- Kept the disclosed 1% time-based developer-fee policy.
- Excluded the third-party SQRL executable and ABI compatibility libraries from
  redistribution; operators supply legally obtained copies during install.

## 0.1.0-beta — 2026-08-20

- First Vivado/VIO public beta for FK33 FJARCODE mining.
