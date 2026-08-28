# JCM33 dual-alignment BitcoinIII build — validated 525 MHz

This package applies the exact USER2 ingress correction proven by the test12
activity trace, builds a timing-gated 525 MHz production image, programs both
VU33P devices, and mines BitcoinIII on PythonPool for a bounded canary period.

The test12 trace showed that both FPGAs received all 117 bytes and all 1053
shift clocks.  The TDI-near device received each byte in bits `[7:0]`; the
TDO-near device received the same byte in bits `[8:1]` because the other TAP's
BYPASS bit appears first.  The new transport collects all nine bits and locks
to the low or high byte slice when it sees the first `0x46` (`F`) magic byte.
The same bitstream therefore works in both physical chain positions.

Safety and scope:

- The build is rejected for negative setup or hold slack.
- The bitstream is explicitly uncompressed for the SQRL bridge.
- No 350 MHz restore image or restore action is included.
- No voltage option is passed to the bridge.
- Unrelated USB/FK bridges are allowed when JCM33 ports are free.
- The canary passes only after PythonPool accepts at least one share assigned
  to FPGA A and at least one assigned to FPGA B, with zero hardware/software
  digest mismatches.

## Validation result

The production canary completed on 2026-08-28 with both physical devices
active:

```text
accepted_A=185
accepted_B=211
rejected=0
hardware_software_mismatches=0
```

This validates the 525 MHz dual-alignment build on the tested JCM33 carrier.
It does not automatically qualify different hardware, cooling, voltage, or
clock targets. See [VALIDATION.md](VALIDATION.md) for the promotion boundary.

## Run

```bash
git clone https://github.com/Zombiekilla25/fk33-fjar-miner.git
cd fk33-fjar-miner/research/jcm33_dualalign_btc3_525

sha256sum -c SHA256SUMS
chmod +x run_jcm33_dualalign_btc3_canary.sh

./run_jcm33_dualalign_btc3_canary.sh \
  --wallet 'bc1qYOUR_BITCOINIII_ADDRESS' \
  --minutes 10
```

Vivado is auto-detected at the operator's established 2026.1 location.  Use
`--vivado /absolute/path/to/vivado` only if it moved.  The first run performs
the full build; later runs reuse the package-local output unless `--rebuild`
is supplied.

Send back the final `CANARY RESULT` block and, on failure, the evidence archive
path printed by the runner.
