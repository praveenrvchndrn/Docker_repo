# Docker Troubleshooting Systematic Guide

## 🎯 Troubleshooting Workflow

```
1. Identify the symptom
2. Check container state
3. Inspect container details
4. Review logs
5. Verify configuration
6. Test connectivity/resources
7. Fix and validate
```

---

## 📋 Essential Diagnostic Commands

### Quick Status Check
```bash
# See all containers (running + stopped)
docker ps -a

# Check container resource usage
docker stats

# Quick health check
docker inspect <container_id> --format='{{.State.Status}}'
```

---

## 🔥 Common Issues & Troubleshooting

### 1. Container Fails to Start / Immediately Exits

**Symptoms:**
- Container shows "Exited (1)" or "Exited (137)"
- Container doesn't appear in `docker ps`

**Diagnostic Commands:**
```bash
# Check exit code and state
docker ps -a | grep <container_name>

# View last container logs
docker logs <container_id>

# Check detailed exit status
docker inspect <container_id> --format='{{.State.ExitCode}}'
docker inspect <container_id> --format='{{.State.Error}}'

# View container config
docker inspect <container_id>
```

**Common Exit Codes:**
- **Exit 0**: Normal exit
- **Exit 1**: Application error
- **Exit 137**: OOM killed (out of memory)
- **Exit 139**: Segmentation fault
- **Exit 143**: SIGTERM received

**What to Check in Logs:**
```bash
# Last 50 lines
docker logs --tail 50 <container_id>

# Follow logs in real-time
docker logs -f <container_id>

# Logs with timestamps
docker logs -t <container_id>

# Logs from last 5 minutes
docker logs --since 5m <container_id>
```

**Log Patterns to Look For:**
- `Error:`, `ERROR`, `FATAL`, `Exception`
- `Permission denied`
- `Cannot find module`
- `Connection refused`
- `Address already in use`

**Practice Scenario:**
```bash
# Create intentional error - wrong command
docker run --name test-fail ubuntu wrongcommand

# Check why it failed
docker logs test-fail
# Output: "docker: Error response from daemon: failed to create shim task..."

docker ps -a | grep test-fail
# Shows: Exited (127) - command not found
```

---

### 2. Application Crashes Inside Container

**Symptoms:**
- Container starts but crashes after some time
- Application errors in logs

**Diagnostic Commands:**
```bash
# Check if container restarted
docker inspect <container_id> --format='{{.RestartCount}}'

# View last few restarts
docker inspect <container_id> --format='{{range .State.Health.Log}}{{.Start}} {{.ExitCode}} {{end}}'

# Check memory limit hit
docker stats --no-stream <container_id>

# Get last 100 lines with timestamps
docker logs --tail 100 -t <container_id>
```

**What to Check:**
1. **Memory Issues:**
   ```bash
   docker stats <container_id>
   # Look for memory usage near limit
   ```

2. **Environment Variables Missing:**
   ```bash
   docker inspect <container_id> | grep -A 20 "Env"
   ```

3. **Volume Mount Issues:**
   ```bash
   docker inspect <container_id> | grep -A 10 "Mounts"
   ```

**Practice Scenario:**
```bash
# Create memory-limited container that will OOMkill
docker run -d --name mem-test --memory="50m" ubuntu bash -c "yes | tr \\n x | head -c 100m | grep n"

# Watch it get killed
docker ps -a | grep mem-test
# Shows: Exited (137)

# Confirm OOMKill
docker inspect mem-test --format='{{.State.OOMKilled}}'
# Output: true
```

---

### 3. Port Binding Errors

**Symptoms:**
- "port is already allocated"
- "bind: address already in use"

**Diagnostic Commands:**
```bash
# Check what's using the port (Linux)
sudo netstat -tulpn | grep :8080
# OR
sudo lsof -i :8080

# Check Docker port mappings
docker port <container_id>

# Inspect network bindings
docker inspect <container_id> --format='{{json .NetworkSettings.Ports}}'
```

**What to Check in Logs:**
```bash
docker logs <container_id> 2>&1 | grep -i "address already in use"
docker logs <container_id> 2>&1 | grep -i "bind"
```

