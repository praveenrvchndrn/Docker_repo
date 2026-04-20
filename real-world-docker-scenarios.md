# Real-World Docker Troubleshooting Scenarios
## Production Environment Context

These scenarios mirror real production issues you might encounter supporting enterprise applications.

---

## 🏥 Scenario 1: Pharmacy API Microservice Crash Loop

**Context:** Your pharmacy inventory microservice keeps crashing every 2-3 minutes in production.

**Initial Alert:**
```
ServiceName: pharmacy-inventory-api
Status: CrashLoopBackOff
RestartCount: 47
```

**Your Response:**

```bash
# Step 1: Quick status
docker ps -a | grep pharmacy-inventory

# Step 2: Check logs for patterns
docker logs --tail 100 pharmacy-inventory-api | grep -i "error\|fatal\|exception"

# Commonly seen in logs:
# - "FATAL: password authentication failed for user 'postgres'"
# - "Error: connect ECONNREFUSED 10.0.1.45:5432"
# - "UnhandledPromiseRejectionWarning: Error: Connection terminated unexpectedly"
```

**Diagnostic Commands:**

```bash
# Check how many times it restarted
docker inspect pharmacy-inventory-api --format='RestartCount: {{.RestartCount}}'

# Check exit code pattern
docker inspect pharmacy-inventory-api --format='ExitCode: {{.State.ExitCode}}'
# Exit 1 = application error (likely DB connection)

# Verify database connectivity from container
docker exec pharmacy-inventory-api ping -c 3 postgres-primary.internal
# or
docker exec pharmacy-inventory-api nc -zv postgres-primary.internal 5432

# Check environment variables (DB credentials)
docker exec pharmacy-inventory-api env | grep -i database

# Check if DB_PASSWORD is set
docker inspect pharmacy-inventory-api --format='{{range .Config.Env}}{{println .}}{{end}}' | grep DB_
```

**Root Cause Analysis:**

```bash
# Often it's one of:
# 1. DB credentials wrong/expired
# 2. DB host unreachable (network issue)
# 3. Connection pool exhausted
# 4. Memory leak causing OOMKill

# To confirm memory issue:
docker stats --no-stream pharmacy-inventory-api
docker inspect pharmacy-inventory-api --format='OOMKilled: {{.State.OOMKilled}}'

# To confirm network:
docker network inspect app-network | grep pharmacy-inventory
docker exec pharmacy-inventory-api cat /etc/resolv.conf
```

**Resolution:**

```bash
# If DB credentials issue:
docker stop pharmacy-inventory-api
docker rm pharmacy-inventory-api
docker run -d --name pharmacy-inventory-api \
  --network app-network \
  -e DATABASE_URL=postgresql://user:correct_password@postgres:5432/pharmacy \
  -e NODE_ENV=production \
  pharmacy-api:v1.2.3

# Verify fix:
docker logs -f pharmacy-inventory-api
# Should see: "✓ Connected to database" and "Server listening on port 3000"
```

---

## 🔒 Scenario 2: HIPAA Audit Log Container Filling Disk

**Context:** Your compliance logging container is filling up disk space rapidly.

**Initial Alert:**
```
Host: prod-worker-03
Alert: Disk usage > 85%
Container: audit-log-collector
```

**Your Response:**

```bash
# Step 1: Check disk usage
docker system df
docker system df -v | grep audit-log

# Step 2: Check container size
docker ps -s | grep audit-log-collector
# Shows SIZE column: 500MB (virtual 2.5GB)

# Step 3: Inspect logs size
docker inspect audit-log-collector --format='{{.LogPath}}'
# Usually: /var/lib/docker/containers/<id>/<id>-json.log

sudo ls -lh /var/lib/docker/containers/$(docker inspect audit-log-collector --format='{{.Id}}')/*.log
# Shows: 15GB log file!

# Step 4: Check log rotation config
docker inspect audit-log-collector --format='{{json .HostConfig.LogConfig}}'
```

**Diagnostic Output:**

```json
{
  "Type": "json-file",
  "Config": {}
}
```

**Problem:** No log rotation configured!

**Resolution:**

```bash
# Immediate mitigation: Truncate logs
sudo truncate -s 0 /var/lib/docker/containers/$(docker inspect audit-log-collector --format='{{.Id}}')/*.log

# Permanent fix: Recreate with log rotation
docker stop audit-log-collector
docker rm audit-log-collector

docker run -d --name audit-log-collector \
  --log-driver json-file \
  --log-opt max-size=50m \
  --log-opt max-file=5 \
  -v /var/log/audit:/logs \
  audit-collector:latest

# Verify log config
docker inspect audit-log-collector --format='{{json .HostConfig.LogConfig}}' | jq
```

