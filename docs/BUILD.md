# Developer bitstream build

End users use `hardware/prebuilt/fk33_fjar_bscan_500.bit` and do not need
Vivado. The validated developer toolchain was Vivado 2026.1 on Ubuntu 24.04
x86-64 targeting `xcvu33p-fsvh2104-2-e`.

## Offline runtime tests

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v
```

## 500 MHz image

```bash
cd hardware/source/ii1_500
./run_build.sh
```

The runner first requires `SHA3T II1 RAW DIGEST ALL PASS`, then performs
synthesis, implementation, routing, setup/hold timing gates, and uncompressed
bitstream generation. Expected output:

```text
FK33 FJAR II1 BSCAN 500 MHZ FULL BUILD COMPLETE
```

## Validated routed result

- Hash clock: 500.000 MHz
- WNS: `+0.336 ns`
- TNS: `0.000 ns`
- WHS: `+0.010 ns`
- Timing-failing endpoints: 0
- Fully routed nets: 360,460
- Routing errors: 0
- CLB LUTs: 146,822 / 439,680 (33.39%)
- CLB registers: 359,255 / 879,360 (40.85%)
- Bitstream compression: disabled for legacy SQRL-loader compatibility
- Bitstream SHA256: `efe740723b4ef4d93b29339cdeea32416495aabea8f78cb15f3456c44a354ecb`

Do not distribute a newly generated image until its known-answer simulation,
route, setup, hold, physical digest, and accepted-share gates all pass.
