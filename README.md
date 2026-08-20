# FK33 FJAR Miner

Open-source SHA3-256T FPGA mining software for the SQRL Forest Kitten 33
(Xilinx/AMD Virtex UltraScale+ XCVU33P). This beta contains the complete RTL,
Vivado build flow, a timing-clean 350 MHz bitstream, a VIO hardware worker, a
Stratum v1 bridge for FJARCODE, monitoring tools, tests, and user-level systemd
services.

## Release status

`v0.1.0-beta` is a hardware-tested public beta, not a guaranteed-profit product.

- Target: SQRL FK33 / `xcvu33p-fsvh2104-2-e`
- Hash clock: 350 MHz
- Architecture: 80 pipes, three active TOKEN3 contexts per nonce stride
- Routed timing: WNS `+0.024 ns`, WHS `+0.006 ns`
- Routing: 641,542/641,542 routable nets completed, zero routing errors
- Short validation run: 405.12 M nonce-space/s, approximately 379.80 MH/s of
  effective work after the `240/256` architecture factor
- Captured pool validation: 65 accepted shares and zero rejects before the
  service handoff; accepted shares resumed after the systemd restart

Pool hashrate estimates require time to settle and are the preferred long-window
performance measurement. Results vary with board revision, cooling, power,
Vivado/hw_server latency, network latency, and pool difficulty.

## Important safety notice

Programming an FPGA replaces its active configuration. Verify the exact USB/JTAG
serial before starting. Stop any other Vivado worker controlling the same card.
The supplied bitstream is only for the FK33 XCVU33P target. Use is at your own
risk; see [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

## Developer fee

This miner contains a visible 1% time-based developer fee:

- 5,940 seconds mining to the operator wallet
- 60 seconds mining to the developer wallet
- one 100-minute cycle, phase-distributed per card
- explicit `[USER]`, `[DEVFEE]`, and wallet-rotation log entries

The developer wallet is:

```text
fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l
```

Because the default pool mode is solo mining, a block found during the developer
window belongs entirely to the developer wallet. Over a long period, the
expected allocation is 1%. Read [docs/DEV_FEE.md](docs/DEV_FEE.md) before use.

## Requirements

- Ubuntu 24.04 x86-64 was used for validation
- SQRL FK33 with XCVU33P FPGA
- Vivado 2026.1 with hardware-manager support and a valid license
- Python 3.10 or newer; no third-party Python packages
- `systemd --user`, `flock`, and standard GNU userland tools
- A lowercase FJARCODE payout address; never provide a private key or passphrase

Other versions may work but are not part of this beta's tested configuration.

## Verify the release

From the extracted release directory:

```bash
./verify-release.sh
```

The verifier checks the manifest, Python syntax and tests, shell syntax, Tcl
completeness, systemd-unit syntax when supported, the embedded developer wallet,
and the absence of known private machine identifiers.

## Find an FK33 serial

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

Installation alone does not program hardware unless `--start` is supplied.

```bash
./install.sh \
  --wallet 'fjarcode:YOUR_LOWERCASE_ADDRESS' \
  --serial 'YOUR_FK_SERIAL'
```

Review the generated configuration:

```bash
sed -n '1,120p' "$HOME/.config/fk33-fjar-miner/miner.env"
```

Then start the selected card:

```bash
systemctl --user enable --now \
  fjar-fk33-worker@YOUR_FK_SERIAL.service

systemctl --user enable --now \
  fjar-fk33-bridge@YOUR_FK_SERIAL.service
```

Alternatively, add `--start` to the installer after reviewing the fee policy and
confirming the serial.

## Monitor

```bash
systemctl --user --no-pager --full status \
  fjar-fk33-worker@YOUR_FK_SERIAL.service \
  fjar-fk33-bridge@YOUR_FK_SERIAL.service

tail -f "$HOME/.local/state/fk33-fjar-miner/YOUR_FK_SERIAL/bridge.log"

python3 "$HOME/.local/share/fk33-fjar-miner/current/runtime/fleet_status.py"
```

Accepted share lines include either `[ACCEPTED][USER]` or
`[ACCEPTED][DEVFEE]`. Persistent rejects or FPGA/Python digest mismatches require
investigation; stop the card rather than continuing blindly.

## Stop one card

```bash
./disable-card.sh YOUR_FK_SERIAL
```

The command retains configuration, logs, and release files.

## Build from RTL

See [docs/BUILD.md](docs/BUILD.md). The internal project/output filenames retain
their original `bc3_...` names to preserve the exact hardware-tested build flow;
SHA3-256T header and hashing behavior are shared by the supported FJAR path.

## Contents

- `hardware/source/` — SystemVerilog, constraints, simulation, and Vivado flow
- `hardware/prebuilt/` — tested bitstream and VIO probes
- `hardware/reports/` — routed timing, utilization, and route evidence
- `runtime/fjar_bridge.py` — Stratum bridge and transparent fee scheduler
- `runtime/vio_worker_fjar_fk33.tcl` — exact-serial programmer and mailbox worker
- `runtime/fleet_status.py` — dynamic single/fleet status monitor
- `systemd/` — user service templates and configuration example
- `tests/` — offline scheduler and submission-routing tests
- `docs/` — build, fee, service, and security details

## Wallet and pool boundaries

The miner only needs a public payout address. It does not need wallet files,
seed phrases, private keys, RPC passwords, or wallet passphrases. The default
pool profile is PythonPool's FJAR Stratum v1 endpoint. Pool availability, rules,
fees, and coin economics can change; verify them independently before mining.