**Prevention:**

```bash
# Add to docker-compose.yml:
services:
  audit-log-collector:
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "5"
```

---

## 🌐 Scenario 3: Nginx Reverse Proxy Can't Reach Backend

**Context:** Web requests return 502 Bad Gateway. Frontend nginx can't reach backend services.

**Initial Alert:**
```
HTTP 502 Bad Gateway
Service: web-gateway
Backend: patient-portal-api
```

**Your Response:**

```bash
# Step 1: Check nginx container
docker logs --tail 50 web-gateway | grep -i "error\|upstream\|502"

# Common log patterns:
# "connect() failed (111: Connection refused) while connecting to upstream"
# "no live upstreams while connecting to upstream"
# "upstream timed out (110: Connection timed out)"
```

**Diagnostic Commands:**

```bash
# Check if backend is running
docker ps | grep patient-portal-api

# Check nginx can resolve backend hostname
docker exec web-gateway nslookup patient-portal-api
docker exec web-gateway ping -c 2 patient-portal-api

# Check if backend is listening on expected port
docker exec patient-portal-api netstat -tulpn | grep 8080

# Check nginx upstream configuration
docker exec web-gateway cat /etc/nginx/conf.d/default.conf | grep upstream -A 5

# Check they're on same network
docker inspect web-gateway --format='{{json .NetworkSettings.Networks}}' | jq
docker inspect patient-portal-api --format='{{json .NetworkSettings.Networks}}' | jq
```

**Common Issues Found:**

```bash
# Issue 1: Different networks
docker network inspect app-network --format='{{range .Containers}}{{.Name}} {{end}}'
# Shows: web-gateway (but not patient-portal-api)

# Fix:
docker network connect app-network patient-portal-api

# Issue 2: Backend crashed but restart policy not set
docker ps -a | grep patient-portal-api
# Shows: Exited (1) 3 minutes ago

docker logs patient-portal-api | tail -20
# Shows: "Error: EADDRINUSE: address already in use :::8080"

# Fix: Clear port conflict
docker rm patient-portal-api
docker run -d --name patient-portal-api \
  --network app-network \
  --restart unless-stopped \
  patient-api:v2.1.0

# Issue 3: Backend listening on 0.0.0.0:8080 not 127.0.0.1:8080
docker exec patient-portal-api netstat -tulpn
# If shows: 127.0.0.1:8080 (wrong - only local)
# Should be: 0.0.0.0:8080 (all interfaces)

# Fix in app config or Dockerfile:
# Change: app.listen(8080, 'localhost')
# To:     app.listen(8080, '0.0.0.0')
```

**Verification:**

```bash
# Test from nginx container
docker exec web-gateway curl -I http://patient-portal-api:8080/health
# Should return: HTTP/1.1 200 OK

# Test end-to-end
curl -I https://portal.yourcompany.com/api/health
# Should return: HTTP/2 200
```

---

## 💾 Scenario 4: PostgreSQL Container Data Lost After Restart

**Context:** After host reboot, database is empty. Data not persisted.

**Initial Alert:**
```
ServiceName: postgres-main
Issue: All tables missing after restart
PanicLevel: CRITICAL
```

**Your Response:**

```bash
# Step 1: Check if volume was mounted
docker inspect postgres-main --format='{{json .Mounts}}' | jq

# Problem Found:
# Output shows: [] (empty - no volumes!)
# OR shows tmpfs mount instead of volume
```

**Diagnostic:**

```bash
# Check how container was started
docker inspect postgres-main --format='{{.Config.Cmd}}'
docker inspect postgres-main --format='{{.Config.Image}}'

# Look for mount point
docker exec postgres-main ls -la /var/lib/postgresql/data
# If shows only a few files: postgres never actually wrote to a volume

# Check docker events for clues
docker events --since 24h --filter container=postgres-main

# Look at compose file or run command
docker inspect postgres-main --format='{{.Config.Labels}}'
```

**Root Cause:**

```yaml
# Wrong - no volume (from docker-compose.yml):
services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: secret
    # NO VOLUME - Data stored in container layer!
```

**Resolution:**

