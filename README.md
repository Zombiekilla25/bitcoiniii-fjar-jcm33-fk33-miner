# FK33 FJAR Miner

Standalone SHA3-256T FPGA mining software for the SQRL Forest Kitten 33
(Xilinx/AMD Virtex UltraScale+ XCVU33P). End users run a prebuilt bitstream,
the SQRL raw-JTAG transport, and Python 3. Vivado is not required on the mining
host.

## Release status

`v0.2.0-beta` is a hardware-tested public beta.

- Target: SQRL FK33 / `xcvu33p-fsvh2104-2-e`
- Hash clock: 350 MHz
- Architecture: 80 pipes with three active TOKEN3 contexts
- Routed timing: WNS `+0.031 ns`, TNS `0.000 ns`
- Routing: 642,228 fully routed nets, zero routing errors
- Utilization: 262,934 CLB LUTs (59.80%), 529,955 registers (60.27%)
- Physical protocol test: 117-byte job frame in, 45-byte share frame out
- Pool validation: matching FPGA/Python SHA3-256T digests and accepted FJAR
  shares through the standalone transport

This is experimental hardware software, not a guaranteed-profit product.

## What changed from v0.1

The v0.1 runtime used Vivado hardware manager and VIO continuously. This
release replaces that runtime with a framed BSCAN transport. Vivado is now
needed only by developers rebuilding the bitstream from RTL.

## Safety

Programming an FPGA replaces its active configuration. Confirm the exact USB
serial and stop any other process controlling that card. The supplied image is
only for an FK33 XCVU33P. Sustained 350 MHz operation requires suitable power
and cooling. Use is at your own risk.

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

- Ubuntu 24.04 x86-64 was used for validation
- SQRL FK33 with XCVU33P FPGA
- Python 3.10 or newer
- `systemd --user`, `flock`, `ss`, and standard GNU tools
- a lowercase public FJARCODE payout address
- a legally obtained `sqrl_bridge_rawjtag_coe` executable
- any compatibility libraries required by that executable
- firewall protection for its hardware TCP port on untrusted networks

The SQRL executable and legacy ABI libraries are **not distributed in this
repository**. See [THIRD_PARTY.md](THIRD_PARTY.md).

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

## Install one card

Installation does not touch hardware unless `--start` is included.

```bash
./install.sh \
  --wallet 'fjarcode:YOUR_LOWERCASE_ADDRESS' \
  --serial 'YOUR_FK_SERIAL' \
  --sqrl-bridge '/path/to/sqrl_bridge_rawjtag_coe' \
  --compat-libs '/path/to/compat_libs' \
  --hw-port 22000
```

Review the generated files:

```bash
sed -n '1,120p' "$HOME/.config/fk33-fjar-miner/miner.env"
sed -n '1,120p' "$HOME/.config/fk33-fjar-miner/cards/YOUR_FK_SERIAL.env"
```

Then start:

```bash
./start-card.sh YOUR_FK_SERIAL
```

For another card on the same host, run the installer again with a different
serial and unused `--hw-port`, such as 22001.

## Monitor and stop

```bash
./status-card.sh YOUR_FK_SERIAL
./disable-card.sh YOUR_FK_SERIAL
```

Persistent `MISMATCH`, comparator-disagreement, or rejected-share messages are
a stop condition.

## Build from RTL

Developers can rebuild the prebuilt image with Vivado 2026.1. End users do not
perform this step. See [docs/BUILD.md](docs/BUILD.md).

## Contents

- `hardware/source/` — SystemVerilog, constraints, probe, and build flow
- `hardware/prebuilt/` — tested standalone mining bitstream
- `hardware/reports/` — route, timing, and utilization evidence
- `runtime/fjar_bridge.py` — framed transport, Stratum, validation, and fee
- `systemd/` — per-card standalone service templates
- `tests/` — offline protocol and scheduling tests
- `docs/` — build, fee, systemd, and validation documentation

The miner requires only a public payout address. Never provide a private key,
seed phrase, wallet backup, passphrase, exchange password, or RPC credential.
