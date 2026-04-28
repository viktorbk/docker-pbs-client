#!/bin/bash
set -uo pipefail

BACKUP_ID="${BACKUP_ID:-contabo-server}"

# Allow either a pre-built PBS_REPOSITORY or the docker-style trio
# (PBS_USER + PBS_SERVER + PBS_DATASTORE), matching docker-compose.yml:9.
if [ -z "${PBS_REPOSITORY:-}" ]; then
    if [ -n "${PBS_USER:-}" ] && [ -n "${PBS_SERVER:-}" ] && [ -n "${PBS_DATASTORE:-}" ]; then
        export PBS_REPOSITORY="${PBS_USER}@${PBS_SERVER}:${PBS_DATASTORE}"
    else
        echo "Error: set PBS_REPOSITORY, or PBS_USER + PBS_SERVER + PBS_DATASTORE" >&2
        exit 2
    fi
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/pbs-backup}"
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"

START_TS=$(date '+%Y-%m-%d %H:%M:%S')
START_EPOCH=$(date +%s)
echo "=== PBS Backup started at ${START_TS} ==="

scan_source() {
    local src="$1"
    local count size
    count=$(find "${src}" -type f \
        ! -path '*/lost+found/*' \
        ! -path '*/node_modules/*' \
        ! -path '*/.cache/*' \
        2>/dev/null | wc -l)
    size=$(du -sh "${src}" 2>/dev/null | awk '{print $1}')
    echo "Source ${src}: ${count} files, ${size} total"
}

scan_source /root
scan_source /home/claude

proxmox-backup-client backup \
    root.pxar:/root \
    home.pxar:/home/claude \
    --repository "${PBS_REPOSITORY}" \
    --backup-id "${BACKUP_ID}" \
    --exclude 'lost+found' \
    --exclude 'node_modules' \
    --exclude '.cache'

RESULT=$?
END_TS=$(date '+%Y-%m-%d %H:%M:%S')
END_EPOCH=$(date +%s)
ELAPSED=$((END_EPOCH - START_EPOCH))
ELAPSED_FMT=$(printf '%dh%02dm%02ds' $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60)))

if [ ${RESULT} -eq 0 ]; then
    echo "=== PBS Backup completed successfully at ${END_TS} ==="
    echo "Elapsed time:  ${ELAPSED_FMT} (${ELAPSED}s)"

    echo "=== Pruning old snapshots ==="
    proxmox-backup-client prune "host/${BACKUP_ID}" \
        --repository "${PBS_REPOSITORY}" \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 6 || true
else
    echo "=== PBS Backup FAILED at ${END_TS} (exit code: ${RESULT}) ==="
    echo "Elapsed time:  ${ELAPSED_FMT} (${ELAPSED}s)"
fi

exit ${RESULT}
