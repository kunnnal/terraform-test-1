# ✅ Post-Deployment Testing Guide

Run these tests **in order** after `terraform apply` finishes.  
Each section tells you **what to run**, **what good output looks like**, and **what to do if it fails**.

---

## 🕐 Step 0 — Wait for Provisioning to Finish

The EC2 instance takes **3–7 minutes** to fully provision after `terraform apply`.  
SSH in immediately and watch the log:

```bash
# SSH in (use your actual IP from terraform output)
ssh -i ~/.ssh/id_ed25519 ubuntu@<public-ip>

# Watch provisioning live
sudo tail -f /var/log/cloud-init-output.log
```

✅ **Wait until you see this line:**
```
[INFO] User-data provisioning complete.
```

Then press `Ctrl+C` and continue with the tests below.

---

## 🔬 Step 1 — Check All Services Are Running

```bash
sudo systemctl is-active postgresql neo4j kafka nginx
```

✅ **Expected output (one per line):**
```
active
active
active
active
```

❌ **If any shows `inactive` or `failed`:**
```bash
# Replace SERVICE with: postgresql, neo4j, kafka, or nginx
sudo systemctl status SERVICE --no-pager
sudo journalctl -u SERVICE --no-pager -n 30
```

---

## 🔬 Step 2 — Check All Ports Are Listening

```bash
sudo ss -tlnp | grep -E '80|5432|7474|7687|9092'
```

✅ **Expected output — all 5 ports should appear:**
```
LISTEN  0.0.0.0:80     nginx
LISTEN  0.0.0.0:5432   postgres
LISTEN  0.0.0.0:7474   neo4j
LISTEN  0.0.0.0:7687   neo4j
LISTEN  0.0.0.0:9092   kafka
```

> Neo4j **must** show `0.0.0.0` not `127.0.0.1` — if it shows `127.0.0.1` the browser URL won't work.

---

## 🔬 Step 3 — Test PostgreSQL

```bash
# 1. Connect as superuser and list databases
sudo -i -u postgres psql -c "\l"
```

✅ **Expected — you should see `nexus_app` in the list:**
```
   Name    |   Owner   
-----------+-----------
 nexus_app | nexus_user
 postgres  | postgres
```

```bash
# 2. Check the app user exists
sudo -i -u postgres psql -c "\du"
```

✅ **Expected — `nexus_user` should be listed**

```bash
# 3. Connect as the app user (TCP connection)
psql -h 127.0.0.1 -U nexus_user -d nexus_app -c "SELECT current_user, current_database();"
```

✅ **Expected:**
```
 current_user | current_database 
--------------+-----------------
 nexus_user   | nexus_app
```

❌ **If connection refused:** `sudo systemctl restart postgresql`  
❌ **If auth failed:** Check password in `/home/appuser/.env`

---

## 🔬 Step 4 — Test Neo4j

### A. Test from the server (CLI)
```bash
# Check Neo4j is responding on Bolt port
cypher-shell -u neo4j -p 'GraphSecret123!' \
  "RETURN 'Neo4j is working!' AS status;"
```

✅ **Expected:**
```
status
"Neo4j is working!"
```

```bash
# Create and read a test node
cypher-shell -u neo4j -p 'GraphSecret123!' \
  "CREATE (t:Test {name:'hello', ts: datetime()}) RETURN t;"
```

✅ **Expected:** Returns the created node with a timestamp

### B. Test from your browser (on your laptop)
Open: `http://<public-ip>:7474`

✅ **Expected:** Neo4j Browser login screen appears  
- Username: `neo4j`  
- Password: `GraphSecret123!` (or whatever you set)

❌ **If browser hangs / refused:**
```bash
# Check Neo4j is bound to 0.0.0.0, NOT 127.0.0.1
sudo ss -tlnp | grep 7474
# Must show: 0.0.0.0:7474

# If it shows 127.0.0.1:7474, fix it:
sudo sed -i 's/#server.default_listen_address=0.0.0.0/server.default_listen_address=0.0.0.0/' /etc/neo4j/neo4j.conf
grep -q "^server.default_listen_address" /etc/neo4j/neo4j.conf || \
  echo "server.default_listen_address=0.0.0.0" | sudo tee -a /etc/neo4j/neo4j.conf
sudo systemctl restart neo4j
```

---

## 🔬 Step 5 — Test Kafka

### A. Verify topics exist
```bash
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
```

✅ **Expected:**
```
ingestion.calendar
ingestion.email
```

### B. Send a test message and read it back

Open **two SSH terminals** to the same instance:

**Terminal 1 — Start consumer first:**
```bash
/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic ingestion.calendar \
  --from-beginning
```

**Terminal 2 — Send a message:**
```bash
echo '{"test":"kafka_works","ts":"2026-03-18"}' | \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic ingestion.calendar
```

✅ **Expected in Terminal 1:**
```
{"test":"kafka_works","ts":"2026-03-18"}
```

Press `Ctrl+C` in Terminal 1 to stop the consumer.

### C. Test ingestion.email topic
```bash
echo '{"from":"test@example.com","subject":"test"}' | \
  /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server localhost:9092 \
  --topic ingestion.email

/opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic ingestion.email \
  --from-beginning \
  --max-messages 1
```

✅ **Expected:** prints the message and exits

---

## 🔬 Step 6 — Test the .env File

```bash
cat /home/appuser/.env
```

