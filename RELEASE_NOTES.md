# v0.3.0-beta — 500 MHz FK33 fleet release

This release nearly doubles useful pool throughput from the same six-card FK33
fleet while preserving the reboot-safe, one-bridge architecture from v0.2.1.

## Huge verified gain

- **2.887 GH/s** effective pool hashrate across six FK33s
- **+91.95%** versus the measured 1.504 GH/s pre-fix rate
- **481.17 MH/s average per card**
- **96.23% of the 3.000 GH/s design rate**
- **zero rejected shares** in the measured validation
- **306 W whole-rig AC**, equal to **9.43 MH/s/W at the wall**

## Hardware

- New fully pipelined, initiation-interval-one SHA3-256T engine at 500 MHz
- Uncompressed prebuilt FK33 XCVU33P bitstream
- Routed WNS `+0.336 ns`, TNS `0.000 ns`, WHS `+0.010 ns`
- 360,460 fully routed nets and zero routing errors
- Complete source, known-answer simulation, and timing-gated build flow

## Runtime fix

At 500 MH/s, the 32-bit nonce field is exhausted in approximately 8.59
seconds. The runtime now rolls pool `extranonce2` every 7.5 seconds so every
dispatch receives a fresh coinbase, Merkle root, header, tag, and nonce range.
The interval is configurable with `FJAR_WORK_ROLL_SECONDS` from 1.0 to 8.0
seconds.

Rolled shares carry their exact `extranonce2`, job ID, time, difficulty, and
wallet mode through submission accounting. Hardware/Python digest verification,
target checking, duplicate suppression, developer-fee disclosure, and
serial-to-port fail-closed validation remain active.

## Power disclosure

The Octominer PSU reported 306 W AC and 279 W DC while the fleet mined. The AC
figure is complete-rig input power, including host, fans, and PSU losses; it is
not an FPGA-only measurement.

This remains experimental mining hardware software. Verify checksums, cooling,
card order, firewalling, and the developer-fee policy before use.
