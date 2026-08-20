# Hardware build

## Tested toolchain

- Vivado 2026.1, 64-bit Linux
- Target part `xcvu33p-fsvh2104-2-e`
- Ubuntu 24.04 x86-64

Vivado and its license are not included.

## Build

```bash
cd hardware/source
chmod +x run_build_350_margin.sh
VIVADO_BIN="$HOME/Xilinx/2026.1/Vivado/bin/vivado" \
  ./run_build_350_margin.sh
```

The script performs the three-context simulation, synthesis, placement,
physical optimization, routing, timing gates, bitstream generation, and debug
probe export. It refuses bitstream generation when setup or hold slack is
negative.

The verified build flow retains its internal output names:

```text
bc3_80pipe_token3_350_margin.bit
bc3_80pipe_token3_350_margin.ltx
```

For the release runtime, copy successful outputs to:

```bash
cp -p bc3_80pipe_token3_350_margin.bit \
  ../prebuilt/fk33_fjar_80pipe_token3_350mhz.bit

cp -p bc3_80pipe_token3_350_margin.ltx \
  ../prebuilt/fk33_fjar_80pipe_token3_350mhz.ltx
```

Regenerate `SHA256SUMS` before distributing a rebuilt release.

## Verified routed result

- 350.000 MHz generated hash clock
- WNS `+0.024 ns`
- TNS `0.000 ns`
- WHS `+0.006 ns`
- THS `0.000 ns`
- zero timing-failing endpoints
- zero routing errors
- CLB LUT utilization: 263,212 / 439,680 (`59.86%`)
- CLB register utilization: 530,114 / 879,360 (`60.28%`)

The full generated reports are under `hardware/reports/`.

## Programming warning

Vivado can report that the bitstream was generated for the ES1 target while a
revision-0 device is compatible with ES1 bitstreams. That warning was observed
during the successful validation run. Do not treat unrelated part or IDCODE
mismatches as benign.
