# FK33 FJAR Miner

Standalone SHA3-256T FPGA mining software for the SQRL Forest Kitten 33
(Xilinx/AMD Virtex UltraScale+ XCVU33P). One SQRL raw-JTAG fleet bridge owns
the cards and one Python miner handles each independent TCP transport. Vivado
is not required on the runtime host.

## v0.3.0-beta: nearly 3 GH/s from six FK33s

The hardware-tested `v0.3.0-beta` release moves the standalone fleet to a
timing-clean 500 MHz initiation-interval-one SHA3T engine and prevents nonce
space exhaustion with automatic 7.5-second `extranonce2` rolling.

| Verified metric | Result |
|---|---:|
| Six-card effective pool hashrate | **2.887 GH/s** |
| Gain over the pre-fix 1.504 GH/s sample | **+91.95%** |
| Average per FK33 | **481.17 MH/s** |
| Share-derived rate vs. 3.000 GH/s design rate | **96.23%** |
| Rejected shares in the measured validation | **0** |
| Whole-rig AC power | **306 W** |
| Whole-rig efficiency at the wall | **9.43 MH/s/W** |

The 306 W measurement includes the complete Octominer host, six cards, chassis
fans, PSU losses, and other PSU load. It is not FPGA-only board power. See
[docs/PERFORMANCE.md](docs/PERFORMANCE.md) for the test details and caveats.

## Hardware evidence

- Target: SQRL FK33 / `xcvu33p-fsvh2104-2-e`
- Hash clock: 500 MHz
- Architecture: one accepted nonce per clock after pipeline fill
- Routed timing: WNS `+0.336 ns`, TNS `0.000 ns`, WHS `+0.010 ns`
- Routing: 360,460 fully routed nets, zero routing errors
- Utilization: 146,822 LUTs (33.39%), 359,255 registers (40.85%)
- Protocol: 117-byte job frame in, 45-byte share frame out
- Physical validation: six FK33s, six transports, six accepted-share streams
- Prebuilt image: uncompressed for legacy SQRL-loader compatibility

## Why fresh-work rolling matters

A 500 MH/s engine scans all `2^32` nonce values in about 8.59 seconds. If a
pool job lasts longer, restarting the same nonce range produces duplicate work.
This runtime rolls `extranonce2` every 7.5 seconds, rebuilding the coinbase,
Merkle root, header, and tag before exhaustion. Every candidate is still
recomputed in Python and checked against the target before submission.

## Safety

Programming replaces the FPGA's active configuration. Stop every other Vivado,
hardware-server, USB/IP, or SQRL process that can control the cards. The image
is only for an FK33 XCVU33P. Sustained 500 MHz operation requires adequate
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

The complete 500 MHz source and gated Vivado 2026.1 build flow are under
`hardware/source/ii1_500/`. See [docs/BUILD.md](docs/BUILD.md).

The miner requires only a public payout address. Never provide a private key,
seed phrase, wallet backup, passphrase, exchange password, or RPC credential.