```bash
# Check if old data exists in a volume
docker volume ls | grep postgres

# If volume exists, data might be salvageable
docker volume inspect postgres-data

# Create new container with proper volume
docker stop postgres-main
docker rm postgres-main

# Option 1: Named volume
docker run -d --name postgres-main \
  -e POSTGRES_PASSWORD=secret \
  -v postgres-data:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:14

# Option 2: Host mount (for easy backup)
docker run -d --name postgres-main \
  -e POSTGRES_PASSWORD=secret \
  -v /mnt/data/postgres:/var/lib/postgresql/data \
  -p 5432:5432 \
  postgres:14

# Verify volume is mounted
docker inspect postgres-main --format='{{json .Mounts}}' | jq
```

**Verification:**

```bash
# Create test data
docker exec -it postgres-main psql -U postgres -c "CREATE TABLE test(id INT);"
docker exec -it postgres-main psql -U postgres -c "INSERT INTO test VALUES (1);"

# Restart container
docker restart postgres-main

# Verify data persisted
docker exec -it postgres-main psql -U postgres -c "SELECT * FROM test;"
# Should show: id | 1

# Check volume
docker volume inspect postgres-data
```

**Prevention in Docker Compose:**

```yaml
services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_PASSWORD: secret
    volumes:
      - postgres-data:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  postgres-data:
    driver: local
```

---

## 🔥 Scenario 5: Redis Cache OOMKilled During Peak Hours

**Context:** During pharmacy rush hours (lunch time), Redis container crashes.

**Initial Alert:**
```
Service: redis-cache
Status: Exited (137)
Time: 12:45 PM (peak hours)
RestartCount: 5 in last hour
```

**Your Response:**

```bash
# Step 1: Confirm OOMKill
docker inspect redis-cache --format='OOMKilled: {{.State.OOMKilled}}'
# Output: true

docker inspect redis-cache --format='ExitCode: {{.State.ExitCode}}'
# Output: 137 (OOMKilled)

# Step 2: Check memory limits
docker inspect redis-cache --format='Memory Limit: {{.HostConfig.Memory}}'
# Output: 268435456 (256MB - too low!)

# Step 3: Check actual memory usage before crash
docker stats --no-stream redis-cache
# (if still running, or check historical metrics)

# Step 4: Check Redis configuration
docker exec redis-cache redis-cli INFO memory
```

**Redis Memory Info Output:**

```
used_memory_human:245.67M
used_memory_peak_human:298.45M
maxmemory:256000000
maxmemory_policy:noeviction
```

**Problem:** Redis trying to use 298MB but container limited to 256MB!

**Resolution:**

```bash
# Stop and remove container
docker stop redis-cache
docker rm redis-cache

# Recreate with higher memory limit and eviction policy
docker run -d --name redis-cache \
  --memory="1g" \
  --memory-reservation="512m" \
  -p 6379:6379 \
  redis:7-alpine redis-server \
  --maxmemory 900mb \
  --maxmemory-policy allkeys-lru

# Verify new limits
docker inspect redis-cache --format='Memory: {{.HostConfig.Memory}}'
docker exec redis-cache redis-cli CONFIG GET maxmemory
```

**Monitoring Setup:**

```bash
# Add CloudWatch or Prometheus monitoring
docker run -d --name redis-exporter \
  --link redis-cache:redis \
  -p 9121:9121 \
  oliver006/redis_exporter

# Check metrics
curl localhost:9121/metrics | grep redis_memory
```

**Prevention:**

```yaml
# docker-compose.yml with proper limits
services:
  redis:
    image: redis:7-alpine
    mem_limit: 1g
    mem_reservation: 512m
    command: redis-server --maxmemory 900mb --maxmemory-policy allkeys-lru
    restart: unless-stopped
```

---

## 🔐 Scenario 6: Secret Rotation Breaks Running Containers

**Context:** Security team rotated database password. All app containers can't connect.

**Initial Alert:**
```
Multiple services failing authentication
Error: password authentication failed
Time: 02:00 AM (automated rotation)
```

**Your Response:**

```bash
# Step 1: Identify affected containers
docker ps --format "table {{.Names}}\t{{.Status}}" | grep "Restarting"

# Step 2: Check logs for auth failures
for container in $(docker ps --filter "status=restarting" --format "{{.Names}}"); do
    echo "=== $container ==="
    docker logs --tail 20 $container | grep -i "auth\|password\|credentials"
done

# Step 3: Verify old vs new credentials
docker exec api-service-1 env | grep DB_PASSWORD
# Shows: DB_PASSWORD=old_password_123

# Check if secret was updated in AWS Secrets Manager / Vault
aws secretsmanager get-secret-value --secret-id prod/db/password
```

