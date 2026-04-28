# Linux native PBS backup

Runs `proxmox-backup-client` directly on a Linux host (no Docker), driven by a
systemd timer. Backs up `/root` and `/home/claude` nightly at 02:00 to a
Proxmox Backup Server.

## Install

```bash
sudo bash linux/install.sh
```

First run installs `proxmox-backup-client` from the official Proxmox apt repo,
copies `backup.sh` to `/usr/local/bin/pbs-backup.sh`, copies the systemd units
to `/etc/systemd/system/`, and seeds `/etc/pbs-backup.env` (mode 600).

The env source is auto-detected:

- If a sibling `.env` exists in the repo root (one level up from `linux/`),
  the installer copies it to `/etc/pbs-backup.env` and continues. This means
  the same env file works for both the Docker and Linux deployments.
- Otherwise, the installer copies `pbs-backup.env.example` to
  `/etc/pbs-backup.env` and halts. Fill it in, then re-run.

The env file accepts either a single `PBS_REPOSITORY=user@realm@host:port:datastore`
or the docker-compose-style trio (`PBS_USER`, `PBS_SERVER`, `PBS_DATASTORE`).
`backup.sh` composes the repository string when the trio is set.

Re-run `sudo bash linux/install.sh` to enable and start the timer.

## Inspect

```bash
systemctl list-timers pbs-backup.timer       # next scheduled run
systemctl status pbs-backup.timer
journalctl -u pbs-backup.service -n 100      # last run log
journalctl -u pbs-backup.service -f          # follow live
```

## Run on demand

```bash
sudo systemctl start pbs-backup.service
```

Or invoke the script directly (env vars must be exported in the current shell):

```bash
set -a; . /etc/pbs-backup.env; set +a
sudo -E /usr/local/bin/pbs-backup.sh
```

## Files

- `backup.sh` → `/usr/local/bin/pbs-backup.sh`
- `pbs-backup.service` / `pbs-backup.timer` → `/etc/systemd/system/`
- `pbs-backup.env.example` → `/etc/pbs-backup.env` (chmod 600)
