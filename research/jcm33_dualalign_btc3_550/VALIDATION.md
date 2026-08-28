# JCM33 550 MHz validation boundary

This release is physically qualified only for the tested dual-VU33P JCM33
carrier with working water cooling, unchanged stock voltage, and the exact
uncompressed bitstream identified below.

| Item | Qualified result |
|---|---|
| Bitstream SHA-256 | `9b75f638459b9c07cc4b36cade5c41d6e45df8f18d9c26020b651f95b52d5e6c` |
| Bitstream size | 28,329,354 bytes |
| Clock | 550 MHz per FPGA |
| Nominal combined rate | 1.10 GH/s |
| Accepted shares | A=634, B=650 |
| Rejected / digest mismatches | 0 / 0 |
| Final setup WNS | +0.128 ns |
| Final hold WHS | +0.010 ns |
| Maximum reported temperature | 28.641 C |
| Voltage | unchanged; VCCINT 0.847–0.850 V |
| Whole-system power | 114 W including pump and fans |

The 114 W measurement is a complete-system observation, not isolated FPGA
board power. The short-window pool rate is probabilistic; the deterministic
clock-derived design rate is 1.10 GH/s.

The hold margin is positive but narrow. Do not infer qualification above
550 MHz. Stop operation if coolant flow, pump operation, temperature, or power
delivery becomes abnormal. The validated 525 MHz image is the fallback.

Hardware qualification was performed with developer-fee rotation disabled.
The published 1% host-side wallet/worker rotation leaves the FPGA bitstream,
job framing, digest verification, transport alignment, clocking, and timing
unchanged.
