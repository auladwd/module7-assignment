#!/bin/bash
# =============================================================================
# Health Monitor Script
# Checks all services and sends email if something is down
# Usage: Add to crontab → */5 * * * * /home/ubuntu/module7/scripts/health-check.sh
# =============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$PROJECT_DIR/logs/health-check.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Load env
[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"

ALERT_TO="${ALERT_EMAIL:-admin@yourdomain.com}"
APP_URL="${APP_URL:-http://localhost}"

mkdir -p "$PROJECT_DIR/logs"

log() { echo "[$TIMESTAMP] $1" | tee -a "$LOG_FILE"; }

# ─── Check function ────────────────────────────────────────────────────────────
check_service() {
  local name="$1"
  local url="$2"
  local expected_code="${3:-200}"

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "$expected_code" ]; then
    log "✅ $name is UP (HTTP $HTTP_CODE)"
    return 0
  else
    log "❌ $name is DOWN (HTTP $HTTP_CODE, expected $expected_code)"
    return 1
  fi
}

# ─── Check Docker containers ──────────────────────────────────────────────────
check_container() {
  local name="$1"
  if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    log "✅ Container $name is running"
    return 0
  else
    log "❌ Container $name is NOT running"
    return 1
  fi
}

# ─── Run checks ───────────────────────────────────────────────────────────────
log "=== Starting Health Check ==="

FAILED=0

check_container "backend_app"   || FAILED=1
check_container "postgres_db"   || FAILED=1
check_container "nginx_proxy"   || FAILED=1
check_container "prometheus"    || FAILED=1
check_container "grafana"       || FAILED=1
check_container "node_exporter" || FAILED=1

check_service "App Health"     "$APP_URL/health"   "200" || FAILED=1
check_service "App Root"       "$APP_URL/"          "200" || FAILED=1
check_service "Prometheus"     "http://localhost:9090/-/ready" "200" || FAILED=1
check_service "Grafana"        "http://localhost:3001/api/health" "200" || FAILED=1

# ─── System resource check ────────────────────────────────────────────────────
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d',' -f1 | xargs printf "%.0f")
MEM=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
DISK=$(df / | awk 'NR==2 {print $5}' | tr -d '%')

log "📊 System: CPU=${CPU}% | RAM=${MEM}% | Disk=${DISK}%"

[ "$CPU"  -gt 90 ] && { log "⚠️  CPU critical: ${CPU}%";  FAILED=1; }
[ "$MEM"  -gt 90 ] && { log "⚠️  RAM critical: ${MEM}%";  FAILED=1; }
[ "$DISK" -gt 90 ] && { log "⚠️  Disk critical: ${DISK}%"; FAILED=1; }

# ─── Alert if failed ──────────────────────────────────────────────────────────
if [ "$FAILED" -eq 1 ]; then
  log "🚨 Issues detected — sending alert email..."

  BODY="Health check failed at $TIMESTAMP on $(hostname)\n\n"
  BODY+="CPU: ${CPU}% | RAM: ${MEM}% | Disk: ${DISK}%\n\n"
  BODY+="Check logs: $LOG_FILE\n"
  BODY+="Prometheus: http://$(curl -s ifconfig.me):9090\n"
  BODY+="Grafana:    http://$(curl -s ifconfig.me):3001\n"

  echo -e "Subject: 🚨 [ALERT] Module 7 Health Check Failed\n\n$BODY" \
    | sendmail "$ALERT_TO" 2>/dev/null || log "⚠️  Email send failed (sendmail not configured)"

  # Auto-restart failed containers
  log "🔄 Attempting auto-restart of failed containers..."
  cd "$PROJECT_DIR"
  docker compose up -d --remove-orphans 2>&1 | tee -a "$LOG_FILE"
else
  log "✅ All checks passed"
fi

log "=== Health Check Complete ==="

# Keep only last 1000 lines in log
tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