**Practice Scenario:**
```bash
# Start nginx on port 80
docker run -d --name nginx1 -p 80:80 nginx

# Try to start another on same port
docker run -d --name nginx2 -p 80:80 nginx
# Error: "port is already allocated"

# Find which container is using the port
docker ps --format "table {{.Names}}\t{{.Ports}}"

# Solution: Use different host port
docker run -d --name nginx2 -p 8080:80 nginx
```

---

### 4. Network Connectivity Issues

**Symptoms:**
- Cannot reach external services
- Containers can't communicate
- DNS resolution fails

**Diagnostic Commands:**
```bash
# Check container network
docker inspect <container_id> --format='{{.NetworkSettings.IPAddress}}'

# List networks
docker network ls

# Inspect network details
docker network inspect bridge

# Test connectivity from inside container
docker exec <container_id> ping -c 3 google.com
docker exec <container_id> curl -I https://google.com

# Check DNS
docker exec <container_id> nslookup google.com
docker exec <container_id> cat /etc/resolv.conf
```

**What to Check in Logs:**
```bash
# Look for connection errors
docker logs <container_id> 2>&1 | grep -i "connection refused"
docker logs <container_id> 2>&1 | grep -i "timeout"
docker logs <container_id> 2>&1 | grep -i "no route to host"
docker logs <container_id> 2>&1 | grep -i "network unreachable"
```

**Practice Scenario:**
```bash
# Create isolated network
docker network create isolated-net

# Run container in isolated network
docker run -d --name isolated --network isolated-net nginx

# Run another container in default bridge
docker run -d --name default nginx

# Try to ping from isolated to default (will fail)
docker exec isolated ping -c 2 default
# Error: "ping: unknown host"

# Connect isolated container to bridge network
docker network connect bridge isolated

# Now ping works
docker exec isolated ping -c 2 default
```

---

### 5. Volume Mount Issues

**Symptoms:**
- "no such file or directory"
- "permission denied"
- Data not persisting

**Diagnostic Commands:**
```bash
# Check mounts
docker inspect <container_id> --format='{{json .Mounts}}' | jq

# Verify volume exists
docker volume ls

# Inspect volume
docker volume inspect <volume_name>

# Check from inside container
docker exec <container_id> ls -la /path/to/mount
docker exec <container_id> df -h
```

**What to Check in Logs:**
```bash
docker logs <container_id> 2>&1 | grep -i "permission denied"
docker logs <container_id> 2>&1 | grep -i "no such file"
docker logs <container_id> 2>&1 | grep -i "read-only file system"
```

**Practice Scenario:**
```bash
# Create volume with wrong permissions
docker volume create mydata

# Run container with non-root user
docker run -d --name perm-test \
  -v mydata:/data \
  --user 1001:1001 \
  ubuntu bash -c "echo test > /data/file.txt"

# Check logs for permission error
docker logs perm-test
# Output: "bash: /data/file.txt: Permission denied"

# Fix: Pre-create directory with correct permissions
docker run --rm -v mydata:/data alpine chown -R 1001:1001 /data

# Now retry
docker run --rm -v mydata:/data --user 1001:1001 \
  ubuntu bash -c "echo test > /data/file.txt && cat /data/file.txt"
```

---

### 6. Environment Variable Issues

**Symptoms:**
- Application can't find configuration
- "undefined environment variable"

**Diagnostic Commands:**
```bash
# Check all environment variables
docker inspect <container_id> --format='{{range .Config.Env}}{{println .}}{{end}}'

# Check specific variable from inside
docker exec <container_id> env | grep DATABASE_URL
docker exec <container_id> printenv DATABASE_URL

# Check .env file loaded correctly
docker exec <container_id> cat /app/.env
```

**Practice Scenario:**
```bash
# Create app expecting DATABASE_URL
cat > app.js << 'EOF'
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  console.error('ERROR: DATABASE_URL not set!');
  process.exit(1);
}
console.log('Connected to:', dbUrl);
EOF

# Build without env var
docker run -d --name node-fail \
  -v $(pwd)/app.js:/app/app.js \
  node:18 node /app/app.js

# Check logs
docker logs node-fail
# Output: "ERROR: DATABASE_URL not set!"

# Fix: Add environment variable
docker run -d --name node-success \
  -e DATABASE_URL=postgresql://localhost:5432/mydb \
  -v $(pwd)/app.js:/app/app.js \
  node:18 node /app/app.js

docker logs node-success
# Output: "Connected to: postgresql://localhost:5432/mydb"
```

