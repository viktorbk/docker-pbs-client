# PBS Client

Two ways to run `proxmox-backup-client` against a Proxmox Backup Server (4.x):

- **[Docker](#docker-setup)** — minimal Debian container, intended for macOS hosts where the client is not packaged natively. Runs `cron` inside the container.
- **[Native Linux](#native-linux-setup)** — installer + systemd timer for Linux hosts that can run the deb directly. No Docker required.

Common features:
- Incremental backups with deduplication
- Nightly schedule with automatic pruning of old snapshots

---

## Docker setup

Minimal Debian Docker container running `proxmox-backup-client`.

Features:
- Debian Bookworm slim (~120 MB image)
- Cron scheduling inside the container
- macOS artifact exclusions (`.DS_Store`, `.Spotlight-V100`, etc.)

### Configure

1. Copy the example env and fill in your details:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your PBS connection details:
   - `PBS_SERVER` — IP:port (e.g. `192.168.1.100:8007`)
   - `PBS_USER` — PBS user (e.g. `root@pam`)
   - `PBS_PASSWORD` — password
   - `PBS_DATASTORE` — target datastore name
   - `PBS_FINGERPRINT` — server TLS fingerprint (see below)
   - `BACKUP_CRON` — cron schedule (default: `0 2 * * *` = 2 AM daily)
   - `TZ` — timezone

3. Edit `docker-compose.yml` — update the volume mount under `volumes:` to point at the directories you want backed up

4. Edit `backup.sh` — update the archive name/path to match your volume mount

5. Build and start:
   ```bash
   docker compose up -d --build
   ```

### Usage

Test connectivity:
```bash
docker compose exec pbs-client proxmox-backup-client snapshot list
```

Run a manual backup:
```bash
docker compose exec pbs-client /usr/local/bin/backup.sh
```

View backup logs:
```bash
docker compose exec pbs-client tail -30 /var/log/pbs-backup/backup.log
```

### Optional: Encryption key

```bash
docker compose exec pbs-client proxmox-backup-client key create --kdf none
```

The key is stored in the persistent `pbs-config` volume and survives container rebuilds.

---

## Native Linux setup

For Linux hosts (Debian/Ubuntu) — installs `proxmox-backup-client` from the official Proxmox apt repo and registers a systemd timer that runs nightly at 02:00.

By default, this layout backs up `/root` and `/home/claude` under the backup-id `contabo-server`. Edit `linux/backup.sh` to change the source paths or backup-id for your host.

### Install

```bash
sudo bash linux/install.sh
```

The first run installs the package, drops the script + units, and creates `/etc/pbs-backup.env` (mode 600). Where the env file comes from depends on what's in the repo when you run the installer:

- **If the repo's `.env` already exists** (because you also use the Docker setup, or you copied `.env.example` to `.env` and filled it in), `install.sh` copies it to `/etc/pbs-backup.env` automatically and continues.
- **If no `.env` is found**, `install.sh` copies `linux/pbs-backup.env.example` to `/etc/pbs-backup.env` and halts. Edit it, then re-run.

The env file accepts either a single `PBS_REPOSITORY=user@realm@host:port:datastore` or the docker-compose-style trio (`PBS_USER`, `PBS_SERVER`, `PBS_DATASTORE`) — `backup.sh` composes the repository string when the trio is set.

Re-run `sudo bash linux/install.sh` to enable and start the timer.

### Usage

Run a backup on demand:
```bash
sudo systemctl start pbs-backup.service
```

Inspect the schedule and recent runs:
```bash
systemctl list-timers pbs-backup.timer       # next scheduled run
journalctl -u pbs-backup.service -n 100      # last run log
journalctl -u pbs-backup.service -f          # follow live
```

Test connectivity (after `/etc/pbs-backup.env` is filled in):
```bash
set -a; . /etc/pbs-backup.env; set +a
proxmox-backup-client snapshot list --repository "$PBS_REPOSITORY"
```

See `linux/README.md` for the full file layout.

---

## Finding the PBS fingerprint

On the PBS web UI (`https://<PBS_IP>:8007`), the fingerprint is shown on the **Dashboard**.

Or via the PBS server shell:
```bash
proxmox-backup-manager cert info | grep Fingerprint
```
