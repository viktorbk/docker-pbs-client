#!/usr/bin/env node

const readline = require("readline");
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
});

function ask(question, defaultVal) {
  const suffix = defaultVal ? ` [${defaultVal}]` : "";
  return new Promise((resolve) => {
    rl.question(`${question}${suffix}: `, (answer) => {
      resolve(answer.trim() || defaultVal || "");
    });
  });
}

function writeFile(name, content) {
  const dest = path.join(process.cwd(), name);
  fs.writeFileSync(dest, content);
  console.log(`  Created ${name}`);
}

// --- Templates ---

const DOCKERFILE = `FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Install minimal dependencies + proxmox-backup-client
# Note: Proxmox only publishes amd64 packages. On Apple Silicon,
# set platform: linux/amd64 in docker-compose.yml (uses Rosetta emulation)
RUN apt-get update && \\
    apt-get install -y --no-install-recommends \\
        ca-certificates \\
        wget \\
        gnupg \\
        cron \\
    && wget -qO /usr/share/keyrings/proxmox-release-bookworm.gpg \\
        https://enterprise.proxmox.com/debian/proxmox-release-bookworm.gpg \\
    && echo "deb [signed-by=/usr/share/keyrings/proxmox-release-bookworm.gpg] http://download.proxmox.com/debian/pbs-client bookworm main" \\
        > /etc/apt/sources.list.d/pbs-client.list \\
    && apt-get update \\
    && apt-get install -y --no-install-recommends proxmox-backup-client \\
    && apt-get purge -y --auto-remove wget gnupg \\
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/.config/proxmox-backup

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

CMD ["cron", "-f"]
`;

function makeCompose(volumes, hostname, cron, tz, needsAmd64) {
  const volumeLines = volumes
    .map((v) => `      - ${v.host}:/backup-source/${v.name}:ro`)
    .join("\n");

  const platformLine = needsAmd64 ? "\n    platform: linux/amd64" : "";

  return `services:
  pbs-client:
    build: .${platformLine}
    container_name: pbs-client
    restart: unless-stopped
    hostname: ${hostname}
    environment:
      - PBS_REPOSITORY=\${PBS_USER}@\${PBS_SERVER}:\${PBS_DATASTORE}
      - PBS_PASSWORD=\${PBS_PASSWORD}
      - PBS_FINGERPRINT=\${PBS_FINGERPRINT}
      - XDG_RUNTIME_DIR=/run/pbs
      - BACKUP_CRON=\${BACKUP_CRON:-${cron}}
      - TZ=\${TZ:-${tz}}
    volumes:
${volumeLines}
      # Persistent PBS client config (encryption keys, auth)
      - pbs-config:/root/.config/proxmox-backup
      # Backup logs
      - pbs-logs:/var/log/pbs-backup
    entrypoint: >
      /bin/sh -c "
        mkdir -p /var/log/pbs-backup &&
        mkdir -p /run/pbs && chmod 700 /run/pbs &&
        env | grep -E '^(PBS_|XDG_|TZ=)' > /etc/environment &&
        echo \\"\\$\\$BACKUP_CRON . /etc/environment; /usr/local/bin/backup.sh >> /var/log/pbs-backup/backup.log 2>&1\\" | crontab - &&
        cron -f
      "

volumes:
  pbs-config:
  pbs-logs:
`;
}

function makeBackupScript(volumes, hostname, excludes) {
  const archives = volumes
    .map((v) => `    ${v.name}.pxar:/backup-source/${v.name} \\`)
    .join("\n");

  const excludeLines = excludes
    .map((e, i) => i < excludes.length - 1
      ? `    --exclude '${e}' \\`
      : `    --exclude '${e}'`)
    .join("\n");

  return `#!/bin/bash
set -uo pipefail

START_TS=$(date '+%Y-%m-%d %H:%M:%S')
START_EPOCH=$(date +%s)
echo "=== PBS Backup started at \${START_TS} ==="

proxmox-backup-client backup \\
${archives}
    --repository "\${PBS_REPOSITORY}" \\
    --backup-id ${hostname} \\
${excludeLines}

RESULT=$?
END_TS=$(date '+%Y-%m-%d %H:%M:%S')
END_EPOCH=$(date +%s)
ELAPSED=$((END_EPOCH - START_EPOCH))
ELAPSED_FMT=$(printf '%dh%02dm%02ds' $((ELAPSED/3600)) $((ELAPSED%3600/60)) $((ELAPSED%60)))

if [ \${RESULT} -eq 0 ]; then
    echo "=== PBS Backup completed successfully at \${END_TS} ==="
    echo "Elapsed time:  \${ELAPSED_FMT} (\${ELAPSED}s)"

    echo "=== Pruning old snapshots ==="
    proxmox-backup-client prune host/${hostname} \\
        --repository "\${PBS_REPOSITORY}" \\
        --keep-daily 7 \\
        --keep-weekly 4 \\
        --keep-monthly 6 || true
else
    echo "=== PBS Backup FAILED at \${END_TS} (exit code: \${RESULT}) ==="
    echo "Elapsed time:  \${ELAPSED_FMT} (\${ELAPSED}s)"
fi

exit \${RESULT}
`;
}