---

### 7. Resource Exhaustion

**Symptoms:**
- Container frozen/unresponsive
- Slow performance
- OOMKilled

**Diagnostic Commands:**
```bash
# Real-time resource monitoring
docker stats

# Check resource limits
docker inspect <container_id> --format='Memory: {{.HostConfig.Memory}}'
docker inspect <container_id> --format='CPU: {{.HostConfig.NanoCpus}}'

# Check if OOMKilled
docker inspect <container_id> --format='{{.State.OOMKilled}}'

# System-wide Docker stats
docker system df
docker system df -v
```

**Practice Scenario:**
```bash
# Run CPU-intensive task with limit
docker run -d --name cpu-limit \
  --cpus="0.5" \
  ubuntu bash -c "yes > /dev/null"

# Monitor in another terminal
docker stats cpu-limit
# Will show CPU at 50%

# Run without limit for comparison
docker run -d --name cpu-nolimit \
  ubuntu bash -c "yes > /dev/null"

docker stats cpu-nolimit
# Will show CPU at 100%+

# Cleanup
docker stop cpu-limit cpu-nolimit
docker rm cpu-limit cpu-nolimit
```

---

### 8. Image Build Issues

**Symptoms:**
- "no such file or directory" during COPY
- Cache not working as expected
- Layer size too large

**Diagnostic Commands:**
```bash
# Build with no cache
docker build --no-cache -t myapp .

# Build with build args
docker build --build-arg NODE_ENV=production -t myapp .

# See build history
docker history <image_id>

# Check image layers
docker inspect <image_id> --format='{{json .RootFS.Layers}}'

# Build with progress output
docker build --progress=plain -t myapp .
```

**Practice Scenario:**
```bash
# Create Dockerfile with intentional error
cat > Dockerfile << 'EOF'
FROM node:18
WORKDIR /app
COPY package.json .
RUN npm install
COPY . .
CMD ["node", "app.js"]
EOF

# Try to build without package.json
docker build -t test-build .
# Error: "COPY failed: file not found in build context"

# Check what's in build context
ls -la

# Create package.json and retry
echo '{"name": "test"}' > package.json
docker build -t test-build .
```

---

## 🔍 Advanced Debugging Techniques

### Get Shell Access for Debugging
```bash
# Start bash in running container
docker exec -it <container_id> /bin/bash

# Start sh if bash not available
docker exec -it <container_id> /bin/sh

# Run as root even if container uses different user
docker exec -it --user root <container_id> /bin/bash

# Debug stopped container by overriding entrypoint
docker run -it --entrypoint /bin/bash <image_name>
```

### Inspect Container Filesystem
```bash
# Copy file from container to host
docker cp <container_id>:/path/to/file ./local-file

# Copy from host to container
docker cp ./local-file <container_id>:/path/to/file

# View container's filesystem changes
docker diff <container_id>
```

### Real-time Log Monitoring
```bash
# Follow logs from multiple containers
docker-compose logs -f service1 service2

# Filter logs by string
docker logs <container_id> 2>&1 | grep ERROR

# Get logs between time range
docker logs --since "2024-01-20T15:00:00" \
            --until "2024-01-20T16:00:00" <container_id>

# Save logs to file
docker logs <container_id> > container.log 2>&1
```

---

## 📊 Systematic Troubleshooting Checklist

When a container fails, follow this order:

```bash
# 1. Check container status
docker ps -a | grep <container_name>

# 2. Get exit code
docker inspect <container_id> --format='{{.State.ExitCode}}'

# 3. Check logs immediately
docker logs --tail 50 <container_id>

# 4. Check resource usage
docker stats --no-stream <container_id>

# 5. Inspect full configuration
docker inspect <container_id>

# 6. Check network connectivity
docker exec <container_id> ping -c 2 8.8.8.8

# 7. Verify mounts
docker inspect <container_id> --format='{{json .Mounts}}'

# 8. Check environment
docker exec <container_id> env

# 9. Get interactive shell
docker exec -it <container_id> /bin/bash

# 10. Check disk space
docker system df
```

