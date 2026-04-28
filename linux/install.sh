#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "install.sh must be run as root" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KEYRING=/usr/share/keyrings/proxmox-release-bookworm.gpg
SOURCES=/etc/apt/sources.list.d/pbs-client.list
ENV_FILE=/etc/pbs-backup.env

if ! command -v proxmox-backup-client >/dev/null 2>&1; then
    echo "==> Installing proxmox-backup-client"
    apt-get update
    apt-get install -y --no-install-recommends ca-certificates wget gnupg
    if [ ! -f "${KEYRING}" ]; then
        wget -qO "${KEYRING}" \
            https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg
    fi
    if [ ! -f "${SOURCES}" ]; then
        echo "deb [signed-by=${KEYRING}] http://download.proxmox.com/debian/pbs-client bookworm main" \
            > "${SOURCES}"
    fi
    apt-get update
    apt-get install -y --no-install-recommends proxmox-backup-client
else
    echo "==> proxmox-backup-client already installed: $(proxmox-backup-client --version | head -1)"
fi

echo "==> Installing backup script and systemd units"
install -m 0755 "${SCRIPT_DIR}/backup.sh" /usr/local/bin/pbs-backup.sh
install -m 0644 "${SCRIPT_DIR}/pbs-backup.service" /etc/systemd/system/pbs-backup.service
install -m 0644 "${SCRIPT_DIR}/pbs-backup.timer" /etc/systemd/system/pbs-backup.timer

if [ ! -f "${ENV_FILE}" ]; then
    REPO_ENV="$(dirname "${SCRIPT_DIR}")/.env"
    if [ -f "${REPO_ENV}" ]; then
        echo "==> Found ${REPO_ENV}, copying to ${ENV_FILE}"
        install -m 0600 "${REPO_ENV}" "${ENV_FILE}"
    else
        install -m 0600 "${SCRIPT_DIR}/pbs-backup.env.example" "${ENV_FILE}"
        cat <<EOF

==> ${ENV_FILE} created from example.
    Edit it with your real PBS credentials, then re-run:
        sudo bash ${SCRIPT_DIR}/install.sh

    The timer is NOT enabled until you do this.
EOF
        exit 0
    fi
fi

echo "==> Enabling and starting pbs-backup.timer"
systemctl daemon-reload
systemctl enable --now pbs-backup.timer

echo
systemctl list-timers pbs-backup.timer --no-pager
echo
echo "Done. Run a backup on demand with:"
echo "    sudo systemctl start pbs-backup.service"
echo "Tail logs with:"
echo "    journalctl -u pbs-backup.service -f"
