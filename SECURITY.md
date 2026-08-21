# Security

## Secrets

This miner requires only a public FJARCODE payout address. Never provide it with
a seed phrase, private key, wallet backup, wallet passphrase, exchange password,
or RPC credential. None of those values belong in `miner.env`, command lines,
logs, issues, or support requests.

## Release verification

Run `./verify-release.sh` before installation. Compare the outer release archive
hash with the hash published alongside the release. Treat any mismatch as a
failed verification.

## Network access

The Python bridge connects to the configured Stratum host and to a TCP port
exposed by the operator-supplied SQRL raw-JTAG bridge. The default pool is
`stratum.pythonpool.dev:3358`. The bridge used for validation bound its TCP
listener to `0.0.0.0`, not only loopback. Do not expose the configured hardware
ports to untrusted networks; use the host firewall or an isolated mining LAN.
Review both service files before running them.

## Hardware isolation

Every SQRL service selects an exact FK33 serial and refuses ambiguous USB
matches. Each card uses a private working directory and a unique configured TCP
port. Do not run two services against the same serial. Stop immediately if logs
show an FPGA/Python digest mismatch, repeated target-comparator disagreement,
or persistent pool rejects.

## Reporting a vulnerability

When a public source repository is created, use its private security-reporting
channel when available. Do not include wallet secrets, private keys, or unrelated
machine logs in a report.
