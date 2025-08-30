#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_error() { echo -e "${RED}❌ $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️ $1${NC}"; }

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check Tailscale connectivity
check_tailscale() {
    if ! command -v tailscale >/dev/null 2>&1; then
        log_error "Tailscale is not installed"
        exit 1
    fi
    
    if ! tailscale status >/dev/null 2>&1; then
        log_error "Tailscale is not connected. Please run 'tailscale up' first"
        exit 1
    fi
    log_success "Tailscale connection verified"
}

# Check required ports
check_ports() {
    local ports=(80 443 8080)
    for port in "${ports[@]}"; do
        if lsof -i ":$port" >/dev/null 2>&1; then
            log_error "Port $port is already in use"
            exit 1
        fi
    done
    log_success "Required ports are available"
}

# Check Docker volumes
check_volumes() {
    local volumes=(
        "/opt/home-lab/data"
        "/opt/home-lab/config"
        "/opt/home-lab/backups"
    )
    for dir in "${volumes[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "Failed to create volume directory: $dir"
            exit 1
        fi
        if ! chmod 755 "$dir"; then
            log_error "Failed to set permissions on: $dir"
            exit 1
        fi
    done
    log_success "Volume directories verified"
}

# Check environment variables
check_env() {
    if [ ! -f .env ]; then
        log_error ".env file not found. Please copy .env.example to .env and configure it"
        exit 1
    fi
    
    required_vars=(
        "DUCKDNS_TOKEN"
        "DUCKDNS_SUBDOMAIN"
        "TAILSCALE_AUTH_KEY"
    )
    
    for var in "${required_vars[@]}"; do
        if ! grep -q "^${var}=" .env; then
            log_error "Missing required environment variable: $var"
            exit 1
        fi
    done
    log_success "Environment configuration verified"
}

# Main validation
main() {
    echo "🔍 Running system validation checks..."
    check_root
    check_tailscale
    check_ports
    check_volumes
    check_env
    echo "✅ All validation checks passed successfully!"
}

main "$@"
