# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository purpose

This repo serves three roles simultaneously:

1. **A working Docker deployment** — the root `Dockerfile`, `docker-compose.yml`, `backup.sh`, and `.env.example` are the maintainer's Mac PBS backup setup (hostname `macbackupM4`, single `home.pxar` archive of `/Users/vikkjart/prjs`).
2. **A published npm scaffolder** — `bin/cli.js` is shipped as the `docker-pbs-client` binary (see `package.json` → `bin`). It runs an interactive prompt and writes a fresh `Dockerfile`, `docker-compose.yml`, `backup.sh`, `.env`, `.env.example`, and `.gitignore` into the user's CWD.
3. **A native Linux deployment** — `linux/` holds an installer (`install.sh`), a backup script (`backup.sh`), and a systemd timer + service for hosts that run `proxmox-backup-client` directly (no Docker). This deployment is independent of the Docker layout.

**Critical sync rule (Docker layout only):** `bin/cli.js` contains template-literal copies of the *root* files (`DOCKERFILE` const, `makeCompose()`, `makeBackupScript()`, `makeEnv()`). When you change the root `Dockerfile`, `docker-compose.yml`, or `backup.sh`, mirror the change inside `bin/cli.js` or scaffolded projects will drift from the reference setup. The two are not generated from a shared source — they're hand-kept in sync.

**The `linux/` directory is NOT subject to this rule** — it is not mirrored from `bin/cli.js` and the scaffolder does not emit Linux-native files. Treat `linux/` as its own self-contained deployment.

## Architecture

- **Base image:** `debian:bookworm-slim` + the `proxmox-backup-client` deb from `download.proxmox.com/debian/pbs-client`. Image is amd64-only because Proxmox does not publish arm64 packages — on Apple Silicon, `platform: linux/amd64` in compose forces Rosetta emulation.
- **Process model:** the container runs `cron -f` in the foreground. The compose `entrypoint` does runtime setup before exec'ing cron: creates `/var/log/pbs-backup` and `/run/pbs` (mode 700, used as `XDG_RUNTIME_DIR`), dumps the `PBS_*`/`XDG_*`/`TZ` env vars to `/etc/environment` (so the cron job can source them — cron strips env), then writes a single crontab line that sources `/etc/environment` and runs `/usr/local/bin/backup.sh`, appending to `/var/log/pbs-backup/backup.log`.
- **Why `/etc/environment` shuffle:** `proxmox-backup-client` reads `PBS_REPOSITORY`, `PBS_PASSWORD`, `PBS_FINGERPRINT` from env. Cron jobs don't inherit container env, so they must be re-sourced inside the cron line.
- **Persistence:** two named volumes — `pbs-config` (`/root/.config/proxmox-backup`, holds encryption keys and auth tokens, survives rebuilds) and `pbs-logs` (`/var/log/pbs-backup`).
- **Backup sources:** mounted read-only under `/backup-source/<name>` and archived as `<name>.pxar` via `proxmox-backup-client backup`. The archive name in `backup.sh` must match the mount path in `docker-compose.yml`.
- **Retention:** `backup.sh` runs `proxmox-backup-client prune host/<hostname>` after a successful backup with `--keep-daily 7 --keep-weekly 4 --keep-monthly 6`. The `host/<hostname>` group name is determined by `--backup-id` on the backup call (PBS auto-prefixes `host/`).
- **Excludes:** `backup.sh` exclude list is duplicated in two places — once in the `find` pre-scan (for the file count log line) and once in the `proxmox-backup-client backup --exclude` flags. Keep both in sync.

## Native Linux deployment (`linux/`)

- Installer: `sudo bash linux/install.sh` (idempotent — first run installs the deb + units, creates `/etc/pbs-backup.env` from the example, and halts; second run enables the timer once env is filled).
- Schedule: `linux/pbs-backup.timer` fires `pbs-backup.service` daily at 02:00 (`OnCalendar=*-*-* 02:00:00`, `Persistent=true`, `RandomizedDelaySec=5m`).
- Env injection: systemd's `EnvironmentFile=/etc/pbs-backup.env` injects `PBS_REPOSITORY`/`PBS_PASSWORD`/`PBS_FINGERPRINT` into the script — there is no `/etc/environment` shuffle as in the Docker setup, since the cron stripping problem doesn't apply.
- Repository env: the Linux script expects `PBS_REPOSITORY` as a single string (`USER@REALM@HOST:PORT:DATASTORE`), unlike the Docker compose which composes it from `PBS_USER`/`PBS_SERVER`/`PBS_DATASTORE`.
- Inspection: `systemctl list-timers pbs-backup.timer`, `journalctl -u pbs-backup.service`, `sudo systemctl start pbs-backup.service` to fire on demand.

## Common commands

```bash
# Build and start
docker compose up -d --build

# Manual backup (inside container)
docker compose exec pbs-client /usr/local/bin/backup.sh

# Connectivity test
docker compose exec pbs-client proxmox-backup-client snapshot list

# Tail logs
docker compose exec pbs-client tail -30 /var/log/pbs-backup/backup.log

# Create encryption key (stored in pbs-config volume)
docker compose exec pbs-client proxmox-backup-client key create --kdf none

# Run the scaffolder against the published version
npx docker-pbs-client
```

There is no test suite, lint config, or build step — this is a shell + Dockerfile + single-file Node CLI repo.

## When editing

- Changes to deployment behavior usually need to land in **both** the root files and the corresponding template in `bin/cli.js`.
- The `bin/cli.js` templates use `\$\${VAR}` and `\\$\\$BACKUP_CRON` escaping to survive both JS template literal evaluation and the shell heredoc inside `entrypoint`. When mirroring compose changes into the template, double-check `$` escaping.
- `package.json` only ships `bin/` (`files: ["bin/"]`); the root deployment files are not part of the published npm package.
