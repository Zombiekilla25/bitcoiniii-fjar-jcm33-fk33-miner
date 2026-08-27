# BitcoinIII (BTC3) one-card canary

BitcoinIII and FJAR use the same SHA3-256T hash construction, but the BTC3
pool path is not yet fleet-qualified.  This canary reuses the checksum-pinned
525 MHz FK33 SHA3-256T image and changes only the Stratum worker configuration.

Safety gates:

- Exactly one FK33 serial is accepted.
- The 550 MHz image and arbitrary bitstream overrides are not accepted.
- FPGA voltage is never changed.
- There is no FJAR address or developer-wallet rotation in the BTC3 worker.
- A matching `hw=`/`sw=` digest and an `[ACCEPTED]` BTC3 share are required
  before any fleet deployment.

## First canary

Stop the FJAR launcher before taking control of the selected USB/JTAG device:

```bash
cd ~/fk33-fjar-miner-main
./start.sh stop
sudo -v
```

Run the read-only preflight:

```bash
./start-btc3-canary.sh doctor \
  --wallet 'bc1qYOUR_BTC3_ADDRESS' \
  --serials 'YOUR_ONE_FK33_SERIAL' \
  --allow-card-count-mismatch
```

If the preflight passes, start the one-card canary:

```bash
./start-btc3-canary.sh start \
  --wallet 'bc1qYOUR_BTC3_ADDRESS' \
  --serials 'YOUR_ONE_FK33_SERIAL' \
  --allow-card-count-mismatch
```

Watch the worker:

```bash
./start-btc3-canary.sh logs --lines 200
```

Success requires both of the following in the same worker log:

```text
hw=<digest>
sw=<same digest>
[ACCEPTED][USER]
```

Stop the canary with:

```bash
./start-btc3-canary.sh stop
```

Do not start all cards until the one-card evidence has been reviewed.

## Promote a passed canary to the fleet

After the canary has produced a matching `hw=`/`sw=` digest and an accepted
BTC3 share, stop it and build the selected serial list:

```bash
./start-btc3-canary.sh stop

SERIALS=$(
  grep -h . /sys/bus/usb/devices/*/serial 2>/dev/null |
  grep -E '^1533[0-9]{8}$' |
  sort -u |
  paste -sd, -
)

echo "$SERIALS"
```

Run the fleet preflight:

```bash
./start-btc3.sh doctor \
  --wallet 'bc1qYOUR_BTC3_ADDRESS' \
  --serials "$SERIALS" \
  --allow-card-count-mismatch
```

Then start the fleet with an explicit acknowledgement of the passed canary:

```bash
./start-btc3.sh start \
  --wallet 'bc1qYOUR_BTC3_ADDRESS' \
  --serials "$SERIALS" \
  --allow-card-count-mismatch \
  --canary-passed
```

The fleet launcher remains pinned to the 525 MHz SHA3-256T image and never
changes FPGA voltage.