---

## 🎓 Practice Lab Scenarios

### Scenario 1: Database Connection Failure
```bash
# Start a container expecting postgres but postgres not running
docker run -d --name webapp \
  -e DATABASE_URL=postgresql://postgres:5432/mydb \
  your-app-image

# Diagnose:
docker logs webapp
# Look for: "connection refused", "could not connect"

# Fix: Start postgres first
docker run -d --name postgres \
  -e POSTGRES_DB=mydb \
  postgres:14

# Recreate webapp connected to postgres network
docker network create app-net
docker network connect app-net postgres
docker rm -f webapp
docker run -d --name webapp \
  --network app-net \
  -e DATABASE_URL=postgresql://postgres:5432/mydb \
  your-app-image
```

### Scenario 2: Configuration File Missing
```bash
# App expects config file at /app/config.yml
docker run -d --name config-test nginx

# Check logs
docker logs config-test
# May show: "config file not found"

# Diagnose
docker exec config-test ls -la /app/

# Fix: Mount config file
cat > config.yml << EOF
server:
  port: 8080
EOF

docker run -d --name config-fixed \
  -v $(pwd)/config.yml:/app/config.yml:ro \
  nginx

# Verify
docker exec config-fixed cat /app/config.yml
```

### Scenario 3: Port Conflict in Production
```bash
# Simulate production scenario
docker run -d --name prod-app1 -p 8080:8080 nginx
docker run -d --name prod-app2 -p 8080:8080 nginx
# Error: "port is already allocated"

# Diagnose which container owns the port
docker ps --format "table {{.Names}}\t{{.Ports}}" | grep 8080

# Options:
# 1. Use different port
docker run -d --name prod-app2 -p 8081:8080 nginx

# 2. Or stop conflicting container
docker stop prod-app1
docker run -d --name prod-app2 -p 8080:8080 nginx
```

---

## 🚨 Production Troubleshooting Commands

### Quick Health Check Script
```bash
#!/bin/bash
CONTAINER=$1

echo "=== Container Status ==="
docker ps -a | grep $CONTAINER

echo -e "\n=== Last 20 Log Lines ==="
docker logs --tail 20 $CONTAINER

echo -e "\n=== Resource Usage ==="
docker stats --no-stream $CONTAINER

echo -e "\n=== Restart Count ==="
docker inspect $CONTAINER --format='Restarts: {{.RestartCount}}'

echo -e "\n=== Network ==="
docker inspect $CONTAINER --format='IP: {{.NetworkSettings.IPAddress}}'

echo -e "\n=== Ports ==="
docker port $CONTAINER
```

### Save to file and make executable
```bash
chmod +x docker-health-check.sh
./docker-health-check.sh <container_name>
```

---

## 💡 Key Takeaways

1. **Always check logs first** - 90% of issues are visible in logs
2. **Use `docker inspect`** - Complete container configuration in JSON
3. **Monitor resources** - Use `docker stats` to catch resource exhaustion
4. **Test incrementally** - Start with minimal config, add complexity
5. **Check networking** - Use `docker exec` to ping/curl from inside
6. **Verify permissions** - Common issue with volume mounts
7. **Exit codes matter** - They tell you how the container died
8. **Use `--rm` for tests** - Auto-cleanup test containers
9. **Follow logs in real-time** - Use `-f` flag during debugging
10. **Document solutions** - Keep a runbook of common fixes

---

## 📚 Quick Reference Card

| Issue Type | First Command | Key Log Pattern |
|------------|---------------|-----------------|
| Won't start | `docker logs <id>` | ERROR, Exception, Permission |
| Crashes | `docker stats <id>` | OOMKilled, SIGTERM |
| Network | `docker exec <id> ping` | Connection refused, timeout |
| Volume | `docker inspect <id>` | Permission denied, No such file |
| Port | `netstat -tulpn` | Address already in use |
| Config | `docker exec <id> env` | undefined, not found |

---

**Remember**: The key to effective troubleshooting is following a systematic approach, not random trial-and-error. Always start with logs, verify configuration, then test hypothesis.
