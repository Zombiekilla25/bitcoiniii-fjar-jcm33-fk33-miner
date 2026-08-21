# v0.2.0-beta — standalone no-Vivado runtime

This beta replaces the continuous Vivado/VIO mining runtime with a standalone
framed BSCAN transport for the SQRL FK33.

## Highlights

- Prebuilt, timing-clean 350 MHz XCVU33P bitstream
- Direct programming through an operator-supplied SQRL raw-JTAG bridge
- 117-byte CRC-protected job frames and 45-byte share frames
- Hardware/Python digest verification before every submission
- Accepted FJAR pool shares demonstrated on physical hardware
- Per-card writable runtime directories and configurable TCP ports
- Multi-card systemd templates
- Transparent 1% time-based developer fee
- Complete RTL, build flow, tests, and routed reports

Vivado is not required on the mining host. It is only required to rebuild the
bitstream from RTL.

## Important third-party boundary

The archive does not contain `sqrl_bridge_rawjtag_coe`, `libncurses.so.5`, or
`libtinfo.so.5`. Supply legally obtained runtime files to `install.sh`; see
`THIRD_PARTY.md`.

## Verified hardware result

- 350.000 MHz generated hash clock
- WNS `+0.031 ns`, TNS `0.000 ns`
- 642,228 fully routed nets and zero routing errors
- Matching hardware/Python SHA3-256T digests
- Accepted pool shares with no mismatch during the canary

Always verify the release checksum, confirm the exact FK33 serial, review the
developer-fee policy, and protect the SQRL TCP port from untrusted networks.
