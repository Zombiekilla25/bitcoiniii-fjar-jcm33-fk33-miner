# JCM33 650 MHz validation boundary

This release is physically qualified only for the tested dual-VU33P JCM33
carrier with working water cooling, unchanged stock voltage, and the exact
uncompressed bitstream identified below.

| Item | Qualified result |
|---|---|
| Bitstream SHA-256 | `0eacb71eb4cb5f6a43f761d1af64dfe25c8fa22177974082742dc12d6f6cdcf1` |
| Routed checkpoint SHA-256 | `31a1b1888f50c3f03b229955b7d2575cfb5c621a942eeddb77739970dcb55c73` |
| Bitstream size | 28,329,354 bytes |
| Clock | 650 MHz per FPGA |
| Nominal combined rate | 1.30 GH/s |
| Accepted shares | A=1,380, B=1,362 |
| Rejected / digest mismatches | 0 / 0 |
| Final setup WNS | +0.010 ns |
| Final hold WHS | +0.010 ns |
| Maximum reported temperature | 30.133 C |
| Voltage | unchanged; VCCINT 0.847–0.850 V |
| Whole-system power | not measured at 650 MHz |
| Rollback | qualified 587.5 MHz image; not needed in either run |

The setup and hold margins are positive but narrow. This evidence does not
qualify operation above 650 MHz, a different carrier, cooling failure, or a
voltage change. Stop operation if coolant flow, pump operation, temperature,
or power delivery becomes abnormal.

The public miner retains the documented 1% host-side BitcoinIII developer-fee
rotation. Hardware qualification used fee rotation disabled; the policy does
not change the FPGA bitstream, work frames, digest validation, transport,
clock tree, implementation result, or timing evidence.