✅ **Expected — all 5 keys should be present:**
```
NEXUS_DB_URL=postgresql://nexus_user:SuperSecretPassword123!@localhost:5432/nexus_app
NEXUS_NEO4J_URL=bolt://localhost:7687
NEXUS_NEO4J_USER=neo4j
NEXUS_NEO4J_PASSWORD=GraphSecret123!
NEXUS_KAFKA_BOOTSTRAP_SERVERS=localhost:9092
```

---

## 🔬 Step 7 — Test Python 3.11 + Venv

```bash
# Check Python version
/home/appuser/venv/bin/python --version
```

✅ **Expected:** `Python 3.11.x`

```bash
# Quick connectivity test using the venv
/home/appuser/venv/bin/python - <<'EOF'
import sys, os
print("Python:", sys.version)

# Load .env manually
env = {}
with open("/home/appuser/.env") as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            k, v = line.split("=", 1)
            env[k] = v

print("DB URL found:", "NEXUS_DB_URL" in env)
print("Neo4j URL found:", "NEXUS_NEO4J_URL" in env)
print("Kafka bootstrap found:", "NEXUS_KAFKA_BOOTSTRAP_SERVERS" in env)
print("✅ All environment variables loaded")
EOF
```

✅ **Expected:**
```
Python: 3.11.x ...
DB URL found: True
Neo4j URL found: True
Kafka bootstrap found: True
✅ All environment variables loaded
```

---

## 🔬 Step 8 — Test Nginx Reverse Proxy

### A. Test from the server itself
```bash
# Test nginx config is valid
sudo nginx -t
```

✅ **Expected:**
```
nginx: configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

```bash
# Test nginx is proxying (even if FastAPI isn't running yet, nginx should respond)
curl -v http://localhost:80
```

✅ **Expected:** Nginx responds (may return 502 Bad Gateway if FastAPI isn't running yet — that's normal, it means Nginx is working)

### B. Test from your laptop browser
Open: `http://<public-ip>`

✅ **Expected:** Nginx response (502 until your app is deployed, but you should NOT get "connection refused")

❌ **If connection refused in browser:**
```bash
sudo systemctl status nginx
sudo systemctl restart nginx
```

---

## 🔬 Step 9 — Test Process Manager (systemd)

```bash
# All 6 nexus units should show as 'enabled' (not yet active — app not deployed)
sudo systemctl list-unit-files | grep nexus
```

✅ **Expected:**
```
nexus-calendar-consumer.service   enabled
nexus-calendar-worker.service     enabled
nexus-email-consumer.service      enabled
nexus-email-worker.service        enabled
nexus-gateway.service             enabled
nexus-nudge-agent.service         enabled
```

> They are **enabled** (auto-start on reboot) but **not yet started** — that's correct.  
> They'll start once you deploy your Python app to `/home/appuser/app/`.

---

## 🔬 Step 10 — Full End-to-End Quick Check (one command)

```bash
echo "=== SERVICE STATUS ===" && \
sudo systemctl is-active postgresql neo4j kafka nginx && \
echo "" && \
echo "=== OPEN PORTS ===" && \
sudo ss -tlnp | grep -E '80|5432|7474|7687|9092' | awk '{print $5}' && \
echo "" && \
echo "=== KAFKA TOPICS ===" && \
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list && \
echo "" && \
echo "=== ENV FILE ===" && \
sudo cat /home/appuser/.env && \
echo "" && \
echo "=== PYTHON VERSION ===" && \
sudo /home/appuser/venv/bin/python --version && \
echo "" && \
echo "✅ ALL CHECKS PASSED"
```

✅ **Expected at the end:** `✅ ALL CHECKS PASSED`

---

## 🧯 Troubleshooting Reference

| Problem | Command to diagnose | Fix |
|---|---|---|
| Service not starting | `sudo journalctl -u SERVICE -n 50` | Check install logs |
| Neo4j browser not loading | `sudo ss -tlnp \| grep 7474` | Must show `0.0.0.0`, not `127.0.0.1` |
| Neo4j auth failed | `cat /home/appuser/.env` | Use password from `.env` |
| Postgres permission denied | Use `sudo -i -u postgres psql` | Don't use `sudo -u postgres psql` |
| Kafka port not open | `sudo systemctl status kafka` | Check KRaft config |
| Nginx 502 Bad Gateway | Normal until FastAPI app is deployed | Deploy your app first |
| Provisioning incomplete | `sudo tail -100 /var/log/cloud-init-output.log` | Check for errors |

---

## 📋 Test Results Checklist

Use this to track your testing:

```
[ ] Step 0 — Provisioning log shows "complete"
[ ] Step 1 — All 4 services: active
[ ] Step 2 — All 5 ports: listening on 0.0.0.0
[ ] Step 3 — PostgreSQL: nexus_app DB + nexus_user exist
[ ] Step 4 — Neo4j: CLI works + browser opens at :7474
[ ] Step 5 — Kafka: both topics listed, message send/receive works
[ ] Step 6 — .env: all 5 keys present
[ ] Step 7 — Python 3.11 venv works, .env loads
[ ] Step 8 — Nginx: config valid, responds on port 80
[ ] Step 9 — All 6 nexus systemd units: enabled
[ ] Step 10 — Full one-liner check passes
```

Once all boxes are checked — your infrastructure is **fully verified** and ready for app deployment! 🎉
