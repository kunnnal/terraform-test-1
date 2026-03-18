# 🚀 Nexus App Server — Terraform Infrastructure

A fully automated Terraform setup that provisions a single EC2 instance on AWS with everything your Nexus application needs: **PostgreSQL**, **Neo4j**, **Apache Kafka**, **Python 3.11**, a **process manager** for 6 app services, and an **Nginx reverse proxy** with optional **free TLS via Let's Encrypt**.

---

## 📐 Architecture Overview

```
                        Internet
                           │
                    ┌──────▼──────┐
                    │  AWS EC2    │  (instance_type, Ubuntu 22.04 / Amazon Linux 2023)
                    │             │
                    │  ┌────────┐ │  :80 / :443
                    │  │ Nginx  │◄├───────────────── Browser / API Client
                    │  └───┬────┘ │
                    │      │ proxy_pass
                    │  ┌───▼────────────────────────────────────┐
                    │  │         FastAPI Gateway  :8000          │
                    │  └─┬──────────┬──────────┬────────────────┘
                    │    │          │           │
                    │  ┌─▼──────┐ ┌▼────────┐ ┌▼───────────┐
                    │  │Postgres│ │  Neo4j  │ │   Kafka    │
                    │  │ :5432  │ │:7474    │ │   :9092    │
                    │  └────────┘ │:7687    │ └────────────┘
                    │             └─────────┘
                    │
                    │  6 Background Processes (systemd / supervisord):
                    │   • nexus-gateway          (FastAPI)
                    │   • nexus-calendar-worker
                    │   • nexus-calendar-consumer
                    │   • nexus-email-worker
                    │   • nexus-email-consumer
                    │   • nexus-nudge-agent
                    └─────────────────────────────────────────────────
```

---

## 📁 Project Structure

```
new-instance/
├── main.tf              # EC2, security group, key pair, all outputs
├── variables.tf         # All configurable variables (with defaults + validation)
├── user-data.sh.tlp     # Bash provisioning script (runs once on first boot)
└── Readme.md            # This file
```

---

## ⚙️ How It Works

### 1. `terraform apply` is run
Terraform reads `variables.tf` for your configuration, creates:
- An **AWS Security Group** opening necessary ports
- An **SSH Key Pair** from your local public key
- An **EC2 instance** with the `user-data.sh.tlp` script injected as cloud-init

### 2. EC2 boots and `user-data.sh.tlp` runs automatically
The script runs **once on first boot** and performs these steps in order:

| Step | What happens |
|------|-------------|
| **1** | Creates the `appuser` Linux user with `sudo` access |
| **2** | Installs Java, Python 3.11, PostgreSQL, Neo4j (OS-specific) |
| **3** | Configures Neo4j to listen on `0.0.0.0` (all interfaces) and starts it |
| **4** | Downloads and configures Apache Kafka (KRaft or Zookeeper mode), then creates the `ingestion.calendar` and `ingestion.email` topics |
| **5** | Sets up the PostgreSQL database, user, and permissions |
| **6** | Writes `/home/appuser/.env` with all connection strings |
| **7** | Creates a Python 3.11 virtual environment at `/home/appuser/venv` |
| **8** | Sets up the **process manager** (systemd units or supervisord config) for all 6 app processes |
| **9** | Installs **Nginx** as a reverse proxy (port 80 → 8000), and optionally runs **Certbot** for free TLS |

---

## 🔧 Variables Reference

### Core

| Variable | Default | Description |
|---|---|---|
| `os_choice` | `"ubuntu"` | OS image: `"ubuntu"` (22.04) or `"amazon_linux"` (2023) |
| `java_version` | `"21"` | Java version: `"17"` or `"21"` |
| `ssh_public_key_path` | `"~/.ssh/id_ed25519.pub"` | Path to your local SSH public key |

### Database

| Variable | Default | Description |
|---|---|---|
| `db_name` | `"nexus_app"` | PostgreSQL database name |
| `db_user` | `"nexus_user"` | PostgreSQL username |
| `db_password` | `"SuperSecretPassword123!"` | PostgreSQL password (sensitive) |

### Neo4j

| Variable | Default | Description |
|---|---|---|
| `neo4j_password` | `"GraphSecret123!"` | Neo4j initial password for `neo4j` user (sensitive) |

### Kafka

| Variable | Default | Description |
|---|---|---|
| `install_kafka` | `true` | `true` = download & install Kafka, `false` = skip entirely |
| `kafka_mode` | `"kraft"` | `"kraft"` (modern, no Zookeeper) or `"zookeeper"` (legacy) |

### App Runtime

