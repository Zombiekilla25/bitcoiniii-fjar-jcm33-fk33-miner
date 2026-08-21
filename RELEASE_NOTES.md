# v0.2.1-beta — reboot-safe FK33 fleet runtime

This beta turns the physically validated standalone miner into a persistent
multi-card service.

## Highlights

- One SQRL raw-JTAG process owns the complete FK33 fleet
- Consecutive TCP transports feed independent per-card Python miners
- Serial-to-port validation fails closed if USB scan order changes
- Serial-specific udev rules preserve USB access after reboot
- `ftdi_sio` release and writable SQRL state are handled before launch
- User services can start before login when lingering is enabled
- Bundled, authorized SQRL bridge with exact provenance and patch notes
- Prebuilt timing-clean 350 MHz XCVU33P bitstream
- Hardware/Python digest verification before every submission
- Transparent 1% time-based developer fee

## Physical validation

A five-card FK33 fleet was programmed by one bridge into ports 22000–22004.
All five miners produced matching FPGA/Python digests and accepted pool shares.
After a real host reboot, the bridge loaded all five cards with zero service
restarts and every miner produced a fresh accepted share without Vivado.

Startup is intentionally gated. Ports may appear before all large bitstreams
finish loading; miners wait for every configured load and their exact
serial-to-port mapping.

## Third-party boundary

The patched SQRL executable is bundled under the permission represented in
`third_party/sqrl/REDISTRIBUTION_PERMISSION.md`. Its original and patched
checksums and both byte changes are documented. ABI-5 ncurses/tinfo libraries
remain operator supplied.

Always verify the release checksum, confirm card order and serials, review the
developer-fee policy, and firewall the SQRL port range.
