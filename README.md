# FK33 FJAR Miner

Standalone SHA3-256T FPGA mining software for the SQRL Forest Kitten 33
(Xilinx/AMD Virtex UltraScale+ XCVU33P). The mining host uses a prebuilt
bitstream, one SQRL raw-JTAG fleet bridge, and one Python miner per card.
Vivado is not required at runtime.

## Release status

`v0.2.1-beta` is a hardware-tested fleet beta.

- Target: SQRL FK33 / `xcvu33p-fsvh2104-2-e`
- Hash clock: 350 MHz
- Architecture: 80 pipes with three active TOKEN3 contexts
- Routed timing: WNS `+0.031 ns`, TNS `0.000 ns`
- Routing: 642,228 fully routed nets, zero routing errors
- Protocol: 117-byte job frame in, 45-byte share frame out
- Physical fleet validation: five FK33s, five TCP transports, five miners
- Reboot validation: automatic programming and fresh accepted shares on all
  five cards without Vivado

This is experimental hardware software, not a guaranteed-profit product.

## What changed in v0.2.1

The old beta tried to run a separate SQRL process for every card. The SQRL
bridge owns and scans the complete FTDI fleet, so that design caused collisions.
This release runs exactly one bridge process and maps consecutive TCP ports to
independent Python miners. Serial-to-port mapping is checked before a miner may
connect.

The authorized patched SQRL executable is now bundled. Its provenance,
checksums, two byte-level modifications, and permission record are in
[third_party/sqrl](third_party/sqrl).

## Safety

Programming an FPGA replaces its active configuration. Stop every other Vivado,
hardware-server, USB/IP, or SQRL process that can control these cards. The
supplied image is only for an FK33 XCVU33P. Sustained 350 MHz operation requires
suitable power and cooling.

The SQRL bridge listens on all interfaces. Firewall the configured port range
or use an isolated mining network.

## Developer fee

The Python bridge contains a visible 1% time-based developer fee: 5,940 seconds
for the operator followed by 60 seconds for the developer in each phase-shifted
6,000-second cycle. Logs label activity as `[USER]` or `[DEVFEE]`.

Developer wallet:

```text
fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l
```

On a solo pool, a block found during the developer window belongs entirely to
the developer wallet. Read [docs/DEV_FEE.md](docs/DEV_FEE.md).

## Runtime requirements

- Linux x86-64; Ubuntu 24.04 was physically validated
- one or more SQRL FK33 XCVU33P cards
- Python 3.10 or newer
- user systemd, `sudo`, `ss`, `flock`, and standard GNU tools
- a lowercase public FJARCODE payout address
- authorized ABI-5 `libncurses` and `libtinfo` files if the host lacks them
- serial-specific USB access and permission to release `ftdi_sio`
- firewall protection for the SQRL TCP port range

The SQRL bridge is bundled under the permission described in
[THIRD_PARTY.md](THIRD_PARTY.md). Legacy ncurses/tinfo libraries are not
bundled.

## Verify

```bash
./verify-release.sh
```

## Find card serials

```bash
for SERIAL_FILE in /sys/bus/usb/devices/*/serial; do
    [ -r "$SERIAL_FILE" ] || continue
    USB_DEV=${SERIAL_FILE%/serial}
    [ "$(cat "$USB_DEV/idVendor" 2>/dev/null)" = 0403 ] || continue
    [ "$(cat "$USB_DEV/idProduct" 2>/dev/null)" = 6010 ] || continue
    printf '%s\n' "$(cat "$SERIAL_FILE")"
done
```

## Install a fleet

List cards in the bridge's physical scan order and assign consecutive ports.
Installation does not program hardware unless `--start` is supplied.

```bash
./install.sh \
  --wallet 'fjarcode:YOUR_LOWERCASE_ADDRESS' \
  --card 'FIRST_SERIAL:22000' \
  --card 'SECOND_SERIAL:22001' \
  --compat-libs '/path/to/authorized/compat_libs' \
  --install-udev \
  --enable-linger
```

`--install-udev` and `--enable-linger` use noninteractive sudo and fail
rather than prompt. Configure sudo access deliberately before using those
options. Review the generated files under
`~/.config/fk33-fjar-miner/`, then start:

```bash
./start-fleet.sh
```

If USB scan order changes, the per-card readiness check refuses a mismatched
serial-to-port mapping. Re-run the installer with the observed order; do not
bypass the check.

## Monitor and stop

```bash
./status-fleet.sh
./status-card.sh YOUR_SERIAL
./disable-card.sh YOUR_SERIAL
./disable-fleet.sh
```

Persistent `MISMATCH`, comparator-disagreement, or rejected-share messages are
a stop condition.

## Build from RTL

Developers can rebuild the image with Vivado 2026.1. End users do not perform
this step. See [docs/BUILD.md](docs/BUILD.md).

## Contents

- `hardware/source/` — SystemVerilog, constraints, probe, and build flow
- `hardware/prebuilt/` — tested standalone mining bitstream
- `hardware/reports/` — route, timing, and utilization evidence
- `runtime/` — fleet orchestration, framed transport, Stratum, and validation
- `systemd/` — shared bridge and per-card miner units
- `third_party/sqrl/` — authorized bridge, provenance, and exact patch record
- `tests/` — offline protocol and scheduling tests
- `docs/` — build, fee, service, and validation documentation

The miner requires only a public payout address. Never provide a private key,
seed phrase, wallet backup, passphrase, exchange password, or RPC credential.