| Variable | Default | Description |
|---|---|---|
| `process_manager` | `"systemd"` | How to run the 6 app processes: `"systemd"` or `"supervisord"` |

### Reverse Proxy & TLS

| Variable | Default | Description |
|---|---|---|
| `enable_nginx` | `true` | Install Nginx as reverse proxy (port 80 → 8000) |
| `domain_name` | `""` | Your domain (e.g. `api.myapp.com`). Set this to auto-get a free TLS cert via Certbot. Leave empty for HTTP only. |

---

## 🚀 Deployment Guide

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/downloads) installed
- AWS credentials configured (`aws configure` or env vars)
- SSH key pair: `~/.ssh/id_ed25519` + `~/.ssh/id_ed25519.pub`

### Step 1 — Initialize

```bash
cd new-instance
terraform init
```

### Step 2 — Preview

```bash
terraform plan
```

### Step 3 — Deploy

```bash
terraform apply
# type 'yes' when prompted
```

### Step 4 — Note Your Outputs

After apply finishes, Terraform prints all connection details:

```
Outputs:

instance_public_ip      = "54.123.45.67"
instance_private_ip     = "172.31.10.5"
ssh_connection_command  = "ssh -i ~/.ssh/id_ed25519 ubuntu@54.123.45.67"
neo4j_http_url          = "http://54.123.45.67:7474"
neo4j_bolt_url          = "bolt://54.123.45.67:7687"
kafka_bootstrap_servers = "54.123.45.67:9092"
kafka_mode_used         = "kraft"
kafka_topics_created    = "ingestion.calendar, ingestion.email"
process_manager_used    = "systemd"
gateway_url             = "http://54.123.45.67"
app_https_url           = "No domain set — TLS not configured"
tls_status              = "HTTP only — set domain_name variable to enable TLS"
```

---

## 🔐 SSH Into the Instance

```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<public-ip>
```

> For Amazon Linux, replace `ubuntu` with `ec2-user`.

---

## 📋 Check Provisioning Logs

The user-data script logs everything here — check this first after deploying:

```bash
sudo tail -f /var/log/cloud-init-output.log
```

Wait for the final line:
```
[INFO] User-data provisioning complete.
```

---

## 🗄️ PostgreSQL

```bash
# Connect as app user
psql -h 127.0.0.1 -U nexus_user -d nexus_app

# Connect as superuser
sudo -i -u postgres psql

# List databases
sudo -i -u postgres psql -c "\l"

# List users
sudo -i -u postgres psql -c "\du"

# Check service status
sudo systemctl status postgresql
```

---

## 🔮 Neo4j

### Browser (GUI)
Open in your browser:
```
http://<public-ip>:7474
```
- **Username:** `neo4j`
- **Password:** your `neo4j_password` variable value

### Cypher Shell (CLI)
```bash
cypher-shell -u neo4j -p 'GraphSecret123!' -a bolt://localhost:7687

# Example query
MATCH (n) RETURN n LIMIT 10;
```

### Check service
```bash
sudo systemctl status neo4j
sudo ss -tlnp | grep -E '7474|7687'
```

---

## 📨 Apache Kafka

### Verify topics were created
```bash
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Send a test message
```bash
# To ingestion.calendar
echo '{"event":"meeting","date":"2026-03-18"}' | \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic ingestion.calendar

# To ingestion.email
echo '{"from":"boss@corp.com","subject":"Hello"}' | \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic ingestion.email
```

### Read messages
```bash
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic ingestion.calendar \
  --from-beginning
```

### Check service
```bash
sudo systemctl status kafka        # KRaft mode
sudo systemctl status zookeeper    # Zookeeper mode only
sudo ss -tlnp | grep 9092
```

---

## 🐍 Python Application

Your app directory: `/home/appuser/app`  
Your venv: `/home/appuser/venv`

### Deploy your app
```bash
# SSH in and deploy code
scp -i ~/.ssh/id_ed25519 -r ./your-app ubuntu@<public-ip>:/home/appuser/app

# Install dependencies
sudo -u appuser /home/appuser/venv/bin/pip install -e /home/appuser/app

# Run database migrations
sudo -u appuser /home/appuser/venv/bin/alembic -c /home/appuser/app/alembic.ini upgrade head
```

### Environment variables
All connection strings are pre-written to `/home/appuser/.env`:
```bash
cat /home/appuser/.env
```
```
NEXUS_DB_URL=postgresql://nexus_user:...@localhost:5432/nexus_app
NEXUS_NEO4J_URL=bolt://localhost:7687
NEXUS_NEO4J_USER=neo4j
NEXUS_NEO4J_PASSWORD=...
NEXUS_KAFKA_BOOTSTRAP_SERVERS=localhost:9092
```

---

## ⚙️ Process Manager

### systemd (default)

```bash
# Start all 6 processes (after deploying your app)
sudo systemctl start \
  nexus-gateway \
  nexus-calendar-worker \
  nexus-calendar-consumer \
  nexus-email-worker \
  nexus-email-consumer \
  nexus-nudge-agent

