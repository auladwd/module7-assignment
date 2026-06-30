# Module 7 Assignment — Backend Deployment with Observability Stack

> **Deploy a backend application with PostgreSQL on AWS EC2, automate deployment via GitHub Actions, and implement a full observability stack using Prometheus, Grafana, and Node Exporter.**

---

## Architecture Overview

```
Internet
   │
   ▼
┌──────────────────────────────────────────────────────────┐
│                    AWS EC2 (Ubuntu 22.04)                 │
│                                                           │
│  ┌─────────┐    ┌──────────┐    ┌────────────────────┐  │
│  │  Nginx  │───▶│  App     │───▶│   PostgreSQL DB     │  │
│  │  :80    │    │  :3000   │    │      :5432          │  │
│  └─────────┘    └──────────┘    └────────────────────┘  │
│                      │                                    │
│          ┌───────────┼───────────┐                       │
│          ▼           ▼           ▼                       │
│  ┌─────────────┐ ┌────────┐ ┌──────────────┐           │
│  │Node Exporter│ │Prometheus│ │   Grafana    │           │
│  │   :9100     │ │  :9090  │ │    :3001     │           │
│  └─────────────┘ └────────┘ └──────────────┘           │
│                       │                                   │
│                ┌──────────────┐                           │
│                │ Alertmanager │──▶ Email (SMTP)           │
│                │    :9093     │                           │
│                └──────────────┘                           │
└──────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
module7-assignment/
├── .github/
│   └── workflows/
│       └── ci-cd.yml              # GitHub Actions CI/CD pipeline
├── app/
│   ├── index.js                   # Express.js backend + Prometheus metrics
│   ├── index.test.js              # Jest unit tests
│   ├── package.json
│   └── Dockerfile                 # Multi-stage Docker build
├── nginx/
│   └── nginx.conf                 # Reverse proxy + rate limiting
├── prometheus/
│   ├── prometheus.yml             # Scrape configs
│   ├── alert.rules.yml            # CPU/RAM/Disk/Network alert rules
│   └── alertmanager.yml           # SMTP email alert routing
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       │   └── datasource.yml     # Auto-configure Prometheus datasource
│       └── dashboards/
│           ├── dashboards.yml     # Dashboard loader config
│           └── system-dashboard.json  # Pre-built system dashboard
├── scripts/
│   ├── setup-ec2.sh              # One-time EC2 server setup
│   ├── health-check.sh           # Cron-based health monitoring
│   └── backup-db.sh              # Automated DB backup
├── docker-compose.yml             # All services
├── docker-compose.dev.yml         # Local dev overrides
├── Makefile                       # Helper commands
├── .env.example                   # Environment variable template
└── .gitignore
```

---

## Step-by-Step Deployment Guide

### Step 1 — Launch EC2 Instance

1. Go to **AWS Console → EC2 → Launch Instance**
2. Choose:
   - **AMI:** Ubuntu Server 22.04 LTS (64-bit)
   - **Instance type:** `t2.micro` (free tier) or `t3.small` (recommended)
   - **Key pair:** Create or select an existing `.pem` key
3. **Security Group — open these ports:**

| Port | Protocol | Source    | Purpose           |
|------|----------|-----------|-------------------|
| 22   | TCP      | Your IP   | SSH               |
| 80   | TCP      | 0.0.0.0/0 | HTTP (Nginx)      |
| 443  | TCP      | 0.0.0.0/0 | HTTPS             |
| 9090 | TCP      | Your IP   | Prometheus        |
| 3001 | TCP      | Your IP   | Grafana           |
| 9093 | TCP      | Your IP   | Alertmanager      |
| 9100 | TCP      | Your IP   | Node Exporter     |

4. **Storage:** minimum 20 GB

---

### Step 2 — Initial EC2 Server Setup

SSH into your instance:

```bash
chmod 400 your-key.pem
ssh -i your-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
```

Run the setup script:

```bash
# Clone your repo (or copy setup script)
curl -o setup-ec2.sh https://raw.githubusercontent.com/YOUR_USERNAME/module7-assignment/main/scripts/setup-ec2.sh

chmod +x setup-ec2.sh
sudo ./setup-ec2.sh
```

This installs: Docker, Docker Compose, UFW firewall, and system tuning.

**Log out and back in** to apply docker group membership:

```bash
exit
ssh -i your-key.pem ubuntu@YOUR_EC2_PUBLIC_IP
docker ps   # Should work without sudo
```

---

### Step 3 — Configure GitHub Repository Secrets

Go to your GitHub repo → **Settings → Secrets and variables → Actions → New repository secret**

Add these secrets:

| Secret Name             | Value                          |
|-------------------------|--------------------------------|
| `EC2_HOST`              | Your EC2 Public IP             |
| `EC2_SSH_KEY`           | Content of your `.pem` file    |
| `DOCKERHUB_USERNAME`    | Your Docker Hub username       |
| `DOCKERHUB_TOKEN`       | Docker Hub access token        |
| `DB_NAME`               | `appdb`                        |
| `DB_USER`               | `appuser`                      |
| `DB_PASSWORD`           | Strong password                |
| `GRAFANA_ADMIN_USER`    | `admin`                        |
| `GRAFANA_ADMIN_PASSWORD`| Strong password                |
| `SMTP_HOST`             | `smtp.gmail.com:587`           |
| `SMTP_USER`             | `your@gmail.com`               |
| `SMTP_PASSWORD`         | Gmail App Password (16 chars)  |
| `SMTP_FROM`             | `your@gmail.com`               |
| `ALERT_EMAIL`           | Where to send alerts           |

