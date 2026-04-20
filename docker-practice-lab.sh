#!/bin/bash

# Docker Troubleshooting Practice Lab
# This script creates intentional errors for practice

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Docker Troubleshooting Practice Lab ===${NC}\n"

# Function to wait for user
wait_for_user() {
    echo -e "\n${YELLOW}Press Enter to continue...${NC}"
    read
}

# Function to cleanup
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm $(docker ps -aq) 2>/dev/null || true
    docker volume rm practice-volume 2>/dev/null || true
    docker network rm practice-net 2>/dev/null || true
    rm -f test-app.js test-config.yml
    echo -e "${GREEN}Cleanup complete!${NC}"
}

# Trap cleanup on exit
trap cleanup EXIT

echo "This script will create various Docker issues for you to troubleshoot."
echo "For each scenario, try to diagnose the issue before looking at the solution."
wait_for_user

# ============================================
# SCENARIO 1: Container Exits Immediately
# ============================================
echo -e "\n${RED}=== SCENARIO 1: Container Exits Immediately ===${NC}"
echo "Starting a container that will fail..."

docker run -d --name exit-fail ubuntu wrongcommand 2>/dev/null || true
sleep 2

echo -e "\n${YELLOW}Your Task:${NC}"
echo "1. Check why the container exited"
echo "2. Find the exit code"
echo "3. Check the logs"
echo ""
echo "Commands to try:"
echo "  docker ps -a | grep exit-fail"
echo "  docker logs exit-fail"
echo "  docker inspect exit-fail --format='{{.State.ExitCode}}'"

wait_for_user

echo -e "\n${GREEN}Solution:${NC}"
docker ps -a | grep exit-fail
echo ""
docker logs exit-fail 2>&1
echo ""
echo "Exit code:"
docker inspect exit-fail --format='ExitCode: {{.State.ExitCode}}' 2>/dev/null || echo "Container not found"
echo -e "\n${GREEN}Exit code 127 = Command not found${NC}"

docker rm -f exit-fail 2>/dev/null || true

# ============================================
# SCENARIO 2: Port Already in Use
# ============================================
echo -e "\n${RED}=== SCENARIO 2: Port Already in Use ===${NC}"
echo "Starting first container on port 8080..."

docker run -d --name port-first -p 8080:80 nginx
sleep 2

echo "Now trying to start second container on same port..."
docker run -d --name port-second -p 8080:80 nginx 2>&1 || true

echo -e "\n${YELLOW}Your Task:${NC}"
echo "1. Identify which container is using port 8080"
echo "2. Verify the port binding"
echo ""
echo "Commands to try:"
echo "  docker ps --format 'table {{.Names}}\t{{.Ports}}'"
echo "  docker port port-first"
echo "  sudo netstat -tulpn | grep 8080"
echo "  docker inspect port-first --format='{{json .NetworkSettings.Ports}}'"

wait_for_user

echo -e "\n${GREEN}Solution:${NC}"
docker ps --format 'table {{.Names}}\t{{.Ports}}'
echo ""
echo "Port binding for port-first:"
docker port port-first
echo -e "\n${GREEN}Fix: Use a different host port (e.g., 8081:80)${NC}"

docker rm -f port-first 2>/dev/null || true
docker rm -f port-second 2>/dev/null || true

# ============================================
# SCENARIO 3: Environment Variable Missing
# ============================================
echo -e "\n${RED}=== SCENARIO 3: Environment Variable Missing ===${NC}"

cat > test-app.js << 'EOF'
const dbUrl = process.env.DATABASE_URL;
if (!dbUrl) {
  console.error('FATAL: DATABASE_URL environment variable not set!');
  process.exit(1);
}
console.log('✓ Connected to database:', dbUrl);
EOF

echo "Created a Node.js app that requires DATABASE_URL..."
docker run -d --name env-fail \
  -v $(pwd)/test-app.js:/app/app.js \
  node:18-alpine node /app/app.js 2>/dev/null || true

sleep 2

echo -e "\n${YELLOW}Your Task:${NC}"
echo "1. Check the container logs"
echo "2. Verify what environment variables are set"
echo "3. Fix by adding the missing variable"
echo ""
echo "Commands to try:"
echo "  docker logs env-fail"
echo "  docker inspect env-fail --format='{{range .Config.Env}}{{println .}}{{end}}'"
echo "  docker exec env-fail env (if container was running)"

