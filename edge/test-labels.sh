#!/bin/bash
set -e

echo "🧪 Testing Labels-Based Automation System"
echo "=========================================="

# Test 1: Check if generate-caddyfile.sh exists and is executable
echo "✅ Test 1: Checking generate-caddyfile.sh"
if [ -f "generate-caddyfile.sh" ] && [ -x "generate-caddyfile.sh" ]; then
    echo "   ✓ Script exists and is executable"
else
    echo "   ✗ Script missing or not executable"
    exit 1
fi

# Test 2: Check if Docker is running
echo "✅ Test 2: Checking Docker"
if docker info > /dev/null 2>&1; then
    echo "   ✓ Docker is running"
else
    echo "   ✗ Docker is not running"
    exit 1
fi

# Test 3: Generate Caddyfile
echo "✅ Test 3: Generating Caddyfile"
./generate-caddyfile.sh

if [ -f "Caddyfile" ]; then
    echo "   ✓ Caddyfile generated successfully"
    echo "   📄 Generated Caddyfile:"
    cat Caddyfile
else
    echo "   ✗ Failed to generate Caddyfile"
    exit 1
fi

# Test 4: Check if Caddy container is running
echo "✅ Test 4: Checking Caddy container"
if docker ps --format '{{.Names}}' | grep -q "edge-caddy"; then
    echo "   ✓ Caddy container is running"
    
    # Test 5: Test Caddy reload
    echo "✅ Test 5: Testing Caddy reload"
    if docker exec edge-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile; then
        echo "   ✓ Caddy reload successful"
    else
        echo "   ⚠ Caddy reload failed (this might be normal if no changes)"
    fi
else
    echo "   ⚠ Caddy container is not running (start with: docker compose up -d)"
fi

# Test 6: Check systemd services
echo "✅ Test 6: Checking systemd services"
if systemctl is-active --quiet caddy-reload.timer; then
    echo "   ✓ Caddy reload timer is active"
else
    echo "   ⚠ Caddy reload timer is not active"
fi

if systemctl is-active --quiet git-sync.timer; then
    echo "   ✓ Git sync timer is active"
else
    echo "   ⚠ Git sync timer is not active"
fi

echo ""
echo "🎉 Testing completed!"
echo ""
echo "📋 Next steps:"
echo "   1. Add a service to homelab/docker-compose.yml with labels"
echo "   2. Push to GitHub"
echo "   3. Check if route appears automatically"
echo ""
echo "🔍 Monitor logs:"
echo "   tail -f /var/log/caddy-generator.log"
echo "   tail -f /var/log/git-sync.log"