# Check status of all at once
sudo systemctl status nexus-* --no-pager

# View live logs for any process
sudo journalctl -fu nexus-gateway
sudo journalctl -fu nexus-calendar-consumer
sudo journalctl -fu nexus-email-consumer
sudo journalctl -fu nexus-nudge-agent

# Restart a single process
sudo systemctl restart nexus-gateway
```

> All 6 units are `enabled` — they **auto-start on reboot**.  
> Each unit reads `/home/appuser/.env` automatically via `EnvironmentFile`.

### supervisord (alternative)

```bash
# Check all process statuses
sudo supervisorctl status

# Start / stop / restart one
sudo supervisorctl start  nexus-gateway
sudo supervisorctl stop   nexus-gateway
sudo supervisorctl restart nexus-gateway

# Reload config after changes
sudo supervisorctl reread && sudo supervisorctl update

# Tail logs
sudo supervisorctl tail nexus-gateway
sudo supervisorctl tail -f nexus-calendar-consumer
```

Config file: `/etc/supervisor/conf.d/nexus.conf`

---

## 🌐 Nginx Reverse Proxy

Nginx listens on **port 80** and forwards all traffic to `http://127.0.0.1:8000` (your FastAPI gateway).

```bash
# Check status
sudo systemctl status nginx

# Test config syntax
sudo nginx -t

# Reload after config changes (no downtime)
sudo systemctl reload nginx

# View access logs
sudo tail -f /var/log/nginx/access.log

# View error logs
sudo tail -f /var/log/nginx/error.log
```

Config file: `/etc/nginx/conf.d/nexus.conf`

---

## 🔒 TLS / HTTPS (via Certbot)

> Only applies when `domain_name` variable is set (e.g. `domain_name = "api.myapp.com"`).

### Prerequisites
Before deploying with a domain, ensure:
1. You own the domain
2. DNS **A record** for `api.myapp.com` points to your EC2 **public IP**
3. DNS has propagated (check with `nslookup api.myapp.com`)

### Enable TLS on existing instance (manual)
```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx -y   # Ubuntu
# or
sudo dnf install certbot python3-certbot-nginx -y   # Amazon Linux

# Get certificate (Nginx must be running and domain must resolve)
sudo certbot --nginx --non-interactive --agree-tos \
  --email admin@myapp.com \
  --domains api.myapp.com \
  --redirect

# Auto-renewal is set up automatically by certbot
# Test renewal manually
sudo certbot renew --dry-run
```

After Certbot runs, your site is available at:
```
https://api.myapp.com
```
HTTP automatically redirects to HTTPS.

---

## 🔍 Quick Diagnostics — Check Everything at Once

```bash
# All service statuses
sudo systemctl is-active neo4j postgresql kafka nginx && echo "INFRA UP ✅" || echo "SOMETHING DOWN ❌"

# Ports listening
sudo ss -tlnp | grep -E '80|443|5432|7474|7687|8000|9092'

# .env contents
cat /home/appuser/.env

# Cloud-init provisioning log
sudo tail -100 /var/log/cloud-init-output.log | grep -E '\[INFO\]|ERROR|FAIL'

# Neo4j binding (must show 0.0.0.0 not 127.0.0.1)
sudo ss -tlnp | grep -E '7474|7687'
```

---

## 💸 Tear Down (Stop AWS Charges)

```bash
terraform destroy
# type 'yes' when prompted
```

> ⚠️ This **permanently deletes** the EC2 instance and all data on it.  
> Back up your PostgreSQL and Neo4j data before destroying.

---

## 📌 Port Reference

| Port | Service | Access |
|------|---------|--------|
| `22` | SSH | `ssh -i ~/.ssh/id_ed25519 ubuntu@<ip>` |
| `80` | HTTP (Nginx → FastAPI) | `http://<ip>` |
| `443` | HTTPS (Certbot TLS) | `https://<domain>` |
| `8000` | FastAPI direct | `http://<ip>:8000` |
| `5432` | PostgreSQL | App connection string |
| `9092` | Kafka | Bootstrap server |
| `7474` | Neo4j Browser (HTTP) | `http://<ip>:7474` |
| `7687` | Neo4j Bolt (Driver) | `bolt://<ip>:7687` |
