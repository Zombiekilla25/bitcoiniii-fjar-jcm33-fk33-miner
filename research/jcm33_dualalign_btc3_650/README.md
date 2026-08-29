# JCM33 dual-alignment BitcoinIII build — validated 650 MHz

This package is the hardware-qualified JCM33 BitcoinIII production build. It
preserves the independently aligned two-FPGA USER2/USER1 transport and raises
both SHA3-256T II=1 engines to exactly 650 MHz.

The transport captures all nine bits in each per-byte JTAG transaction and
selects the correct eight-bit slice for each physical chain position. Jobs are
sent independently to both VU33P devices and every returned digest is
recomputed in Python before submission.

## Hardware qualification

| Run | Accepted A | Accepted B | Rejected | Digest mismatches |
|---|---:|---:|---:|---:|
| 5-minute canary | 199 | 175 | 0 | 0 |
| 60-minute soak | 1,181 | 1,187 | 0 | 0 |
| **Combined** | **1,380** | **1,362** | **0** | **0** |

The exhaustive six-strategy build selected `Performance_NetDelay_low` and
passed with setup WNS `+0.010 ns` and hold WHS `+0.010 ns`. Maximum reported
FPGA temperature was `30.133 C`; VCCINT remained `0.847–0.850 V`; no voltage
command was issued. No contemporaneous 650 MHz wall-power measurement was
recorded, so this release makes no 650 MHz efficiency claim.

## Included validated prebuilt

The exact image exercised by both recorded runs is published at
[`../../hardware/prebuilt/jcm33_bitcoiniii_dualalign_650_validated.bit`](../../hardware/prebuilt/jcm33_bitcoiniii_dualalign_650_validated.bit).

```text
SHA-256: 0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1
Size: 28329354 bytes
```

Authenticate it from the repository root:

```bash
sha256sum -c research/jcm33_dualalign_btc3_650/PREBUILT_SHA256.txt
```

The qualification runner also includes the exact 587.5 MHz rollback image at
`qualified_587p5/jcm33_dualalign_bscan_587p5.bit` with SHA-256
`2abff6fc716bdea86d7c88865e07dcd380a89564f9267654910b5931a3f2f85b`. Neither qualification run needed rollback.

## Developer fee

The published host miner uses the repository's transparent 1.00% time-based
BitcoinIII developer fee. Developer pool workers end in `-DEVFEE`. Hardware
qualification used fee rotation disabled; this host-side policy does not alter
the bitstream, JTAG transport, FPGA work, digest verification, clocking, or
timing evidence.

## Run

```bash
git clone https://github.com/Zombiekilla25/bitcoiniii-fjar-jcm33-fk33-miner.git
cd bitcoiniii-fjar-jcm33-fk33-miner/research/jcm33_dualalign_btc3_650

sha256sum -c SHA256SUMS
chmod +x run_jcm33_dualalign_btc3_650_canary.sh

./run_jcm33_dualalign_btc3_650_canary.sh \
  --wallet 'bc1qYOUR_BITCOINIII_ADDRESS' \
  --minutes 5
```

The runner is checksum-pinned, requires both devices, rejects digest mismatch,
never changes voltage, and restores the qualified 587.5 MHz image after a
canary pass, failure, or interruption. See `VALIDATION.md` before use.
