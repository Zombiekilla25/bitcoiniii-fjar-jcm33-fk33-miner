# FK33 500 MHz performance validation

The `v0.3.0-beta` release was validated on six SQRL FK33 cards using the
500 MHz initiation-interval-one SHA3-256T engine and the standalone framed
BSCAN transport.

## Headline result

| Metric | Result |
|---|---:|
| Six-card effective pool hashrate before fresh-work rolling | 1.504 GH/s |
| Six-card effective pool hashrate after fresh-work rolling | 2.887 GH/s |
| Effective pool-hashrate gain | **+91.95%** |
| Average per FK33 | 481.17 MH/s |
| Six-card design rate | 3.000 GH/s |
| Achieved share-derived rate vs. design rate | 96.23% |
| Rejected shares during the measured validation | 0 |

At 500 MH/s, a card exhausts a 32-bit nonce range in about 8.59 seconds.
Long-lived Stratum jobs therefore caused repeated candidates and capped useful
work well below the physical engine rate. The runtime now rolls `extranonce2`
every 7.5 seconds, rebuilding the coinbase, Merkle root, header, and tag before
the nonce range repeats. Hardware and Python digest verification still occurs
before every submission.

## Power and efficiency

The Octominer PSU reported the following while all six cards remained mining:

| Measurement | Result |
|---|---:|
| Whole-rig AC power | 306 W |
| Whole-rig DC output | 279 W |
| AC voltage / current | 230.5 V / 1.33 A |
| AC efficiency | 9.43 MH/s/W |
| Energy per gigahash at the wall | 106.0 J/GH |
| PSU temperatures | 31 C / 49 C |
| PSU fan | 1,680 RPM |

The 306 W figure is whole-rig input power. It includes the six FPGA cards,
host, chassis fans, PSU conversion losses, and any other load on that PSU; it
is not an FPGA-only board-power measurement.

## Validation gates

- Six authenticated FK33s loaded the 500 MHz image.
- Every card produced a hardware/Python digest match.
- Every card produced pool-accepted shares.
- The shared SQRL bridge remained running during the runtime-only rollout.
- Fresh-work rolling raised the measured fleet rate to 2.887 GH/s.
- No voltage command was issued.
- No rejected shares or digest/comparator errors occurred in the measured run.

Mining results vary with pool difficulty, job cadence, network latency,
temperature, device quality, and measurement-window length. This beta is
experimental hardware software, not a profitability guarantee.
