#!/bin/bash
# =============================================================================
# PostgreSQL Backup Script
# Dumps the database and optionally uploads to S3
# Crontab: 0 2 * * * /home/ubuntu/module7/scripts/backup-db.sh
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
BACKUP_FILE="$BACKUP_DIR/db_backup_${TIMESTAMP}.sql.gz"
LOG="$PROJECT_DIR/logs/backup.log"

[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"

DB_NAME="${DB_NAME:-appdb}"
DB_USER="${DB_USER:-appuser}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
S3_BUCKET="${S3_BUCKET:-}"   # optional — set in .env

mkdir -p "$BACKUP_DIR" "$PROJECT_DIR/logs"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"; }

log "=== Starting DB Backup ==="

# Dump database from running container
docker exec postgres_db pg_dump -U "$DB_USER" "$DB_NAME" \
  | gzip > "$BACKUP_FILE"

SIZE=$(du -sh "$BACKUP_FILE" | cut -f1)
log "✅ Backup created: $BACKUP_FILE ($SIZE)"

# Optional: Upload to S3
if [ -n "$S3_BUCKET" ]; then
  aws s3 cp "$BACKUP_FILE" "s3://${S3_BUCKET}/database-backups/" \
    && log "✅ Uploaded to S3: s3://${S3_BUCKET}/database-backups/" \
    || log "⚠️  S3 upload failed"
fi

# Remove old backups
find "$BACKUP_DIR" -name "db_backup_*.sql.gz" -mtime +$RETENTION_DAYS -delete
log "🧹 Removed backups older than $RETENTION_DAYS days"

# List current backups
log "📦 Current backups:"
ls -lh "$BACKUP_DIR"/*.sql.gz 2>/dev/null | tee -a "$LOG" || log "No backups found"

log "=== Backup Complete ==="
