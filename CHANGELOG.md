# Changelog

## Unreleased

- Promoted the timing-clean JCM33 dual-FPGA BitcoinIII 650 MHz image after a
  5-minute canary and 60-minute soak totaling A=1,380 and B=1,362 accepted
  shares with zero rejects and zero hardware/software digest mismatches.
- Added the exact uncompressed 650 MHz prebuilt, six-strategy route summary,
  positive `+0.010 ns` setup/hold timing evidence, complete source, XVC runner,
  and the qualified 587.5 MHz rollback image.
- Recorded a maximum observed FPGA temperature of `30.133 C`, stock VCCINT of
  `0.847–0.850 V`, and no voltage command. No 650 MHz power claim is made.

- Added the physically validated JCM33 dual-FPGA BitcoinIII 525 MHz
  bitstream, exact identity, and sanitized 185/211 accepted-share evidence.
- Rebranded the project for BitcoinIII and FJAR across JCM33 and FK33 while
  preserving platform-specific bitstream safety boundaries.
- Repaired release-manifest and verification coverage for the JCM33 research
  package and its separately authorized XVC bridge.
- Added a portable `start.sh` launcher with automatic serial discovery,
  card-count cross-checking, checksum pinning, per-card workers, dry-run,
  status, log, and guarded stop commands.
- Added serial-specific FTDI vendor/product and device-access validation plus
  controlled `ftdi_sio` release for the selected cards.
- Made the hardware-validated 525 MHz image the portable launcher's safe
  default.
- Added the checksum-pinned 550 MHz bitstream as an explicitly selected,
  unqualified experimental candidate. It is not enabled by the installer or
  systemd fleet path and is not described as timing-signed or hardware
  validated.
- Preserved the no-voltage-change policy and required an explicit override for
  any unpinned bitstream.

## 0.4.0-beta — 2026-08-23

- Added the timing-clean, fully routed 525 MHz initiation-interval-one image.
- Added the authenticated uncompressed 525 MHz prebuilt bitstream, complete
  source, and routed timing, utilization, congestion, and route reports.
- Made 525 MHz the default fleet image while retaining the authenticated
  500 MHz image as an included rollback artifact.
- Updated to the physically deployed fresh-work runtime.
- Kept serial-to-port validation fail-closed in the systemd readiness helper.
- Measured six cards at 3.172 GH/s over 660 seconds, a 9.87% gain over the
  measured 2.887 GH/s 500 MHz baseline.
- Recorded 680 submitted and 680 accepted shares with zero rejects,
  duplicates, or runtime faults.
- Made no 525 MHz power or wall-efficiency claim because contemporaneous
  whole-rig power telemetry was unavailable.

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
