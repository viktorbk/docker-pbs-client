# Docker PBS Client

Minimal Debian Docker container running `proxmox-backup-client` for backing up to a Proxmox Backup Server (4.x).

Features:
- Debian Bookworm slim (~120 MB image)
- Incremental backups with deduplication
- Cron scheduling inside the container
- Automatic pruning of old snapshots
- macOS artifact exclusions

## Setup

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

## Finding the PBS fingerprint

On the PBS web UI (`https://<PBS_IP>:8007`), the fingerprint is shown on the **Dashboard**.

Or via the PBS server shell:
```bash
proxmox-backup-manager cert info | grep Fingerprint
```

## Usage

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

## Optional: Encryption key

```bash
docker compose exec pbs-client proxmox-backup-client key create --kdf none
```

The key is stored in the persistent `pbs-config` volume and survives container rebuilds.
