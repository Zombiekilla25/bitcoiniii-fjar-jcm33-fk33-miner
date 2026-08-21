# Developer fee policy

The runtime implements a transparent 1% time-based developer fee.

Each card uses a 6,000-second wall-clock cycle:

- 5,940 seconds: operator wallet (`USER`)
- 60 seconds: developer wallet (`DEVFEE`)

The phase is deterministically distributed using the serial and worker name so
multiple cards do not normally rotate together. Because the schedule is tied
to wall-clock time, restarting does not reset the operator interval.

Developer wallet:

```text
fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l
```

At a boundary, the bridge reconnects Stratum with the correct wallet. Every job
retains its wallet and fee mode. Logs expose startup policy, rotations,
submissions, and acceptances.

This is time allocation, not a split coinbase. On a solo pool, an entire block
found during the developer window is credited to the developer wallet. The
long-run expected allocation is 1%, while individual outcomes are variable.
