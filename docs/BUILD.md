# Developer bitstream build

End users use `hardware/prebuilt/fk33_fjar_bscan_350.bit` and do not need
Vivado.

The validated developer toolchain was Vivado 2026.1 on Ubuntu 24.04 x86-64,
targeting `xcvu33p-fsvh2104-2-e`.

## Offline tests

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

## Protocol probe

```bash
cd hardware/source
./run_probe_build.sh
```

Require the physical probe to report a complete 117-byte input frame and a
correct 45-byte output frame before building the miner.

## Full image

```bash
cd hardware/source
./run_build.sh
```

Expected output:

```text
FK33 FJAR BSCAN BUILD COMPLETE
```

The generated file is `fk33_fjar_bscan_350.bit`. Require zero route errors and
positive setup timing before copying it into `hardware/prebuilt/` and
regenerating `SHA256SUMS`.

## Validated routed result

- Hash clock: 350.000 MHz
- WNS: `+0.031 ns`
- TNS: `0.000 ns`
- Timing-failing endpoints: 0
- Fully routed nets: 642,228
- Routing errors: 0
- CLB LUTs: 262,934 / 439,680 (59.80%)
- CLB registers: 529,955 / 879,360 (60.27%)
- Bitstream compression: disabled for legacy SQRL-loader compatibility
