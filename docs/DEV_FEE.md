# Developer fee policy

The runtime implements a transparent 1% time-based developer fee.

## Schedule

Each card uses a 6,000-second wall-clock cycle:

- seconds 0 through 5,939: operator wallet (`USER`)
- seconds 5,940 through 5,999: developer wallet (`DEVFEE`)

The resulting developer window is exactly `60 / 6000 = 1%`. A deterministic
SHA-256-derived phase offset based on the FK serial and worker name spreads
multiple cards across the cycle. Because the schedule is anchored to wall-clock
time, restarting the process does not always reset it to the operator window.

## Wallet switching

Stratum v1 authorizes a single wallet/worker username per connection. At a
schedule boundary, the bridge closes the current connection and reconnects with
the appropriate wallet. Jobs remember the username and fee mode under which they
were created, so a share cannot silently cross from one wallet context to the
other.

The log reports:

- the exact fee percentage, cycle, window, and developer address at startup
- `[USER]` or `[DEVFEE]` on session, submission, and acceptance lines
- each wallet rotation and reconnect

## Developer wallet

```text
fjarcode:qq5daj4gl6q7t7hpwm2e5vu84gn4p3h7huu4h64z9l
```

The operator's `FJAR_WALLET` is mandatory and has no developer-wallet default.

## Solo-mining consequence

This is a time allocation, not a split coinbase. On a solo pool, a full block
found during the developer window is credited entirely to the developer wallet.
A block found during the operator window is credited entirely to the operator
wallet. Individual outcomes are highly variable; the expected long-run allocation
is 1%.

## Verification

`tests/test_fjar_bridge.py` checks the exact 5,940/60 boundary, stable per-card
phase selection, required operator-wallet configuration, confirmed developer
address, and job-bound submission username.