wait_for_user

echo -e "\n${GREEN}Solution:${NC}"
echo "Container logs:"
docker logs env-fail 2>&1
echo ""
echo "Environment variables:"
docker inspect env-fail --format='{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null || echo "Container not found"

echo -e "\n${GREEN}Fix: Add -e DATABASE_URL=postgresql://db:5432/myapp${NC}"
docker rm -f env-fail 2>/dev/null || true

docker run -d --name env-success \
  -e DATABASE_URL=postgresql://db:5432/myapp \
  -v $(pwd)/test-app.js:/app/app.js \
  node:18-alpine node /app/app.js

sleep 2
echo "Fixed container logs:"
docker logs env-success 2>&1

docker rm -f env-success 2>/dev/null || true

# ============================================
# SCENARIO 4: Volume Permission Denied
# ============================================
echo -e "\n${RED}=== SCENARIO 4: Volume Permission Issue ===${NC}"

docker volume create practice-volume 2>/dev/null || true

echo "Creating container with volume mount as non-root user..."
docker run -d --name vol-fail \
  -v practice-volume:/data \
  --user 1001:1001 \
  ubuntu bash -c "echo 'test' > /data/file.txt && sleep 3600" 2>/dev/null || true

sleep 2

echo -e "\n${YELLOW}Your Task:${NC}"
echo "1. Check if container is running or exited"
echo "2. Check logs for permission errors"
echo "3. Inspect the volume mount configuration"
echo ""
echo "Commands to try:"
echo "  docker ps -a | grep vol-fail"
echo "  docker logs vol-fail"
echo "  docker inspect vol-fail --format='{{json .Mounts}}' | jq"
echo "  docker exec vol-fail ls -la /data"

wait_for_user

echo -e "\n${GREEN}Solution:${NC}"
docker ps -a | grep vol-fail
echo ""
echo "Container logs:"
docker logs vol-fail 2>&1
echo ""
echo "Mounts:"
docker inspect vol-fail --format='{{json .Mounts}}' 2>/dev/null || echo "Container not found"

echo -e "\n${GREEN}Fix: Pre-set correct permissions on volume${NC}"
docker rm -f vol-fail 2>/dev/null || true

# Fix permissions first
docker run --rm -v practice-volume:/data alpine chown -R 1001:1001 /data

# Now retry
docker run -d --name vol-success \
  -v practice-volume:/data \
  --user 1001:1001 \
  ubuntu bash -c "echo 'test' > /data/file.txt && cat /data/file.txt && sleep 3600"

sleep 2
echo "Fixed container logs:"
docker logs vol-success 2>&1

docker rm -f vol-success 2>/dev/null || true
docker volume rm practice-volume 2>/dev/null || true

# ============================================
# SCENARIO 5: Network Connectivity
# ============================================
echo -e "\n${RED}=== SCENARIO 5: Network Connectivity Issue ===${NC}"

docker network create practice-net 2>/dev/null || true

echo "Creating two containers in different networks..."
docker run -d --name net-isolated --network practice-net nginx
docker run -d --name net-default nginx

sleep 2

echo -e "\n${YELLOW}Your Task:${NC}"
echo "1. Try to ping net-default from net-isolated (it will fail)"
echo "2. Check which networks each container is connected to"
echo "3. Fix the connectivity"
echo ""
echo "Commands to try:"
echo "  docker exec net-isolated ping -c 2 net-default"
echo "  docker inspect net-isolated --format='{{json .NetworkSettings.Networks}}'"
echo "  docker network ls"
echo "  docker network inspect practice-net"

wait_for_user

echo -e "\n${GREEN}Solution:${NC}"
echo "Attempting to ping (will fail):"
docker exec net-isolated ping -c 2 net-default 2>&1 || echo "Ping failed - expected!"
echo ""
echo "Networks for net-isolated:"
docker inspect net-isolated --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}'
echo ""
echo "Networks for net-default:"
docker inspect net-default --format='{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}'

echo -e "\n${GREEN}Fix: Connect net-isolated to bridge network${NC}"
docker network connect bridge net-isolated

echo "Now ping should work:"
docker exec net-isolated ping -c 2 net-default 2>&1 || echo "Still not working - DNS issue"

docker rm -f net-isolated net-default 2>/dev/null || true
docker network rm practice-net 2>/dev/null || true

