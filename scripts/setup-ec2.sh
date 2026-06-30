#!/bin/bash
# =============================================================================
# EC2 Server Initial Setup Script
# Ubuntu 22.04 LTS — Run once after launching your EC2 instance
# Usage: chmod +x setup-ec2.sh && sudo ./setup-ec2.sh
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✔] $1${NC}"; }
warn()    { echo -e "${YELLOW}[!] $1${NC}"; }
error()   { echo -e "${RED}[✘] $1${NC}"; exit 1; }
section() { echo -e "\n${BLUE}━━━ $1 ━━━${NC}"; }

# ─── Must run as root ─────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || error "Please run as root: sudo ./setup-ec2.sh"

section "1. System Update"
apt-get update -y && apt-get upgrade -y
apt-get install -y curl wget git htop unzip ufw net-tools
log "System packages updated"

section "2. Install Docker"
# Remove old versions
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Install dependencies
apt-get install -y ca-certificates gnupg lsb-release

# Add Docker's official GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repo
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start & enable Docker
systemctl enable docker
systemctl start docker

# Add ubuntu user to docker group (no sudo needed)
usermod -aG docker ubuntu
log "Docker installed: $(docker --version)"

section "3. Install Docker Compose (standalone)"
COMPOSE_VERSION="2.24.6"
curl -SL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
log "Docker Compose installed: $(docker-compose --version)"

section "4. Configure UFW Firewall"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow SSH (critical - must be first!)
ufw allow 22/tcp comment "SSH"

# Application ports
ufw allow 80/tcp   comment "HTTP - Nginx"
ufw allow 443/tcp  comment "HTTPS - Nginx"
ufw allow 9090/tcp comment "Prometheus"
ufw allow 3001/tcp comment "Grafana"
ufw allow 9093/tcp comment "Alertmanager"
ufw allow 9100/tcp comment "Node Exporter"

ufw --force enable
log "Firewall configured"
ufw status verbose

section "5. Create Project Directory"
mkdir -p /home/ubuntu/module7
chown -R ubuntu:ubuntu /home/ubuntu/module7
log "Project directory ready: /home/ubuntu/module7"

section "6. Configure System for Observability"
# Increase file descriptors for Prometheus
cat >> /etc/sysctl.conf << 'EOF'

# Module 7 - Observability tuning
fs.file-max = 65536
vm.max_map_count = 262144
net.core.somaxconn = 65535
EOF
sysctl -p
log "System tuning applied"

# Set ulimits for Docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF
systemctl restart docker
log "Docker daemon configured"

section "7. Setup Logrotate"
cat > /etc/logrotate.d/docker-containers << 'EOF'
/var/lib/docker/containers/*/*.log {
  rotate 7
  daily
  compress
  missingok
  delaycompress
  copytruncate
}
EOF
log "Log rotation configured"

section "8. Create Deployment Helper Script"
cat > /home/ubuntu/deploy.sh << 'DEPLOY'
#!/bin/bash
# Quick redeploy script — run on EC2 to pull and restart
set -e
cd ~/module7
echo "🔄 Pulling latest images..."
docker compose pull
echo "🚀 Restarting services..."
docker compose up -d --remove-orphans
echo "🧹 Cleaning old images..."
docker image prune -f
echo "✅ Deployment complete!"
docker compose ps
DEPLOY
chmod +x /home/ubuntu/deploy.sh
chown ubuntu:ubuntu /home/ubuntu/deploy.sh
log "Deploy helper script created at ~/deploy.sh"

section "✅ Setup Complete!"
echo ""
echo -e "${GREEN}EC2 is ready! Next steps:${NC}"
echo "  1. Log out and back in (for docker group to take effect)"
echo "  2. Copy your project:  rsync -avz ./ ubuntu@YOUR_IP:~/module7/"
echo "  3. Create .env file:   nano ~/module7/.env"
echo "  4. Start services:     cd ~/module7 && docker compose up -d"
echo ""
echo -e "${YELLOW}Access URLs (replace YOUR_EC2_IP):${NC}"
echo "  🌐 App:          http://YOUR_EC2_IP"
echo "  📊 Prometheus:   http://YOUR_EC2_IP:9090"
echo "  📈 Grafana:      http://YOUR_EC2_IP:3001"
echo "  🔔 Alertmanager: http://YOUR_EC2_IP:9093"