**Resolution Strategy:**

```bash
# Option 1: Manual update (quick fix for incident)
docker stop api-service-1 api-service-2 api-service-3

docker rm api-service-1
docker run -d --name api-service-1 \
  -e DB_PASSWORD=new_password_456 \
  --restart unless-stopped \
  api:v1.2.3

# Repeat for other services...

# Option 2: Update docker-compose with new env vars
# Edit .env file:
# DB_PASSWORD=new_password_456

docker-compose up -d --force-recreate

# Option 3: Use secrets management (proper solution)
# Using Docker Swarm secrets or Kubernetes secrets
docker secret create db_password /tmp/new_password.txt
docker service update --secret-rm old_db_password \
                     --secret-add db_password \
                     api-service
```

**Verification:**

```bash
# Test database connection from containers
for container in $(docker ps --format "{{.Names}}" | grep api-service); do
    echo "Testing $container..."
    docker exec $container nc -zv postgres-primary 5432
    docker logs --tail 5 $container | grep -i "connected\|ready"
done

# Check application health endpoints
curl http://localhost:8080/health
```

**Prevention:**

```bash
# Implement health checks with secrets validation
# In Dockerfile:
HEALTHCHECK --interval=30s --timeout=3s \
  CMD node healthcheck.js || exit 1

# healthcheck.js should test DB connection
# If connection fails, container marked unhealthy but doesn't restart unnecessarily
```

---

## 📊 Scenario 7: Performance Degradation - Slow Response Times

**Context:** Users reporting slow page loads. Application response time degraded from 200ms to 5000ms.

**Your Response:**

```bash
# Step 1: Check resource usage
docker stats

# Look for:
# - CPU at 100% (CPU bound)
# - Memory near limit (memory pressure)
# - High network I/O (network bottleneck)

# Step 2: Check application logs for slow queries
docker logs --since 10m api-gateway | grep -i "slow\|timeout\|exceeded"

# Step 3: Check connection pools
docker exec api-gateway curl -s localhost:9090/metrics | grep "pool\|connections"
```

**Common Findings:**

```bash
# Database connection pool exhausted
docker exec api-gateway curl localhost:8080/debug/db-pool
# Output: active: 50, idle: 0, waiting: 234

# Check slow queries in Postgres logs
docker logs postgres-main | grep "duration:" | grep "LOG:  duration: [5-9][0-9][0-9][0-9]"

# Memory leak detection
docker stats api-gateway --no-stream
# Compare with historical data - if memory climbing = leak

# Check garbage collection (Node.js example)
docker exec api-gateway node --expose-gc -e "global.gc(); console.log(process.memoryUsage())"
```

**Resolution:**

```bash
# Immediate: Restart affected services
docker-compose restart api-gateway

# Scale horizontally if needed
docker-compose up -d --scale api-gateway=3

# Increase connection pool
docker stop api-gateway
docker rm api-gateway
docker run -d --name api-gateway \
  -e DB_POOL_SIZE=100 \
  -e DB_POOL_MAX=200 \
  api:v1.2.3

# Add resource limits to prevent one container from starving others
docker update --cpus="2.0" --memory="2g" api-gateway
```

---

## 🎯 Key Patterns Across All Scenarios

### 1. **Immediate Triage (30 seconds)**
```bash
docker ps -a | grep <service>
docker logs --tail 50 <container>
docker inspect <container> --format='{{.State.ExitCode}}'
```

### 2. **Detailed Investigation (5 minutes)**
```bash
docker stats <container>
docker inspect <container>
docker exec <container> <diagnostic command>
```

### 3. **Resolution Verification**
```bash
docker logs -f <container>  # Watch for success messages
curl <health_endpoint>      # Test functionality
docker stats <container>    # Verify resources normal
```

### 4. **Documentation**
Always document:
- What failed
- Error messages seen
- Root cause found
- Fix applied
- Prevention steps added

---

## 🚨 Production Incident Response Checklist

```
□ Alert received - note timestamp
□ Identify affected service(s)
□ Check container status (docker ps -a)
□ Review last 100 lines of logs
□ Check exit code if stopped
□ Verify resource usage
□ Test connectivity (network/DB)
□ Check recent changes (deployments/config)
□ Apply fix
□ Verify resolution
□ Monitor for recurrence
□ Document in runbook
□ Post-incident review
```

---

**Remember:** In production, speed matters but accuracy matters more. Follow the systematic approach, document everything, and always verify your fix before declaring incident resolved.
