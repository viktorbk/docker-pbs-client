FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal dependencies + proxmox-backup-client
# Note: Proxmox only publishes amd64 packages. On Apple Silicon,
# set platform: linux/amd64 in docker-compose.yml (uses Rosetta emulation)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        gnupg \
        cron \
    && wget -qO /usr/share/keyrings/proxmox-release-bookworm.gpg \
        https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/proxmox-release-bookworm.gpg] http://download.proxmox.com/debian/pbs-client bookworm main" \
        > /etc/apt/sources.list.d/pbs-client.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends proxmox-backup-client \
    && apt-get purge -y --auto-remove wget gnupg \
    && rm -rf /var/lib/apt/lists/*

# Create config directory for PBS client
RUN mkdir -p /root/.config/proxmox-backup

# Copy backup script
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Run cron in foreground
CMD ["cron", "-f"]
