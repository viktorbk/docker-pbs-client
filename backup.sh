#!/bin/bash
set -uo pipefail

SOURCE=/backup-source/home
START_TS=$(date '+%Y-%m-%d %H:%M:%S')
START_EPOCH=$(date +%s)
echo "=== PBS Backup started at ${START_TS} ==="

# Count files and total size in the source directory
echo "Scanning source ${SOURCE} ..."
FILE_COUNT=$(find "${SOURCE}" -type f \
    ! -name '.DS_Store' \
    ! -path '*/node_modules/*' \
    ! -path '*/.Spotlight-V100/*' \
    ! -path '*/.fseventsd/*' \
    ! -path '*/.Trashes/*' \
    ! -path '*/.TemporaryItems/*' \
    ! -path '*/.DocumentRevisions-V100/*' \
    ! -path '*/.bzvol/*' \
    2>/dev/null | wc -l)
SOURCE_SIZE=$(du -sh "${SOURCE}" 2>/dev/null | awk '{print $1}')
echo "Source: ${FILE_COUNT} files, ${SOURCE_SIZE} total"

# Back up mounted sources as .pxar archives
# Update the archive names and paths to match your docker-compose.yml volume mounts.
proxmox-backup-client backup \
    home.pxar:"${SOURCE}" \
    --repository "${PBS_REPOSITORY}" \
    --backup-id macbackup \
    --exclude 'lost+found' \
    --exclude '.DS_Store' \
    --exclude '.Spotlight-V100' \
    --exclude '.fseventsd' \
    --exclude '.Trashes' \
    --exclude '.TemporaryItems' \
    --exclude '.DocumentRevisions-V100' \
    --exclude '.bzvol' \
    --exclude 'node_modules'

RESULT=$?
END_TS=$(date '+%Y-%m-%d %H:%M:%S')
END_EPOCH=$(date +%s)
ELAPSED=$((END_EPOCH - START_EPOCH))
ELAPSED_FMT=$(printf '%dh%02dm%02ds' $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60)))

if [ ${RESULT} -eq 0 ]; then
    echo "=== PBS Backup completed successfully at ${END_TS} ==="
    echo "Files scanned: ${FILE_COUNT}"
    echo "Source size:   ${SOURCE_SIZE}"
    echo "Elapsed time:  ${ELAPSED_FMT} (${ELAPSED}s)"

    # Prune old snapshots
    echo "=== Pruning old snapshots ==="
    proxmox-backup-client prune host/macbackup \
        --repository "${PBS_REPOSITORY}" \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 6 || true
else
    echo "=== PBS Backup FAILED at ${END_TS} (exit code: ${RESULT}) ==="
    echo "Elapsed time:  ${ELAPSED_FMT} (${ELAPSED}s)"
fi

exit ${RESULT}
