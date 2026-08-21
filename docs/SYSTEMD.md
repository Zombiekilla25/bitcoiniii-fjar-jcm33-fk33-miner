# systemd operation

The installer uses user-level services and does not request root access.

```text
~/.local/share/fk33-fjar-miner/0.2.0-beta/       installed release
~/.local/share/fk33-fjar-miner/current           active release symlink
~/.local/share/fk33-fjar-miner/private/           operator-supplied runtime
~/.config/fk33-fjar-miner/miner.env               wallet and pool
~/.config/fk33-fjar-miner/cards/SERIAL.env        worker and TCP port
~/.local/state/fk33-fjar-miner/SERIAL/             logs and SQRL state
~/.config/systemd/user/                            unit templates
```

Every card needs a unique local TCP port. The SQRL service changes into a
private writable per-card directory before launch because the legacy bridge
creates `virtual_ports` in its current directory.

## Start

```bash
./start-card.sh SERIAL
```

This starts `fk33-sqrl-bridge@SERIAL.service`, waits for the configured local
port, then starts `fjar-fk33-standalone@SERIAL.service`.

## Inspect

```bash
./status-card.sh SERIAL
```

Systemd's `MainPID` is authoritative. The release does not depend on manual PID
files.

## Stop

```bash
./disable-card.sh SERIAL
```

## Boot before login

Operators who intentionally need user services before interactive login can
enable lingering themselves:

```bash
sudo loginctl enable-linger "$USER"
```

The installer does not perform this privileged action.
