# Nexus App Server - Terraform Infrastructure

A fully automated Terraform setup that provisions an EC2 instance on AWS with everything the Nexus application needs: **PostgreSQL**, **Neo4j**, **Apache Kafka**, **Python 3.11**, a **process manager** for 6 app services, and an **Nginx reverse proxy** with optional **free TLS via Let's Encrypt**.

**No pre-existing AWS resources needed** - the code creates VPC, subnet, internet gateway, route table, security group, SSH key pair, and EC2 instance from scratch.

---

## Architecture Overview

```
                        Internet
                           |
                    +------v------+
                    |  AWS EC2    |  (configurable instance type)
                    |             |
                    |  +--------+ |  :80 / :443
                    |  | Nginx  |<|-- Browser / API Client
                    |  +---+----+ |
                    |      | proxy_pass
                    |  +---v------------------------------------+
                    |  |         FastAPI Gateway  :8000          |
                    |  +-+----------+----------+----------------+
                    |    |          |           |
                    |  +-v------+ +v--------+ +v-----------+
                    |  |Postgres| |  Neo4j  | |   Kafka    |
                    |  | :5432  | |:7474    | |   :9092    |
                    |  +--------+ |:7687    | +------------+
                    |             +---------+
                    |
                    |  6 Background Processes (systemd / supervisord):
                    |   - nexus-gateway          (FastAPI)
                    |   - nexus-calendar-worker
                    |   - nexus-calendar-consumer
                    |   - nexus-email-worker
                    |   - nexus-email-consumer
                    |   - nexus-nudge-agent
                    +---------------------------------------------

     Inside custom VPC (10.0.0.0/16)
       Public Subnet (10.0.1.0/24)
         Internet Gateway attached
         Route Table: 0.0.0.0/0 -> IGW
```

---

## Project Structure

```
new-instance/
  main.tf              # All resources: VPC, subnet, IGW, SG, key pair, EC2, outputs
  variables.tf         # All configurable variables with defaults and validation
  user-data.sh.tlp     # Bash provisioning script (runs on first boot)
  Readme.md            # This file
  TESTING.md           # Post-deployment verification guide
  .gitignore           # Prevents sensitive files from being committed
```

---

## What Gets Created

| Resource | Name | Purpose |
|----------|------|---------|
| VPC | nexus-vpc | Isolated network (10.0.0.0/16) |
| Subnet | nexus-public-subnet | Public subnet (10.0.1.0/24) with auto-assign public IP |
| Internet Gateway | nexus-igw | Allows internet access from the VPC |
| Route Table | nexus-public-rt | Routes all traffic (0.0.0.0/0) through the IGW |
| Security Group | nexus-sg | Opens ports: 22, 80, 443, 5432, 7474, 7687, 8000, 9092 |
| SSH Key Pair | nexus-server-key | Auto-generated RSA 4096-bit key, .pem saved locally |
| EC2 Instance | Nexus-App-Server | Runs all services via user-data script |

---

## How It Works

### 1. `terraform apply` is run

Terraform creates all networking, generates an SSH key pair, and launches the EC2 instance. The private key (`nexus-key.pem`) is saved in your project folder automatically.

### 2. EC2 boots and `user-data.sh.tlp` runs automatically

The script runs once on first boot and performs these steps:

| Step | What happens |
|------|-------------|
| **1** | Creates the app Linux user with sudo access |
| **2** | Installs Java, Python 3.11, PostgreSQL, Neo4j |
| **3** | Configures Neo4j to listen on all interfaces and starts it |
| **4** | Downloads and configures Kafka (KRaft or Zookeeper mode), creates topics |
| **5** | Sets up the PostgreSQL database, user, and permissions |
| **6** | Writes `/home/<app_user>/.env` with all connection strings |
| **7** | Creates a Python 3.11 virtual environment |
| **8** | Sets up the process manager (systemd or supervisord) for all 6 app processes |
| **9** | Installs Nginx as a reverse proxy, optionally runs Certbot for TLS |

---

## Variables

### AWS

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | AWS region to deploy in |
| `instance_type` | `t3.medium` | EC2 instance type |

### VPC Network

| Variable | Default | Description |
|----------|---------|-------------|
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the VPC |
| `subnet_cidr` | `10.0.1.0/24` | CIDR block for the public subnet |

### App User

| Variable | Default | Description |
|----------|---------|-------------|
| `app_user` | `appuser` | Linux username on the EC2 instance |

### OS and Java

| Variable | Default | Description |
|----------|---------|-------------|
| `os_choice` | `ubuntu` | `ubuntu` (22.04) or `amazon_linux` (2023) |
| `java_version` | `21` | Java version: `17` or `21` |

### PostgreSQL

| Variable | Default | Description |
|----------|---------|-------------|
| `db_name` | `nexus_app` | Database name |
| `db_user` | `nexus_user` | Database username |
| `db_password` | `dbpassword` | Database password (sensitive) |

### Neo4j

| Variable | Default | Description |
|----------|---------|-------------|
| `neo4j_password` | `neo4jpassword` | Initial password for neo4j user (sensitive) |

### Kafka (prompted at apply time)

| Variable | Default | Description |
|----------|---------|-------------|
| `install_kafka` | _(asked)_ | `true` to install, `false` to skip |
| `kafka_mode` | _(asked)_ | `kraft` (modern) or `zookeeper` (legacy) |

### Process Manager

| Variable | Default | Description |
|----------|---------|-------------|
| `process_manager` | `systemd` | `systemd` or `supervisord` |

