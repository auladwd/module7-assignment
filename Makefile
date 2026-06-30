# =============================================================================
# Makefile — Module 7 Assignment Helper Commands
# Usage: make <target>
# =============================================================================

.PHONY: help up down restart logs test build push deploy status clean

# Default target
help:
	@echo ""
	@echo "  Module 7 - Available Commands"
	@echo "  ─────────────────────────────────────────────"
	@echo "  make up          → Start all services (production)"
	@echo "  make dev         → Start in development mode"
	@echo "  make down        → Stop all services"
	@echo "  make restart     → Restart all services"
	@echo "  make logs        → Tail all container logs"
	@echo "  make logs-app    → Tail app logs only"
	@echo "  make test        → Run unit tests"
	@echo "  make build       → Build Docker image locally"
	@echo "  make status      → Show container status"
	@echo "  make health      → Check app health"
	@echo "  make backup      → Backup database"
	@echo "  make clean       → Remove containers + volumes (DANGER!)"
	@echo ""

# ─── Services ─────────────────────────────────────────────────────────────────
up:
	docker compose up -d
	@echo "✅ All services started"
	@make status

dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up

down:
	docker compose down
	@echo "🛑 All services stopped"

restart:
	docker compose restart
	@echo "🔄 All services restarted"

# ─── Logs ─────────────────────────────────────────────────────────────────────
logs:
	docker compose logs -f --tail=50

logs-app:
	docker compose logs -f --tail=100 app

logs-nginx:
	docker compose logs -f --tail=50 nginx

# ─── Testing ──────────────────────────────────────────────────────────────────
test:
	cd app && npm test

test-watch:
	cd app && npm test -- --watch

# ─── Docker ───────────────────────────────────────────────────────────────────
build:
	docker compose build --no-cache app

pull:
	docker compose pull

# ─── Status & Health ──────────────────────────────────────────────────────────
status:
	@docker compose ps

health:
	@echo "Checking services..."
	@curl -sf http://localhost/health && echo " → App: ✅ UP" || echo " → App: ❌ DOWN"
	@curl -sf http://localhost:9090/-/ready && echo " → Prometheus: ✅ UP" || echo " → Prometheus: ❌ DOWN"
	@curl -sf http://localhost:3001/api/health && echo " → Grafana: ✅ UP" || echo " → Grafana: ❌ DOWN"
	@curl -sf http://localhost:9100/metrics > /dev/null && echo " → Node Exporter: ✅ UP" || echo " → Node Exporter: ❌ DOWN"

# ─── Database ─────────────────────────────────────────────────────────────────
db-shell:
	docker exec -it postgres_db psql -U $${DB_USER:-appuser} -d $${DB_NAME:-appdb}

backup:
	bash scripts/backup-db.sh

# ─── Cleanup ──────────────────────────────────────────────────────────────────
clean:
	@echo "⚠️  This will DELETE all containers and volumes!"
	@read -p "Are you sure? (yes/N): " confirm && [ "$$confirm" = "yes" ] || exit 1
	docker compose down -v --remove-orphans
	docker image prune -f
	@echo "🧹 Cleanup complete"
