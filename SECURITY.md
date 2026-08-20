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

The Python bridge opens a TCP connection only to the configured Stratum host and
port. The default is `stratum.pythonpool.dev:3358`. The Vivado worker connects to
the local AMD/Xilinx hardware server. Review the source and service files before
running them.

## Hardware isolation

Every worker selects an exact FK33 serial and refuses ambiguous target matches.
Do not run two workers against the same serial. Stop mining immediately if logs
show an FPGA/Python digest mismatch, repeated target-comparator disagreement, or
persistent pool rejects.

## Reporting a vulnerability

When a public source repository is created, use its private security-reporting
channel when available. Do not include wallet secrets, private keys, or unrelated
machine logs in a report.