### Reverse Proxy and TLS

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_nginx` | `true` | Install Nginx reverse proxy (port 80 to 8000) |
| `domain_name` | `""` | Domain name for auto TLS via Certbot. Leave empty for HTTP only. |

---

## Deployment

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/downloads) installed
- AWS credentials configured (`aws configure` or environment variables)
- No SSH key needed (auto-generated)

### Step 1 - Initialize

```bash
cd new-instance
terraform init
```

### Step 2 - Preview

```bash
terraform plan
```

Terraform will ask for `install_kafka` and `kafka_mode` since they have no defaults.

### Step 3 - Deploy

```bash
terraform apply
```

Type the values when prompted, then type `yes` to confirm.

### Step 4 - Note the Outputs

```
ssh_private_key_file   = "./nexus-key.pem"
ssh_connection_command = "ssh -i nexus-key.pem ubuntu@54.123.45.67"
vpc_id                 = "vpc-0abc123..."
subnet_id              = "subnet-0def456..."
instance_public_ip     = "54.123.45.67"
instance_private_ip    = "10.0.1.15"
neo4j_http_url         = "http://54.123.45.67:7474"
neo4j_bolt_url         = "bolt://54.123.45.67:7687"
kafka_bootstrap_servers = "54.123.45.67:9092"
kafka_mode_used        = "kraft"
kafka_topics_created   = "ingestion.calendar, ingestion.email"
process_manager_used   = "systemd"
gateway_url            = "http://54.123.45.67"
```

---

## SSH Into the Instance

The SSH key is auto-generated and saved as `nexus-key.pem` in the project folder:

```bash
ssh -i nexus-key.pem ubuntu@<public-ip>
```

For Amazon Linux use `ec2-user` instead of `ubuntu`.

---

## Check Provisioning

```bash
sudo tail -f /var/log/cloud-init-output.log
```

Wait for the final banner:
```
####################################################
######################  ALL DONE ###################
####################################################
```

---

## PostgreSQL

```bash
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

## Neo4j

### Browser (GUI)
Open `http://<public-ip>:7474` in your browser.
- Username: `neo4j`
- Password: your `neo4j_password` variable value

### CLI
```bash
cypher-shell -u neo4j -p '<your-password>' -a bolt://localhost:7687
```

### Check service
```bash
sudo systemctl status neo4j
sudo ss -tlnp | grep -E '7474|7687'
```

---

## Kafka

### Verify topics
```bash
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

### Send a test message
```bash
echo '{"event":"test"}' | /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 --topic ingestion.calendar
```

### Read messages
```bash
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 --topic ingestion.calendar --from-beginning
```

### Check service
```bash
sudo systemctl status kafka
sudo ss -tlnp | grep 9092
```

---

## Deploy the Application

```bash
# Copy your app code to the instance
scp -i nexus-key.pem -r ./your-app ubuntu@<public-ip>:/home/<app_user>/app

# Install dependencies
sudo -u <app_user> /home/<app_user>/venv/bin/pip install -e /home/<app_user>/app

# Run database migrations
sudo -u <app_user> /home/<app_user>/venv/bin/alembic -c /home/<app_user>/app/alembic.ini upgrade head
```

### Environment variables
All connection strings are written to `/home/<app_user>/.env` automatically.

---

## Process Manager

### systemd (default)

```bash
# Start all 6 processes
sudo systemctl start nexus-gateway nexus-calendar-worker nexus-calendar-consumer \
  nexus-email-worker nexus-email-consumer nexus-nudge-agent

# Check status
sudo systemctl status nexus-* --no-pager

# View logs
sudo journalctl -fu nexus-gateway

# Restart a process
sudo systemctl restart nexus-gateway
```

All units auto-start on reboot. Each reads `/home/<app_user>/.env` via `EnvironmentFile`.

### supervisord

```bash
# Check status
sudo supervisorctl status

# Restart a process
sudo supervisorctl restart nexus-gateway

# Tail logs
sudo supervisorctl tail -f nexus-gateway
```

---

## Nginx

```bash
# Check status
sudo systemctl status nginx

# Test config
sudo nginx -t

# Reload
sudo systemctl reload nginx

# View logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

---

## TLS / HTTPS

Only applies when `domain_name` is set. DNS A record must point to the EC2 public IP before applying.

### Manual setup on existing instance
```bash
sudo apt install certbot python3-certbot-nginx -y
sudo certbot --nginx --non-interactive --agree-tos \
  --email admin@yourdomain.com --domains yourdomain.com --redirect
sudo certbot renew --dry-run
```

---

## Quick Diagnostics

```bash
sudo systemctl is-active neo4j postgresql kafka nginx && echo "ALL UP" || echo "SOMETHING DOWN"
sudo ss -tlnp | grep -E '80|443|5432|7474|7687|8000|9092'
sudo tail -100 /var/log/cloud-init-output.log | grep -E 'INFO|ERROR|FAIL'
```

---

## Tear Down

```bash
terraform destroy
```

This permanently deletes the VPC, subnet, EC2 instance, and all data. Back up first.

---

## Port Reference

| Port | Service | How to access |
|------|---------|---------------|
| 22 | SSH | `ssh -i nexus-key.pem ubuntu@<ip>` |
| 80 | HTTP (Nginx) | `http://<ip>` |
| 443 | HTTPS (TLS) | `https://<domain>` |
| 5432 | PostgreSQL | App connection string |
| 7474 | Neo4j Browser | `http://<ip>:7474` |
| 7687 | Neo4j Bolt | `bolt://<ip>:7687` |
| 8000 | FastAPI direct | `http://<ip>:8000` |
| 9092 | Kafka | Bootstrap server |
