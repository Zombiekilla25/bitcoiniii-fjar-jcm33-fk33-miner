# systemd fleet operation

The runtime uses one user-level bridge service and one miner service per card.

```text
~/.local/share/fk33-fjar-miner/0.4.0-beta/       installed release
~/.local/share/fk33-fjar-miner/current           active release symlink
~/.local/share/fk33-fjar-miner/private/           bridge and ABI libraries
~/.config/fk33-fjar-miner/miner.env               wallet and pool
~/.config/fk33-fjar-miner/fleet.env               card order and base port
~/.config/fk33-fjar-miner/cards/SERIAL.env        worker and mapped port
~/.local/state/fk33-fjar-miner/fleet/              SQRL state and logs
~/.local/state/fk33-fjar-miner/SERIAL/             miner log
```

`fk33-sqrl-fleet.service` releases FTDI interfaces and starts exactly one
bridge process. `fjar-fk33-fleet@SERIAL.service` waits for all configured
bitstreams and validates that serial's expected port before starting Python.

## Start and inspect

```bash
./start-fleet.sh
./status-fleet.sh
./status-card.sh SERIAL
```

The bridge's systemd `MainPID` is authoritative. The release does not depend
on manual PID files.

## Stop

```bash
./disable-card.sh SERIAL
./disable-fleet.sh
```

Disabling one card stops only its Python miner because the bridge is shared.

## Boot before login

Use the installer's `--enable-linger` option or configure it directly:

```bash
sudo loginctl enable-linger "$USER"
```

The serial-specific udev rule must also be installed so USB node permissions
survive reboot. The FTDI-release helper uses noninteractive sudo; the intended
runtime host must authorize that operation or keep the interfaces unbound by
another controlled mechanism.

A reboot test is not complete merely because the ports listen. Wait until the
fleet log contains one `Bitstream Loaded` event per configured card and each
miner records a fresh accepted share.
