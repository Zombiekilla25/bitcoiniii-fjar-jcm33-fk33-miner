# Experimental 550 MHz image

`hardware/prebuilt/fk33_fjar_bscan_550_experimental.bit` is a candidate image
for SQRL FK33 XCVU33P cards. It is included for controlled hardware validation;
it is not the default mining image.

## Artifact facts

- The image identifies `miner_top_ii1_bscan_550`.
- The target encoded in the image is `xcvu33p-fsvh2104-2-e`.
- The image records Vivado version `2026.1`.
- Bitstream compression is disabled for the legacy SQRL raw-JTAG bridge.
- SHA-256:
  `de9621edb8fdb1df35270ac601668b0b30ada110c5ed446114755c7093a2e8db`

## Qualification still required

This repository does not include a positive setup/hold timing report for this
exact image. No physical FK33 has been programmed with it in the release
evidence, and no share-derived hashrate, stability, temperature, power, or
accepted/rejected-share sample is claimed. The validated 525 MHz image remains
the default and rollback target.

## Controlled selection

Run a read-only preflight first:

```bash
./start.sh doctor --experimental-550
```

Then select the candidate explicitly:

```bash
./start.sh \
  --wallet 'fjarcode:YOUR_LOWERCASE_ADDRESS' \
  --experimental-550
```

Start with one card. Stop on programming errors, transport faults, digest or
comparator disagreement, rejected/duplicate shares, excessive temperature, or
unstable power. This software does not issue a voltage command.
