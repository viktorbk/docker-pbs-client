FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install proxmox-backup-client
# On amd64: use the official Proxmox apt repo
# On arm64: build from source (Proxmox only publishes amd64 packages)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates wget cron && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "amd64" ]; then \
        apt-get install -y --no-install-recommends gnupg && \
        wget -qO /usr/share/keyrings/proxmox-release-bookworm.gpg \
            https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg && \
        echo "deb [signed-by=/usr/share/keyrings/proxmox-release-bookworm.gpg] http://download.proxmox.com/debian/pbs-client bookworm main" \
            > /etc/apt/sources.list.d/pbs-client.list && \
        apt-get update && \
        apt-get install -y --no-install-recommends proxmox-backup-client && \
        apt-get purge -y --auto-remove gnupg; \
    elif [ "$ARCH" = "arm64" ]; then \
        apt-get install -y --no-install-recommends \
            build-essential \
            cargo \
            rustc \
            libsgutils2-dev \
            libacl1-dev \
            libfuse3-dev \
            libssl-dev \
            pkg-config \
            git && \
        git clone --depth 1 --branch v3.3.2 https://git.proxmox.com/git/proxmox-backup.git /tmp/pbs && \
        cd /tmp/pbs && \
        cargo build --release --package proxmox-backup-client && \
        cp target/release/proxmox-backup-client /usr/local/bin/ && \
        cd / && rm -rf /tmp/pbs /root/.cargo && \
        apt-get purge -y --auto-remove build-essential cargo rustc \
            libsgutils2-dev libacl1-dev libfuse3-dev libssl-dev pkg-config git; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    apt-get purge -y --auto-remove wget && \
    rm -rf /var/lib/apt/lists/*

# Create config directory for PBS client
RUN mkdir -p /root/.config/proxmox-backup

# Copy backup script
COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

# Run cron in foreground
CMD ["cron", "-f"]
