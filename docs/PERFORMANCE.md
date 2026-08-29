# FK33 525 MHz performance validation

The `v0.4.0-beta` release was physically validated on six SQRL FK33 cards.

| Metric | Result |
|---|---:|
| 500 MHz fleet baseline | 2.887 GH/s |
| 525 MHz fleet result | **3.172 GH/s** |
| Improvement | **+9.87%** |
| Average per FK33 | 528.67 MH/s |
| Clock-derived design rate | 3.150 GH/s |
| Submitted / accepted | 680 / 680 |
| Rejects / duplicates / faults | 0 / 0 / 0 |
| Measurement window | 660 seconds |

Per-card rates were 551.05, 463.20, 513.05, 581.48, 535.24, and
528.03 MH/s. Public card identifiers are intentionally omitted.

The calculation used the exact target associated with each submitted share.
The measured 100.70% of design rate reflects normal short-window share
variance, not operation beyond the 525 MHz clock-derived rate.

A 525 MH/s engine exhausts the 32-bit nonce range in approximately 8.18
seconds. The runtime rolls `extranonce2` every 7.5 seconds before repetition.

No contemporaneous 525 MHz whole-rig power sample was available. The earlier
306 W measurement applies only to the 500 MHz validation; this release makes
no measured 525 MHz power or efficiency claim.

All six services remained active. No rejected shares, duplicate shares,
digest faults, comparator faults, runtime faults, or voltage commands occurred.

## Native 650 MHz qualification boundary

The v0.5.0-beta native 650 MHz image represents a 23.81% clock increase over
525 MHz, but the completed test was a correctness and stability soak on one
card, not a fleet hashrate benchmark. It produced 675/675 accepted submissions
with zero digest mismatches over 60 minutes. No measured 650 MHz fleet
hashrate, wall power, or efficiency result is claimed.
