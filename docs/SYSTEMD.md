# systemd operation

The installer uses user-level services; root is not required for normal service
operation.

## Files

```text
~/.local/share/fk33-fjar-miner/0.1.0-beta/  installed release
~/.local/share/fk33-fjar-miner/current      active release symlink
~/.config/fk33-fjar-miner/miner.env         operator configuration
~/.local/state/fk33-fjar-miner/SERIAL/      jobs, status, and logs
~/.config/systemd/user/                      unit templates
```

## Start

```bash
systemctl --user enable --now fjar-fk33-worker@SERIAL.service
systemctl --user enable --now fjar-fk33-bridge@SERIAL.service
```

The worker programs the selected FPGA and starts the VIO mailbox. The bridge
waits up to 180 seconds for fresh VIO status before connecting to the pool.

## Inspect

```bash
systemctl --user --no-pager --full status \
  fjar-fk33-worker@SERIAL.service \
  fjar-fk33-bridge@SERIAL.service

systemctl --user show \
  fjar-fk33-worker@SERIAL.service \
  fjar-fk33-bridge@SERIAL.service \
  -p Id -p ActiveState -p SubState -p MainPID -p NRestarts
```

Systemd's `MainPID` is authoritative; this release does not use stale manual PID
files.

## Stop

```bash
./disable-card.sh SERIAL
```

## Boot before login

If mining must start without an interactive login, the operator can explicitly
enable lingering:

```bash
sudo loginctl enable-linger "$USER"
```

This is intentionally not performed by the installer.
