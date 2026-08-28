# JCM33 dual-alignment BitcoinIII build — validated 550 MHz

This package is the hardware-qualified JCM33 BitcoinIII production build. It
preserves the independently aligned two-FPGA USER2/USER1 transport proven at
525 MHz and raises both SHA3-256T II=1 engines to exactly 550 MHz.

The transport captures all nine bits in each per-byte JTAG transaction and
selects the correct eight-bit slice for each physical chain position. Jobs are
sent independently to both VU33P devices and every returned digest is
recomputed in Python before submission.

## Hardware qualification

| Run | Accepted A | Accepted B | Rejected | Digest mismatches |
|---|---:|---:|---:|---:|
| 15-minute canary | 246 | 232 | 0 | 0 |
| 60-minute soak | 388 | 418 | 0 | 0 |
| **Combined** | **634** | **650** | **0** | **0** |

The routed build passed timing with setup WNS `+0.128 ns` and hold WHS
`+0.010 ns`. Maximum reported FPGA temperature was `28.641 C`. VCCINT stayed
between `0.847 V` and `0.850 V`; no voltage command was issued. The measured
whole system used 114 W at the wall, including its water pump and fans.

The nominal combined engine rate is 1.10 GH/s, corresponding to about
9.65 MH/s/W (103.6 W/GH) for that complete-system measurement. Pool estimates
remain subject to share variance.

The `+0.010 ns` hold margin is valid but narrow. This release does not qualify
any clock above 550 MHz, other JCM33 carriers, cooling failures, or voltage
changes. The validated 525 MHz package remains the fallback.

## Included validated prebuilt

The exact image exercised by both recorded runs is published at
[`../../hardware/prebuilt/jcm33_bitcoiniii_dualalign_550_validated.bit`](../../hardware/prebuilt/jcm33_bitcoiniii_dualalign_550_validated.bit).

```text
SHA-256: 9b75f638459b9c07cc4b36cade5c41d6e45df8f18d9c26020b651f95b52d5e6c
Size: 28329354 bytes
```

Authenticate it from the repository root:

```bash
sha256sum -c research/jcm33_dualalign_btc3_550/PREBUILT_SHA256.txt
```

## Developer fee

The host miner uses a transparent 1.00% time-based BitcoinIII developer fee:
5,940 seconds for the operator and 60 seconds for the developer in each
phase-shifted 6,000-second cycle. Developer pool workers end in `-DEVFEE`.
The hardware qualification runs used fee rotation disabled; enabling this
host-side wallet/worker rotation does not alter the bitstream, JTAG transport,
FPGA job contents, digest verification, clocking, or timing.

## Run

```bash
git clone https://github.com/Zombiekilla25/bitcoiniii-fjar-jcm33-fk33-miner.git
cd bitcoiniii-fjar-jcm33-fk33-miner/research/jcm33_dualalign_btc3_550

sha256sum -c SHA256SUMS
chmod +x run_jcm33_dualalign_btc3_550_canary.sh

./run_jcm33_dualalign_btc3_550_canary.sh \
  --wallet 'bc1qYOUR_BITCOINIII_ADDRESS' \
  --minutes 15
```

The build is rejected for negative setup or hold slack, emits an uncompressed
bitstream for the SQRL bridge, never changes voltage, and contains no 350 MHz
restore path. See [VALIDATION.md](VALIDATION.md) for the production boundary.