# ============================================
# SCENARIO 6: Resource Limits (Memory)
# ============================================
echo -e "\n${RED}=== SCENARIO 6: Memory Limit / OOMKill ===${NC}"

echo "Creating container with 50MB memory limit that will exceed it..."
docker run -d --name mem-limit \
  --memory="50m" \
  ubuntu bash -c "sleep 2 && yes | tr \\n x | head -c 100m | grep n" 2>/dev/null || true

echo "Waiting for OOMKill..."
sleep 5

echo -e "\n${YELLOW}Your Task:${NC}"
echo "1. Check if container was OOMKilled"
echo "2. Find the exit code"
echo "3. Check resource limits"
echo ""
echo "Commands to try:"
echo "  docker ps -a | grep mem-limit"
echo "  docker inspect mem-limit --format='{{.State.OOMKilled}}'"
echo "  docker inspect mem-limit --format='{{.State.ExitCode}}'"
echo "  docker inspect mem-limit --format='Memory Limit: {{.HostConfig.Memory}}'"
echo "  docker logs mem-limit"

wait_for_user

echo -e "\n${GREEN}Solution:${NC}"
docker ps -a | grep mem-limit
echo ""
echo "Was OOMKilled:"
docker inspect mem-limit --format='OOMKilled: {{.State.OOMKilled}}' 2>/dev/null || echo "Container not found"
echo ""
echo "Exit Code:"
docker inspect mem-limit --format='ExitCode: {{.State.ExitCode}}' 2>/dev/null || echo "Container not found"
echo ""
echo "Memory Limit:"
docker inspect mem-limit --format='Memory: {{.HostConfig.Memory}} bytes ({{div .HostConfig.Memory 1048576}} MB)' 2>/dev/null || echo "Container not found"

echo -e "\n${GREEN}Exit code 137 = OOMKilled (Out of Memory)${NC}"

docker rm -f mem-limit 2>/dev/null || true

# ============================================
# SCENARIO 7: Configuration File Missing
# ============================================
echo -e "\n${RED}=== SCENARIO 7: Missing Configuration File ===${NC}"

echo "Creating container expecting a config file..."
docker run -d --name config-missing \
  nginx 2>/dev/null || true

sleep 2

echo -e "\n${YELLOW}Your Task:${NC}"
echo "Simulate: App expects /app/config.yml"
echo "1. Try to check if file exists inside container"
echo "2. Mount the configuration file"
echo ""
echo "Commands to try:"
echo "  docker exec config-missing ls -la /app/"
echo "  docker exec config-missing cat /app/config.yml"

wait_for_user

echo -e "\n${GREEN}Solution:${NC}"
echo "Checking for config file:"
docker exec config-missing ls -la /app/ 2>&1 || echo "Directory doesn't exist"

cat > test-config.yml << EOF
database:
  host: localhost
  port: 5432
server:
  port: 8080
EOF

echo -e "\n${GREEN}Fix: Mount config file as volume${NC}"
echo "docker run -v \$(pwd)/test-config.yml:/app/config.yml:ro nginx"

docker rm -f config-missing 2>/dev/null || true

# ============================================
# Summary
# ============================================
echo -e "\n${GREEN}=== Practice Lab Complete! ===${NC}\n"

echo "Key Commands Summary:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Status:        docker ps -a"
echo "2. Logs:          docker logs <container>"
echo "3. Inspect:       docker inspect <container>"
echo "4. Resources:     docker stats <container>"
echo "5. Exec:          docker exec -it <container> /bin/bash"
echo "6. Network:       docker network inspect <network>"
echo "7. Volume:        docker volume inspect <volume>"
echo "8. Exit Code:     docker inspect <id> --format='{{.State.ExitCode}}'"
echo "9. Environment:   docker inspect <id> --format='{{range .Config.Env}}{{println .}}{{end}}'"
echo "10. Ports:        docker port <container>"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo -e "\n${YELLOW}Common Exit Codes:${NC}"
echo "  0   - Normal exit"
echo "  1   - Application error"
echo "  137 - OOMKilled (Out of Memory)"
echo "  139 - Segmentation fault"
echo "  143 - SIGTERM received"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Review the full guide: docker-troubleshooting-guide.md"
echo "2. Practice on your own containers"
echo "3. Create your own scenarios"
echo "4. Build a troubleshooting runbook for your team"

echo -e "\n${GREEN}Cleanup completed automatically!${NC}"
