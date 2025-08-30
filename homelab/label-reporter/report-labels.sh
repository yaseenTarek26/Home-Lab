#!/bin/bash
set -euo pipefail

# Configuration
REPORT_DIR="/opt/home-lab/homelab/label-reporter/reports"
REPORT_FILE="$REPORT_DIR/caddy-services.json"
LOG_FILE="/var/log/label-reporter.log"

# Logging function
log() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Create report directory
mkdir -p "$REPORT_DIR"

log "Starting label reporter scan..."

# Get all running containers with caddy.expose=true
containers=$(docker ps --format "{{.Names}}" | while read name; do
    if docker inspect "$name" --format "{{.Config.Labels.caddy.expose}}" | grep -q "true"; then
        echo "$name"
    fi
done)

# Generate report for each container
report="[]"
for container in $containers; do
    log "Processing container: $container"
    
    # Get container info
    labels=$(docker inspect "$container" --format "{{json .Config.Labels}}")
    name=$(docker inspect "$container" --format "{{.Name}}")
    container_id=$(docker inspect "$container" --format "{{.Id}}")
    
    # Extract Caddy labels
    expose=$(echo "$labels" | jq -r ".caddy.expose // empty")
    path=$(echo "$labels" | jq -r ".caddy.path // empty")
    host_port=$(echo "$labels" | jq -r ".caddy.host_port // empty")
    root=$(echo "$labels" | jq -r ".caddy.root // empty")
    fqdn=$(echo "$labels" | jq -r ".caddy.fqdn // empty")
    
    if [[ "$expose" == "true" ]]; then
        # Get container port mapping if host_port not specified
        if [[ -z "$host_port" ]]; then
            port_mapping=$(docker port "$container" 2>/dev/null | head -1 | cut -d: -f2 || echo "")
            if [[ -n "$port_mapping" ]]; then
                host_port="$port_mapping"
                log "Derived host_port $host_port for $container"
            fi
        fi
        
        # Create service entry
        service_entry=$(jq -n \
            --arg name "$name" \
            --arg path "$path" \
            --arg host_port "$host_port" \
            --arg root "$root" \
            --arg fqdn "$fqdn" \
            --arg source "docker-inspect" \
            --arg container_id "$container_id" \
            '{
                name: $name,
                path: $path,
                host_port: $host_port,
                root: $root,
                fqdn: $fqdn,
                source: $source,
                container_id: $container_id
            }')
        
        # Add to report
        report=$(echo "$report" | jq --argjson service "$service_entry" '. += [$service]')
        log "Added service: $name -> $host_port"
    fi
done

# Write report to file
echo "$report" > "$REPORT_FILE"
service_count=$(echo "$report" | jq '. | length')
log "Report generated with $service_count services"

# Optional: Send report to edge server (if configured)
if [[ -n "${EDGE_SERVER_URL:-}" ]]; then
    log "Sending report to edge server: $EDGE_SERVER_URL"
    curl -s -X POST "$EDGE_SERVER_URL/api/services" \
        -H "Content-Type: application/json" \
        -d "$report" || log "Failed to send report to edge server"
fi
