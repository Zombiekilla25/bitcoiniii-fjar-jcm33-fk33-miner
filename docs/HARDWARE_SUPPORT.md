# Hardware and network support

This repository contains separate transport images for JCM33 and FK33
XCVU33P hardware. A shared SHA3-256T algorithm does not make their bitstreams
interchangeable.

| Platform | Network | Status | Image |
|---|---|---|---|
| JCM33 dual-FPGA carrier | BitcoinIII | Physically validated at 525 MHz | `hardware/prebuilt/jcm33_bitcoiniii_dualalign_525_validated.bit` |
| FK33 | FJAR | Six-card fleet validated at 525 MHz | `hardware/prebuilt/fk33_fjar_bscan_525.bit` |
| FK33 | BitcoinIII | Guarded canary/fleet software path | Uses the qualified FK33 525 MHz SHA3-256T image |

## JCM33 production boundary

- Clock: 525 MHz
- Devices: both VU33P FPGAs on the tested JCM33 carrier
- Transport: nine-bit USER2 capture with automatic low/high byte alignment
- Accepted shares: 185 from device A and 211 from device B
- Rejections: 0
- Hardware/software digest mismatches: 0
- Bitstream SHA-256: `2ef00b41b8b542cf4725336c7754e3b81e5a23aa710993fc0f5f8b2828e05a8d`
- Voltage changes: none

The JCM33 image is not an FK33 image. Higher clocks, different carriers,
modified transports, cooling changes, or voltage changes require a new timing
and physical acceptance qualification.

## FK33 boundary

The FK33 FJAR path retains the verified 525 MHz fleet release and its 500 MHz
rollback image. The BitcoinIII FK33 launchers remain gated by the one-card
canary procedure in [BTC3_CANARY.md](BTC3_CANARY.md).
