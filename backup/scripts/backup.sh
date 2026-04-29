#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Docker Volume Backup Script
# Stops containers, archives volumes, restarts containers.
# Run as root (or with sudo) from the project directory.
#
# Usage:  sudo bash backup/scripts/backup.sh
# Cron:   0 2 * * * /path/to/onlineOffice/backup/scripts/backup.sh >> /var/log/cloud-backup.log 2>&1
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BACKUP_DIR="${PROJECT_DIR}/backup/archives"
DATE=$(date +%Y-%m-%d_%H-%M-%S)
KEEP_DAYS=7

VOLUMES=(
  nextcloud_html
  nextcloud_data
  nextcloud_db
  onlyoffice_data
  vikunja_files
  vikunja_db
  uptime_kuma
  npm_data
  npm_letsencrypt
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

mkdir -p "${BACKUP_DIR}"

log "Starting backup ${DATE}"
cd "${PROJECT_DIR}"

log "Putting Nextcloud into maintenance mode..."
docker compose exec -T nextcloud php occ maintenance:mode --on 2>/dev/null || true

log "Stopping containers (except proxy)..."
docker compose stop nextcloud nextcloud-db nextcloud-redis \
                     onlyoffice vikunja vikunja-db 2>/dev/null || true

for VOL in "${VOLUMES[@]}"; do
  ARCHIVE="${BACKUP_DIR}/${DATE}_${VOL}.tar.gz"
  log "Archiving volume: ${VOL} → ${ARCHIVE}"
  docker run --rm \
    -v "${VOL}:/data:ro" \
    -v "${BACKUP_DIR}:/backup" \
    alpine \
    tar czf "/backup/${DATE}_${VOL}.tar.gz" -C /data .
done

log "Restarting containers..."
docker compose start nextcloud-db nextcloud-redis nextcloud onlyoffice vikunja vikunja-db

log "Disabling Nextcloud maintenance mode..."
docker compose exec -T nextcloud php occ maintenance:mode --off 2>/dev/null || true

log "Removing backups older than ${KEEP_DAYS} days..."
find "${BACKUP_DIR}" -name "*.tar.gz" -mtime "+${KEEP_DAYS}" -delete

log "Backup complete."
