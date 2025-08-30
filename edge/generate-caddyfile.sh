#!/usr/bin/env bash
set -euo pipefail

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${EDGE_DIR}/Caddyfile"
TMP="$(mktemp)"
LOG_FILE="/var/log/caddy-generator.log"

# User-configurable settings
DOMAIN="${DOMAIN:-yourname.duckdns.org}"
HOMELAB_IP="${HOMELAB_IP:-100.x.x.x}"
ROUTING_MODE="${ROUTING_MODE:-path}"  # "path" or "subdomain"
ENABLE_VALIDATION="${ENABLE_VALIDATION:-true}"
ENABLE_DEBUG="${ENABLE_DEBUG:-false}"

# Logging function
log() {
    echo "$(date): $1" >> "$LOG_FILE"
    if [[ "$ENABLE_DEBUG" == "true" ]]; then
        echo "$1"
    fi
}

# Error handling
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Validation function
validate_requirements() {
    log "Validating requirements..."
    
    # Check for required tools
    if ! command -v yq >/dev/null 2>&1; then
        error_exit "yq is required but not installed. Run: curl -sSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq"
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        error_exit "jq is required but not installed. Run: apt update && apt install -y jq"
    fi
    
    # Validate configuration
    if [[ -z "$DOMAIN" || "$DOMAIN" == "yourname.duckdns.org" ]]; then
        error_exit "DOMAIN is not configured. Set DOMAIN environment variable or edit this script."
    fi
    
    if [[ -z "$HOMELAB_IP" || "$HOMELAB_IP" == "100.x.x.x" ]]; then
        error_exit "HOMELAB_IP is not configured. Set HOMELAB_IP environment variable or edit this script."
    fi
    
    if [[ "$ROUTING_MODE" != "path" && "$ROUTING_MODE" != "subdomain" ]]; then
        error_exit "ROUTING_MODE must be 'path' or 'subdomain', got: $ROUTING_MODE"
    fi
    
    log "Requirements validation passed"
}

