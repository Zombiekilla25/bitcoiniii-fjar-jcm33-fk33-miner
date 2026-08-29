# Hardware and network support

This repository contains separate transport images for JCM33 and FK33
XCVU33P hardware. A shared SHA3-256T algorithm does not make their bitstreams
interchangeable.

| Platform | Network | Status | Image |
|---|---|---|---|
| JCM33 dual-FPGA carrier | BitcoinIII | Physically validated at 650 MHz | `hardware/prebuilt/jcm33_bitcoiniii_dualalign_650_validated.bit` |
| FK33 | FJAR | Six-card fleet validated at 525 MHz | `hardware/prebuilt/fk33_fjar_bscan_525.bit` |
| FK33 | BitcoinIII | One-card validated at native 650 MHz | `hardware/prebuilt/fk33_native_bscan_650_validated.bit` |

## JCM33 production boundary

- Clock: 650 MHz per FPGA; nominal combined engine rate 1.30 GH/s
- Devices: both VU33P FPGAs on the tested JCM33 carrier
- Transport: nine-bit USER2 capture with automatic low/high byte alignment
- Accepted shares: A=1,380 and B=1,362 across the 5-minute and 60-minute runs
- Rejections: 0
- Hardware/software digest mismatches: 0
- Bitstream SHA-256: `0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1`
- Timing: setup WNS `+0.010 ns`; hold WHS `+0.010 ns`
- Maximum observed FPGA temperature: `30.133 C`
- Stock VCCINT observation: `0.847–0.850 V`
- Voltage changes: none
- 650 MHz wall power: not measured; no efficiency claim

The timing margin is positive but only `0.010 ns`. Treat 650 MHz as the
production ceiling for this RTL and route. Any higher clock requires a new
timing-gated build, rollback-protected hardware canary, and soak test. A
meaningful increase beyond 650 MHz should use another pipeline/placement
revision instead of relabeling this image.

The qualification package carried the exact hardware-qualified 587.5 MHz
rollback image and did not need to invoke it. The published validated 550 MHz
and 525 MHz images remain additional fallbacks.

## FK33 boundary

The FK33 FJAR path retains the verified 525 MHz fleet release and its 500 MHz
rollback image. The native FK33 650 MHz image passed a 60-minute BitcoinIII
soak on one physical card with 675/675 submitted shares accepted and zero
digest mismatches. It is opt-in because it has not yet completed a multi-card
fleet qualification. See [FK33_NATIVE650.md](FK33_NATIVE650.md).

The BitcoinIII FK33 launchers remain guarded by explicit canary
acknowledgement. The JCM33 650 MHz image must not be used on FK33 because its
dual-device JTAG alignment is different.
