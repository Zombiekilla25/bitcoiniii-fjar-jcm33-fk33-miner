# FK33 FJAR Miner

> Experimental BitcoinIII support includes a deliberately one-card-only BTC3
> canary and a gated fleet launcher for use after the canary produces matching
> hardware/software hashes and an accepted share. See
> [docs/BTC3_CANARY.md](docs/BTC3_CANARY.md).

Standalone SHA3-256T FPGA mining software for the SQRL Forest Kitten 33
(Xilinx/AMD Virtex UltraScale+ XCVU33P). One SQRL raw-JTAG fleet bridge owns
the cards and one Python miner handles each independent TCP transport. Vivado
is not required on the runtime host.

## v0.4.0-beta: verified 525 MHz fleet release

The hardware-tested `v0.4.0-beta` release raises the standalone FK33 fleet
clock from 500 MHz to 525 MHz while retaining the authenticated 500 MHz image
as a rollback artifact. The deployed fresh-work runtime and service-level
serial-to-port validation remain part of the release.

| Verified metric | Result |
|---|---:|
| Six-card effective pool hashrate | **3.172 GH/s** |
| Gain over the measured 2.887 GH/s 500 MHz baseline | **+9.87%** |
| Average per FK33 | **528.67 MH/s** |
| Share-derived rate vs. 3.150 GH/s design rate | **100.70%** |
| Submitted / accepted shares in the sample | **680 / 680** |
| Rejected shares, duplicates, and runtime faults | **0 / 0 / 0** |

The 100.70% short-window result reflects normal share variance; it is not a
claim that the hardware exceeds its clock-derived design rate. The measurement
covered 660 seconds with all six cards continuously active. A contemporaneous
525 MHz whole-rig power measurement was not available, so this release makes
no 525 MHz efficiency claim. See
[docs/PERFORMANCE.md](docs/PERFORMANCE.md).

## Hardware evidence

- Target: SQRL FK33 / `xcvu33p-fsvh2104-2-e`
- Hash clock: 525 MHz
- Architecture: initiation interval one; one nonce tested per clock
- Routed timing: WNS `+0.056 ns`, TNS `0.000 ns`, WHS `+0.010 ns`
- Routing: fully routed with zero routing errors
- Protocol: 117-byte job frame in, 45-byte share frame out
- Physical validation: six FK33s, six transports, six accepted-share streams
- Default image: authenticated uncompressed 525 MHz bitstream
- Rollback image: authenticated uncompressed 500 MHz bitstream
- Legacy SQRL-loader compatibility: bitstream compression disabled

## Why fresh-work rolling matters

A 525 MH/s engine scans all `2^32` nonce values in about 8.18 seconds. If a
pool job lasts longer, restarting the same nonce range produces duplicate work.
This runtime rolls `extranonce2` every 7.5 seconds, rebuilding the coinbase,
Merkle root, header, and tag before exhaustion. Every candidate is still
recomputed in Python and checked against the target before submission.

## Safety

Programming replaces the FPGA's active configuration. Stop every other Vivado,
hardware-server, USB/IP, or SQRL process that can control the cards. The image
is only for an FK33 XCVU33P. Sustained 525 MHz operation requires adequate
power and cooling. No voltage change is performed by this software.

The SQRL bridge listens on all interfaces. Firewall its port range or use an
isolated mining network. This is experimental hardware software, not a
profitability guarantee.

## Developer fee

The Python bridge contains a visible 1% time-based developer fee: 5,940 seconds
for the operator followed by 60 seconds for the developer in each phase-shifted
6,000-second cycle. Logs label activity as `[USER]` or `[DEVFEE]`.

Developer wallet:

```text
fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l
```

Read [docs/DEV_FEE.md](docs/DEV_FEE.md).

## Runtime requirements

- Linux x86-64; Ubuntu 24.04 was physically validated
- one or more SQRL FK33 XCVU33P cards
- Python 3.10 or newer
- user systemd, `sudo`, `ss`, `flock`, and standard GNU tools
- a lowercase public FJARCODE payout address
- authorized ABI-5 `libncurses` and `libtinfo` files if the host lacks them
- serial-specific USB access and permission to release `ftdi_sio`
- firewall protection for the SQRL TCP port range

The authorized SQRL bridge is bundled as documented in
[THIRD_PARTY.md](THIRD_PARTY.md). Legacy ncurses/tinfo libraries are not
bundled.

## Verify

```bash
./verify-release.sh
```

## Portable quick start

The top-level launcher detects FK33 USB/JTAG serials, assigns consecutive
ports, starts one shared SQRL bridge plus one miner per card, and keeps logs
under `~/.local/state/fk33-fjar/`. It uses the six-card validated 525 MHz image
by default and does not change voltage.

```bash
chmod +x start.sh
./start.sh doctor
sudo -v                 # only needed when ftdi_sio must be released
./start.sh --wallet 'fjarcode:YOUR_LOWERCASE_ADDRESS'
```

Use `./start.sh status`, `./start.sh logs`, and `./start.sh stop` for lifecycle
control. Systems lacking ABI-5 ncurses/tinfo libraries must point
`FK33_LIB_DIR` at an authorized compatibility-library directory.
The launcher validates each selected serial as an FTDI `0403:6010` device and
will release only those selected interfaces from `ftdi_sio`.

The included 550 MHz image is a checksum-pinned but otherwise unqualified
experimental candidate, not a timing-signed or hardware-validated release
image. It is never selected by default and requires explicit acknowledgement:

```bash
./start.sh doctor --experimental-550
./start.sh --wallet 'fjarcode:YOUR_LOWERCASE_ADDRESS' --experimental-550
```

Read [docs/EXPERIMENTAL_550.md](docs/EXPERIMENTAL_550.md) before selecting it.

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

List cards in physical bridge scan order and assign consecutive ports:

```bash
./install.sh \
  --wallet 'fjarcode:YOUR_LOWERCASE_ADDRESS' \
  --card 'FIRST_SERIAL:22000' \
  --card 'SECOND_SERIAL:22001' \
  --compat-libs '/path/to/authorized/compat_libs' \
  --install-udev \
  --enable-linger
```

Review `~/.config/fk33-fjar-miner/`, then start:

```bash
./start-fleet.sh
```

If USB scan order changes, serial-to-port validation fails closed. Re-run the
installer with the observed order; do not bypass the check.

## Monitor and stop

```bash
./status-fleet.sh
./status-card.sh YOUR_SERIAL
./disable-card.sh YOUR_SERIAL
./disable-fleet.sh
```

Persistent mismatch, comparator-disagreement, digest-mismatch, or rejected
share messages are a stop condition.

## Build from RTL

The complete 525 MHz source and gated Vivado 2026.1 build flow are under
`hardware/source/ii1_525/`. See [docs/BUILD.md](docs/BUILD.md).

The miner requires only a public payout address. Never provide a private key,
seed phrase, wallet backup, passphrase, exchange password, or RPC credential.