**How to get Gmail App Password:**
1. Enable 2-Factor Authentication on your Google account
2. Go to [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
3. Create a new App Password → select "Mail" → copy the 16-character code

---

### Step 4 — Deploy

Push to `main` branch — GitHub Actions handles everything automatically:

```bash
git add .
git commit -m "feat: initial deployment"
git push origin main
```

**CI/CD Pipeline runs 4 jobs:**

```
┌─────────┐    ┌─────────┐    ┌──────────┐    ┌─────────────┐
│  Test   │───▶│  Build  │───▶│  Deploy  │───▶│ Smoke Test  │
│ (Jest)  │    │(Docker) │    │ (EC2 SSH)│    │(API checks) │
└─────────┘    └─────────┘    └──────────┘    └─────────────┘
```

---

### Step 5 — Manual Deployment (Alternative)

If you want to deploy manually without GitHub Actions:

```bash
# On your local machine
rsync -avz --exclude='.git' --exclude='node_modules' \
  ./ ubuntu@YOUR_EC2_IP:~/module7/

# SSH into EC2
ssh ubuntu@YOUR_EC2_IP

cd ~/module7

# Copy and fill environment variables
cp .env.example .env
nano .env   # Fill in your values

# Start all services
docker compose up -d

# Check status
docker compose ps
```

---

### Step 6 — Setup Cron Jobs on EC2

```bash
crontab -e
```

Add these lines:

```cron
# Health check every 5 minutes
*/5 * * * * /home/ubuntu/module7/scripts/health-check.sh

# Database backup daily at 2 AM
0 2 * * * /home/ubuntu/module7/scripts/backup-db.sh
```

---

## Accessing the Services

After deployment, access everything at your EC2 Public IP:

| Service       | URL                              | Credentials            |
|---------------|----------------------------------|------------------------|
| **API**       | `http://YOUR_EC2_IP/`            | —                      |
| **Health**    | `http://YOUR_EC2_IP/health`      | —                      |
| **Prometheus**| `http://YOUR_EC2_IP:9090`        | —                      |
| **Grafana**   | `http://YOUR_EC2_IP:3001`        | admin / your password  |
| **Alertmanager**| `http://YOUR_EC2_IP:9093`      | —                      |

---

## API Endpoints

| Method   | Endpoint      | Description          | Body                    |
|----------|---------------|----------------------|-------------------------|
| `GET`    | `/`           | API info             | —                       |
| `GET`    | `/health`     | Health + DB status   | —                       |
| `GET`    | `/metrics`    | Prometheus metrics   | —                       |
| `GET`    | `/users`      | List all users       | —                       |
| `POST`   | `/users`      | Create a user        | `{name, email}`         |
| `GET`    | `/users/:id`  | Get user by ID       | —                       |
| `DELETE` | `/users/:id`  | Delete user          | —                       |

**Example requests:**

```bash
# Create a user
curl -X POST http://YOUR_EC2_IP/users \
  -H "Content-Type: application/json" \
  -d '{"name": "Alice", "email": "alice@example.com"}'

# Get all users
curl http://YOUR_EC2_IP/users

# Health check
curl http://YOUR_EC2_IP/health
```

---

## Observability Stack

### Prometheus Metrics Collected

| Category     | Metrics                                    |
|--------------|--------------------------------------------|
| **CPU**      | Usage %, per-core breakdown, idle time     |
| **Memory**   | Used, available, cached, swap              |
| **Disk**     | Usage %, read/write IOPS, space per mount  |
| **Network**  | Bytes in/out per interface, error rates    |
| **App**      | HTTP requests/sec, response time, errors   |

### Alert Rules

| Alert                  | Condition              | Severity  |
|------------------------|------------------------|-----------|
| HighCPUUsage           | CPU > 80% for 5min     | Warning   |
| CriticalCPUUsage       | CPU > 95% for 2min     | Critical  |
| HighMemoryUsage        | RAM > 80% for 5min     | Warning   |
| CriticalMemoryUsage    | RAM > 95% for 2min     | Critical  |
| HighDiskUsage          | Disk > 80% for 5min    | Warning   |
| CriticalDiskUsage      | Disk > 90% for 2min    | Critical  |
| HighNetworkTrafficIn   | >100 MB/s for 5min     | Warning   |
| AppDown                | App unreachable 1min   | Critical  |
| HighHTTPErrorRate      | 5xx > 5% for 5min      | Warning   |
| SlowAPIResponse        | p95 > 2s for 5min      | Warning   |

### Grafana Dashboard Panels

1. **CPU Usage %** — Gauge with green/yellow/red thresholds
2. **Memory Usage %** — Gauge
3. **Disk Usage %** — Gauge
4. **App Status** — UP/DOWN stat panel
5. **CPU Over Time** — Time series graph
6. **Memory Over Time** — Used vs Available
7. **Network I/O** — Bytes in/out per second
8. **HTTP Requests/sec** — By route and status code

---

## Email Alert Setup (SMTP Bonus)

Email alerts are sent via **Alertmanager** using SMTP when:
- CPU > 80% (Warning) or > 95% (Critical)
- RAM > 80% (Warning) or > 95% (Critical)
- Disk > 80% (Warning) or > 90% (Critical)
- Application goes down
- High HTTP error rate

Critical alerts repeat every **1 hour**. Warning alerts repeat every **4 hours**.

To test alerts manually:

```bash
# Trigger a test alert via Alertmanager API
curl -X POST http://YOUR_EC2_IP:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname": "TestAlert", "severity": "warning"},
    "annotations": {"summary": "Test alert", "description": "This is a test"}
  }]'
```

---

## Useful Commands

```bash
# View all running containers
make status

# Check all service health
make health

# View application logs
make logs-app

# Access database shell
make db-shell

# Backup database now
make backup

# Restart everything
make restart

# Stop everything
make down
```

---

## Local Development

```bash
# Clone repo
git clone https://github.com/YOUR_USERNAME/module7-assignment.git
cd module7-assignment

# Copy and configure env
cp .env.example .env

# Start in dev mode (hot-reload enabled)
make dev

# Run tests
make test
```

---

## Troubleshooting

**Container not starting?**
```bash
docker compose logs <service-name>
docker compose ps
```

**Cannot connect to DB?**
```bash
docker exec -it postgres_db pg_isready -U appuser
docker compose restart postgres
```

**Prometheus not scraping?**
```bash
# Check targets in browser
http://YOUR_EC2_IP:9090/targets

# Reload Prometheus config
curl -X POST http://localhost:9090/-/reload
```

**Email alerts not arriving?**
```bash
# Check Alertmanager logs
docker compose logs alertmanager

# Verify SMTP settings in .env
cat .env | grep SMTP
```

---

## Technologies Used

| Tool              | Purpose                              |
|-------------------|--------------------------------------|
| Node.js + Express | Backend REST API                     |
| PostgreSQL         | Relational database                  |
| Docker + Compose  | Containerization                     |
| Nginx             | Reverse proxy + rate limiting        |
| Prometheus        | Metrics collection + alerting rules  |
| Grafana           | Metrics visualization dashboards     |
| Node Exporter     | OS-level metrics (CPU/RAM/Disk/Net)  |
| Alertmanager      | Alert routing + SMTP email delivery  |
| GitHub Actions    | CI/CD automation pipeline            |
| AWS EC2           | Cloud hosting (Ubuntu 22.04)         |
