# Hardware and network support

This repository contains separate transport images for JCM33 and FK33
XCVU33P hardware. A shared SHA3-256T algorithm does not make their bitstreams
interchangeable.

| Platform | Network | Status | Image |
|---|---|---|---|
| JCM33 dual-FPGA carrier | BitcoinIII | Physically validated at 550 MHz | `hardware/prebuilt/jcm33_bitcoiniii_dualalign_550_validated.bit` |
| FK33 | FJAR | Six-card fleet validated at 525 MHz | `hardware/prebuilt/fk33_fjar_bscan_525.bit` |
| FK33 | BitcoinIII | Guarded canary/fleet software path | Uses the qualified FK33 525 MHz SHA3-256T image |

## JCM33 production boundary

- Clock: 550 MHz
- Devices: both VU33P FPGAs on the tested JCM33 carrier
- Transport: nine-bit USER2 capture with automatic low/high byte alignment
- Accepted shares: 634 from device A and 650 from device B across two runs
- Rejections: 0
- Hardware/software digest mismatches: 0
- Bitstream SHA-256: `9b75f638459b9c07cc4b36cade5c41d6e45df8f18d9c26020b651f95b52d5e6c`
- Timing: setup WNS `+0.128 ns`; hold WHS `+0.010 ns`
- Maximum observed FPGA temperature: `28.641 C`
- Complete-system power observation: 114 W including water pump and fans
- Voltage changes: none

The JCM33 image is not an FK33 image. The positive hold margin is narrow;
higher clocks, different carriers, modified transports, cooling changes, or
voltage changes require a new timing and physical acceptance qualification.
The validated 525 MHz image remains the rollback/fallback artifact.

## FK33 boundary

The FK33 FJAR path retains the verified 525 MHz fleet release and its 500 MHz
rollback image. The BitcoinIII FK33 launchers remain gated by the one-card
canary procedure in [BTC3_CANARY.md](BTC3_CANARY.md).
