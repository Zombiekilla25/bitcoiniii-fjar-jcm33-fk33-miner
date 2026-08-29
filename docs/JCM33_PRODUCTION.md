# JCM33 650 MHz production launcher

`start-jcm33-btc3.sh` is the release-candidate lifecycle supervisor for the
published, hardware-qualified JCM33 dual-FPGA BitcoinIII 650 MHz package. It
does not rebuild or alter the qualified bitstream, transport, miner, clock, or
voltage.

The launcher is intentionally separate from `start-btc3.sh`, which is an FK33
launcher. JCM33 and FK33 use different physical transports and their images
must never be interchanged.

## Pinned production boundary

| Artifact | SHA-256 |
|---|---|
| JCM33 650 MHz bitstream | `0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1` |
| JCM33 587.5 MHz rollback | `2abff6fc716bdea86d7c88865e07dcd380a89564f9267654910b5931a3f2f85b` |
| JCM33 XVC bridge | `fd1a550af5eb5dab475071a8f08f181c0b0d308233cbca805c52e3a96f342141` |
| JCM33 dual miner | `1d64c8e7d2650e3733a26985f271779dbf5b36fea46e5c6ea7e6c605681c3593` |

The supervisor requires both VU33P devices and the published timing-gate
marker. It uses the existing low/high nine-bit chain alignment, independently
dispatches work to A and B, and leaves full digest verification inside the
published Python miner.

## Safety behavior

- No voltage option or voltage command is issued.
- A start fails closed if any existing SQRL bridge targets the configured
  JCM33 carrier.
- Unrelated FK33/USB bridges are not stopped or modified.
- A start fails if carrier ports `2000/2001` or local XVC port `2542` are
  already listening, unless different ports were explicitly configured.
- Both devices must report that the 650 MHz image loaded before mining starts.
- The supervisor keeps both the XVC bridge and dual miner under PID-specific
  control; it never uses a broad `pkill` or `killall` operation.
- A hardware/software `SHARE mismatch`, miner exit, bridge exit, controlled
  stop, or interrupted foreground run stops the children and programs the
  checksum-pinned qualified 587.5 MHz rollback image on both devices.
- If rollback cannot be confirmed, the launcher fails closed and records
  `rollback_587p5=FAIL`; do not resume mining until both images are verified.

A sudden host power loss cannot execute software rollback. On the next start,
the launcher always rechecks every artifact and explicitly programs the 650
MHz image before starting the miner.

The launcher does not yet enforce a numeric temperature threshold. The
qualified boundary requires working water cooling. Stop immediately if pump,
coolant flow, temperature, or power delivery becomes abnormal.

## Configure

```bash
cp config-jcm33-btc3.env.example config-jcm33-btc3.env
chmod 600 config-jcm33-btc3.env
```

Edit `BTC3_WALLET` to the operator's lowercase BitcoinIII `bc1q` address. The
default network settings match the qualified carrier and pool:

```text
carrier: 192.168.1.222
ports:   2000/2001
XVC:     127.0.0.1:2542
pool:    stratum.pythonpool.dev:3357
```

If the host lacks ABI-5 ncurses/tinfo libraries, set `JCM33_LIB_DIR` to the
operator-provided compatibility directory. Those legacy libraries are not
distributed by this repository.

## Preflight and start

First perform a local-only check. This hashes the exact assets, validates the
configuration, checks bridge dependencies, and runs the miner self-test. It
does not contact the carrier or pool and never programs hardware:

```bash
./start-jcm33-btc3.sh doctor --dry-run
```

Then run the full read-only doctor. It checks carrier and pool reachability,
process conflicts, and port availability, but still does not program an FPGA:

```bash
./start-jcm33-btc3.sh doctor
```

Start the background production supervisor:

```bash
./start-jcm33-btc3.sh start
```

Startup does not return `START PASS` until both devices load, the XVC endpoint
is listening, and the dual miner connects to the two-device XVC chain.

## Operate and stop

```bash
./start-jcm33-btc3.sh status
./start-jcm33-btc3.sh logs --lines 160
./start-jcm33-btc3.sh logs --follow
./start-jcm33-btc3.sh stop
```

`status` reports the supervisor, bridge, and miner PIDs; XVC state; accepted A
and B shares; rejected shares; digest mismatches; and developer-fee log events.
Logs and prior-run evidence live under `~/.local/state/jcm33-btc3/` by default.

`stop` is deliberately not instantaneous: it stops mining and waits up to the
configured safe-stop timeout for both FPGAs to load the qualified 587.5 MHz
rollback. It will not force-kill a supervisor while rollback may be active.

`run` provides the same supervisor in the foreground for a future systemd
unit. Systemd promotion should happen only after this release candidate passes
a fresh-clone canary, controlled stop/rollback drill, six-hour burn-in, and
24-hour unattended soak.

## Developer fee visibility

The unchanged published miner retains the transparent BitcoinIII 1% time-based
developer rotation. Operator work uses the configured worker name. Developer
sessions use the same base with the visible `-DEVFEE` suffix and the published
network-specific developer wallet. See [DEV_FEE.md](DEV_FEE.md).
