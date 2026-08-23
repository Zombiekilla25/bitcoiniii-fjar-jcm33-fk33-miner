# Developer bitstream build

End users use `hardware/prebuilt/fk33_fjar_bscan_525.bit` and do not need
Vivado. The authenticated 500 MHz image remains included for rollback.

The validated toolchain was Vivado 2026.1 on Ubuntu 24.04 x86-64 targeting
`xcvu33p-fsvh2104-2-e`.

## Build the 525 MHz image

Run `cd hardware/source/ii1_525`, followed by `./run_build.sh`.

The runner requires the SHA3T known-answer simulation to pass before synthesis,
implementation, routing, setup/hold timing gates, and uncompressed bitstream
generation.

## Validated routed result

- Hash clock: 525.000 MHz
- WNS: `+0.056 ns`
- TNS: `0.000 ns`
- WHS: `+0.010 ns`
- Timing-failing endpoints: 0
- Routing errors: 0
- Compression disabled for legacy SQRL-loader compatibility
- Bitstream SHA256:
  `64e0a7d21a10b4aa04b340c826af7d75363b5d5ba5e39330fe28c42ff103821c`

Timing, utilization, hierarchy, congestion, and route reports are included
under `hardware/reports/`.

Do not distribute a generated image until simulation, routing, setup, hold,
physical digest, and accepted-share gates all pass.