# Parse compose files and extract services
parse_services() {
    log "Parsing compose files for services..."
    
    local services_json="[]"
    local service_count=0
    
    # Method 1: Parse compose files
    while IFS= read -r -d '' f; do
        log "Processing compose file: $f"
        
        # Extract services with caddy labels
        local file_services=$(yq -r '
            .services
            | to_entries[]
            | {name: .key, labels: (.value.labels // {})}
            | select(.labels["caddy.expose"] == "true")
            | {
                name,
                path: (.labels["caddy.path"] // ""),
                host_port: (.labels["caddy.host_port"] // ""),
                root: (.labels["caddy.root"] // ""),
                fqdn: (.labels["caddy.fqdn"] // ""),
                source_file: "'"$f"'",
                source: "compose-file"
              }
        ' "$f" 2>/dev/null | yq -r -s '.' | jq -c '.[]' 2>/dev/null || echo "")
        
        if [[ -n "$file_services" ]]; then
            while read -r svc; do
                services_json=$(echo "$services_json" | jq --argjson svc "$svc" '. += [$svc]')
                ((service_count++))
            done <<< "$file_services"
        fi
    done < <(find "${REPO_ROOT}/homelab" -type f -name 'docker-compose.yml' -print0)
    
    # Method 2: Read from label reporter (if available)
    local label_reporter_file="${REPO_ROOT}/homelab/label-reporter/reports/caddy-services.json"
    if [[ -f "$label_reporter_file" ]]; then
        log "Reading from label reporter: $label_reporter_file"
        local reporter_services=$(jq -c '.[]' "$label_reporter_file" 2>/dev/null || echo "")
        if [[ -n "$reporter_services" ]]; then
            while read -r svc; do
                # Add source information
                svc_with_source=$(echo "$svc" | jq '.source = "label-reporter"')
                services_json=$(echo "$services_json" | jq --argjson svc "$svc_with_source" '. += [$svc]')
                ((service_count++))
            done <<< "$reporter_services"
        fi
    else
        log "Label reporter file not found: $label_reporter_file"
    fi
    
    log "Found $service_count total services with Caddy labels"
    echo "$services_json"
}

# Validate services for conflicts and issues
validate_services() {
    local services_json="$1"
    
    if [[ "$ENABLE_VALIDATION" != "true" ]]; then
        return 0
    fi
    
    log "Validating services..."
    
    # Check for missing host_port
    local missing_ports=$(echo "$services_json" | jq -r '.[] | select(.host_port == "") | .name')
    if [[ -n "$missing_ports" ]]; then
        log "WARNING: Services missing caddy.host_port: $missing_ports"
    fi
    
    # Check for path collisions (only in path mode)
    if [[ "$ROUTING_MODE" == "path" ]]; then
        local path_collisions=$(echo "$services_json" | jq -r '.[] | select(.path != "" and .path != "/") | .path' | sort | uniq -d)
        if [[ -n "$path_collisions" ]]; then
            log "WARNING: Path collisions detected: $path_collisions"
            log "WARNING: Only the last service with each path will be active"
        fi
    fi
    
    # Check for subdomain collisions (only in subdomain mode)
    if [[ "$ROUTING_MODE" == "subdomain" ]]; then
        local subdomain_collisions=$(echo "$services_json" | jq -r '.[] | select(.path != "" and .path != "/") | .path | ltrimstr("/")' | sort | uniq -d)
        if [[ -n "$subdomain_collisions" ]]; then
            log "WARNING: Subdomain collisions detected: $subdomain_collisions"
            log "WARNING: Only the last service with each subdomain will be active"
        fi
    fi
    
    # Check for multiple root services
    local root_services=$(echo "$services_json" | jq -r '.[] | select(.root == "true") | .name')
    local root_count=$(echo "$root_services" | wc -l)
    if [[ $root_count -gt 1 ]]; then
        log "WARNING: Multiple root services detected: $root_services"
        log "WARNING: Only the last root service will be active"
    fi
}

# Generate Caddyfile content
generate_caddyfile() {
    local services_json="$1"
    
    log "Generating Caddyfile with $ROUTING_MODE routing mode..."
    
    # Start with header
    cat > "$TMP" <<EOF
# Auto-generated Caddyfile
# Generated on: $(date)
# Routing mode: $ROUTING_MODE
# Domain: $DOMAIN
# Homelab IP: $HOMELAB_IP

EOF
    
    # Handle root domain
    local root_service=$(echo "$services_json" | jq -r '.[] | select(.root == "true") | .name' | tail -1)
    if [[ -n "$root_service" && "$root_service" != "null" ]]; then
        local root_port=$(echo "$services_json" | jq -r ".[] | select(.name == \"$root_service\") | .host_port")
        log "Setting root domain to service: $root_service on port $root_port"
        cat >> "$TMP" <<EOF
# Root domain
$DOMAIN {
    reverse_proxy $HOMELAB_IP:$root_port
}
EOF
    else
        # Default root domain (website service)
        log "Using default root domain (website service)"
        cat >> "$TMP" <<EOF
# Root domain (default)
$DOMAIN {
    reverse_proxy $HOMELAB_IP:8080
}
EOF
    fi
    
    # Process each service
    echo "$services_json" | jq -c '.[]' | while read -r svc; do
        local name=$(jq -r '.name' <<<"$svc")
        local path=$(jq -r '.path' <<<"$svc")
        local host_port=$(jq -r '.host_port' <<<"$svc")
        local root=$(jq -r '.root' <<<"$svc")
        local fqdn=$(jq -r '.fqdn' <<<"$svc")
        
        # Skip if missing host_port
        if [[ -z "$host_port" || "$host_port" == "null" ]]; then
            log "Skipping $name (no caddy.host_port)"
            continue
        fi
        
        # Skip root services (already handled above)
        if [[ "$root" == "true" ]]; then
            continue
        fi
        
        # Handle FQDN (full domain)
        if [[ -n "$fqdn" && "$fqdn" != "null" ]]; then
            log "Adding FQDN service: $name -> $fqdn:$host_port"
            cat >> "$TMP" <<EOF

# FQDN service: $name
$fqdn {
    reverse_proxy $HOMELAB_IP:$host_port
}
EOF
        # Handle path-based routing
        elif [[ "$ROUTING_MODE" == "path" && -n "$path" && "$path" != "null" ]]; then
            log "Adding path service: $name -> $path:$host_port"
            cat >> "$TMP" <<EOF

# Path service: $name
$DOMAIN {
    handle_path $path* {
        reverse_proxy $HOMELAB_IP:$host_port
    }
}
EOF
        # Handle subdomain routing
        elif [[ "$ROUTING_MODE" == "subdomain" && -n "$path" && "$path" != "null" ]]; then
            local subdomain=$(echo "$path" | sed 's|^/||')
            if [[ -n "$subdomain" ]]; then
                log "Adding subdomain service: $name -> $subdomain.$DOMAIN:$host_port"
                cat >> "$TMP" <<EOF

# Subdomain service: $name
${subdomain}.$DOMAIN {
    reverse_proxy $HOMELAB_IP:$host_port
}
EOF
            fi
        fi
    done
    
    log "Caddyfile generation completed"
}

# Reload Caddy if configuration changed
reload_caddy() {
    # Change detection
    if [[ -f "$OUTPUT" ]] && cmp -s "$OUTPUT" "$TMP"; then
        log "Caddyfile unchanged; skipping reload."
        rm -f "$TMP"
        return 0
    fi
    
    # Move new file to output
    mv "$TMP" "$OUTPUT"
    log "Caddyfile updated. Reloading Caddy..."
    
    # Ensure Caddy is running
    if ! docker ps --format '{{.Names}}' | grep -q "edge-caddy"; then
        log "Caddy container not running, starting it..."
        docker compose -f "${EDGE_DIR}/docker-compose.yml" up -d caddy
        sleep 5
    fi
    
    # Reload Caddy
    if docker exec edge-caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile; then
        log "Caddy reloaded successfully"
    else
        error_exit "Failed to reload Caddy"
    fi
}

# Main function
main() {
    log "Starting Caddyfile generation (mode: $ROUTING_MODE)"
    
    # Validate requirements
    validate_requirements
    
    # Parse services
    local services_json=$(parse_services)
    
    # Validate services
    validate_services "$services_json"
    
    # Generate Caddyfile
    generate_caddyfile "$services_json"
    
    # Reload Caddy
    reload_caddy
    
    log "Caddyfile generation completed successfully"
}

# Run main function
main "$@"
