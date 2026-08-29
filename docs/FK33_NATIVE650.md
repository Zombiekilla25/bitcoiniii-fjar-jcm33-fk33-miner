# FK33 native 650 MHz image

`hardware/prebuilt/fk33_native_bscan_650_validated.bit` is an uncompressed,
native eight-bit FK33 SHA3-256T image. It is not the JCM33 dual-device image.

## Qualification boundary

- Exact SHA-256: `bd494ba2ea697a5e916b51caf4bdab8e5c620cd121bfd4b2e9a806deb5596c39`
- Target: `xcvu33p-fsvh2104-2-e`
- Routed setup WNS: `+0.002 ns`
- Routed hold WHS: `+0.007 ns`
- One physical FK33, 60-minute BitcoinIII soak
- 740 hardware share frames
- 65 duplicate candidates suppressed before submission
- 675 submitted and 675 accepted shares
- Zero rejected shares, hardware/software mismatches, or protocol errors
- Initial/post-soak temperature: `27.646 C` / `41.076 C`
- Stock VCCINT observation: `0.809 V` / `0.803 V`
- No voltage command
- Exact 525 MHz rollback confirmed after the run

The image is hardware-qualified on one FK33, not yet fleet-qualified across
multiple cards. The positive timing margin is only `0.002 ns`; 650 MHz is the
ceiling for this exact route.

## Portable selection

The portable FJAR launcher retains 525 MHz as its default. Select 650 MHz
explicitly:

```bash
./start.sh doctor --qualified-650 [other options]
./start.sh start --qualified-650 [other options]
```

BitcoinIII fleet selection additionally retains the existing `--canary-passed`
acknowledgement:

```bash
./start-btc3.sh doctor --qualified-650 [other options]
./start-btc3.sh start --qualified-650 --canary-passed [other options]
```

## Installed systemd fleet

Set this only for a staged rollout:

```text
FJAR_FLEET_BITSTREAM=650
```

in `~/.config/fk33-fjar-miner/fleet.env`, then restart the shared bridge and
workers. Set it back to `525` to select the retained rollback image. The
runtime authenticates either image before programming any card.