function makeEnv(server, user, password, datastore, fingerprint, cron, tz) {
  return `# Proxmox Backup Server connection
PBS_SERVER=${server}
PBS_USER=${user}
PBS_PASSWORD=${password}
PBS_DATASTORE=${datastore}
PBS_FINGERPRINT=${fingerprint}

# Backup schedule (cron format)
BACKUP_CRON=${cron}

# Timezone
TZ=${tz}
`;
}

const DEFAULT_EXCLUDES = [
  "lost+found",
  ".DS_Store",
  ".Spotlight-V100",
  ".fseventsd",
  ".Trashes",
  ".TemporaryItems",
  ".DocumentRevisions-V100",
  ".bzvol",
  "node_modules",
];

const GITIGNORE = `.env
`;

// --- Main ---

async function main() {
  console.log("\n  Docker PBS Client Setup\n");

  // PBS server details
  const server = await ask("PBS server (ip:port)", "192.168.1.100:8007");
  const user = await ask("PBS user", "root@pam");
  const password = await ask("PBS password");
  const datastore = await ask("PBS datastore", "main");
  const fingerprint = await ask(
    "PBS fingerprint (from PBS Dashboard or: proxmox-backup-manager cert info)"
  );

  // Backup sources
  console.log(
    "\n  Add directories to back up. Enter an empty path when done.\n"
  );
  const volumes = [];
  while (true) {
    const hostPath = await ask("  Host path to back up (empty to finish)");
    if (!hostPath) break;
    const defaultName = path.basename(hostPath).toLowerCase().replace(/[^a-z0-9]/g, "");
    const name = await ask("  Archive name", defaultName);
    volumes.push({ host: hostPath, name });
    console.log("");
  }

  if (volumes.length === 0) {
    console.log("No backup sources added. Adding a placeholder.");
    volumes.push({ host: "/path/to/data", name: "data" });
  }

  // Excludes
  console.log(`\n  Default excludes: ${DEFAULT_EXCLUDES.join(", ")}`);
  const editExcludes = await ask("  Edit exclude list? (y/n)", "n");
  let excludes = [...DEFAULT_EXCLUDES];
  if (editExcludes.toLowerCase() === "y") {
    const addMore = await ask("  Additional excludes (comma-separated, empty to skip)");
    if (addMore) {
      excludes.push(...addMore.split(",").map((s) => s.trim()).filter(Boolean));
    }
    const remove = await ask("  Remove any excludes? (comma-separated, empty to skip)");
    if (remove) {
      const toRemove = remove.split(",").map((s) => s.trim());
      excludes = excludes.filter((e) => !toRemove.includes(e));
    }
    console.log(`  Final excludes: ${excludes.join(", ")}`);
  }

  // Platform detection
  const arch = process.arch; // "arm64" on Apple Silicon, "x64" on Intel
  let needsAmd64 = arch === "arm64";
  if (needsAmd64) {
    console.log(`\n  Detected ARM64 (Apple Silicon). Proxmox only publishes amd64 packages.`);
    console.log(`  The container will run via Rosetta emulation.`);
    console.log(`  Make sure Rosetta is enabled: Docker Desktop > Settings > General > "Use Rosetta"`);
    const confirm = await ask("  Add platform: linux/amd64 to docker-compose.yml? (y/n)", "y");
    needsAmd64 = confirm.toLowerCase() !== "n";
  }

  // Options
  const hostname = await ask("\nBackup hostname (shows in PBS UI)", "macbackup");
  const cron = await ask("Backup schedule (cron)", "0 2 * * *");
  const tz = await ask("Timezone", "Europe/Oslo");

  // Generate files
  console.log("\nGenerating files...\n");

  writeFile("Dockerfile", DOCKERFILE);
  writeFile("docker-compose.yml", makeCompose(volumes, hostname, cron, tz, needsAmd64));
  writeFile("backup.sh", makeBackupScript(volumes, hostname, excludes));
  writeFile(".env", makeEnv(server, user, password, datastore, fingerprint, cron, tz));
  writeFile(".env.example", makeEnv(server, user, "your-password-here", datastore, "AA:BB:CC:...", cron, tz));
  writeFile(".gitignore", GITIGNORE);

  console.log("\nDone! Next steps:\n");
  console.log("  docker compose up -d --build");
  console.log("  docker compose exec pbs-client proxmox-backup-client snapshot list");
  console.log("  docker compose exec pbs-client /usr/local/bin/backup.sh\n");

  const start = await ask("Start the container now? (y/n)", "n");
  if (start.toLowerCase() === "y") {
    console.log("\nBuilding and starting...\n");
    try {
      execSync("docker compose up -d --build", { stdio: "inherit" });
      console.log("\nContainer is running!");
    } catch {
      console.error("\nFailed to start. Check Docker is running and try: docker compose up -d --build");
    }
  }

  rl.close();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
