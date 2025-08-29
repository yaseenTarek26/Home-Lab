#!/usr/bin/env bash
set -euo pipefail

OUTPUT="Caddyfile"
DOMAIN="yourname.duckdns.org"
HOMELAB_IP="100.x.x.x" # Tailscale IP of homelab server

echo "$(date): Generating Caddyfile from Docker labels..." >> /var/log/caddy-generator.log

# Base/root domain (e.g. website)
cat > "$OUTPUT" <<EOF
$DOMAIN {
    reverse_proxy $HOMELAB_IP:8080
}
EOF

# Scan Docker labels for subdomains
docker ps --format '{{.Names}}' | while read -r container; do
    subdomain=$(docker inspect -f '{{ index .Config.Labels "caddy.subdomain" }}' "$container" || true)
    port=$(docker inspect -f '{{ index .Config.Labels "caddy.port" }}' "$container" || true)

    if [[ -n "$subdomain" && -n "$port" ]]; then
        echo "$(date): Found service: $subdomain -> $HOMELAB_IP:$port" >> /var/log/caddy-generator.log
        cat >> "$OUTPUT" <<EOF

${subdomain}.$DOMAIN {
    reverse_proxy $HOMELAB_IP:${port}
}
EOF
    fi
done

# Reload Caddy automatically if it's running
if docker ps --format '{{.Names}}' | grep -q "edge-caddy"; then
    echo "$(date): Reloading Caddy..." >> /var/log/caddy-generator.log
    docker exec edge-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile || {
        echo "$(date): ERROR - Failed to reload Caddy" >> /var/log/caddy-generator.log
        exit 1
    }
    echo "$(date): Caddy reloaded successfully" >> /var/log/caddy-generator.log
else
    echo "$(date): Caddy container not running, skipping reload" >> /var/log/caddy-generator.log
fi

echo "$(date): Caddyfile generation completed" >> /var/log/caddy-generator.log
