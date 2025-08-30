#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_DIR="/opt/home-lab"
LOG_FILE="/var/log/validation.log"

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_warning "Some checks may fail without root privileges"
fi

echo "🔍 Home-Lab Configuration Validation"
echo "===================================="

# Initialize error counter
errors=0

# Function to check file existence
check_file() {
    local file="$1"
    local description="$2"
    
    if [[ -f "$file" ]]; then
        log_success "$description exists"
        return 0
    else
        log_error "$description missing: $file"
        ((errors++))
        return 1
    fi
}

# Function to check if command exists
check_command() {
    local cmd="$1"
    local description="$2"
    
    if command -v "$cmd" &> /dev/null; then
        log_success "$description available"
        return 0
    else
        log_error "$description not found: $cmd"
        ((errors++))
        return 1
    fi
}

# Function to check systemd service
check_service() {
    local service="$1"
    local description="$2"
    
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        log_success "$description is active"
        return 0
    else
        log_warning "$description is not active: $service"
        return 1
    fi
}

# Function to check systemd timer
check_timer() {
    local timer="$1"
    local description="$2"
    
    if systemctl is-active --quiet "$timer" 2>/dev/null; then
        log_success "$description is active"
        return 0
    else
        log_warning "$description is not active: $timer"
        return 1
    fi
}

# Function to validate edge configuration
validate_edge_config() {
    log_info "Validating Edge Server Configuration..."
    
    # Check core files
    check_file "$REPO_DIR/edge/generate-caddyfile.sh" "Caddyfile generator script"
    check_file "$REPO_DIR/edge/docker-compose.yml" "Edge docker-compose.yml"
    check_file "$REPO_DIR/edge/config.env" "Edge configuration file"
    
    # Check if generate-caddyfile.sh is executable
    if [[ -x "$REPO_DIR/edge/generate-caddyfile.sh" ]]; then
        log_success "Caddyfile generator script is executable"
    else
        log_error "Caddyfile generator script is not executable"
        ((errors++))
    fi
    
    # Check systemd services
    check_file "/etc/systemd/system/caddy-reload.service" "Caddy reload service"
    check_file "/etc/systemd/system/caddy-reload.timer" "Caddy reload timer"
    
    # Check timers
    check_timer "caddy-reload.timer" "Caddy reload timer"
    
    # Check Docker containers
    if docker ps --format '{{.Names}}' | grep -q "edge-caddy"; then
        log_success "Caddy container is running"
    else
        log_error "Caddy container is not running"
        ((errors++))
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "edge-duckdns"; then
        log_success "DuckDNS container is running"
    else
        log_error "DuckDNS container is not running"
        ((errors++))
    fi
    
    # Check Caddyfile
    if [[ -f "$REPO_DIR/edge/Caddyfile" ]]; then
        log_success "Caddyfile exists"
        echo "   Generated Caddyfile content:"
        cat "$REPO_DIR/edge/Caddyfile" | sed 's/^/   /'
    else
        log_error "Caddyfile does not exist"
        ((errors++))
    fi
    
    # Check configuration
    if [[ -f "$REPO_DIR/edge/config.env" ]]; then
        log_info "Edge configuration:"
        grep -E "^(DOMAIN|HOMELAB_IP|ROUTING_MODE)=" "$REPO_DIR/edge/config.env" | sed 's/^/   /'
    fi
}

# Function to validate homelab configuration
validate_homelab_config() {
    log_info "Validating Homelab Server Configuration..."
    
    # Check core files
    check_file "$REPO_DIR/homelab/docker-compose.yml" "Homelab docker-compose.yml"
    
    # Check systemd services
    check_file "/etc/systemd/system/git-sync.service" "Git sync service"
    check_file "/etc/systemd/system/git-sync.timer" "Git sync timer"
    check_file "/etc/systemd/system/docker-redeploy-homelab.service" "Homelab redeploy service"
    check_file "/etc/systemd/system/docker-redeploy-homelab.timer" "Homelab redeploy timer"
    check_file "/etc/systemd/system/label-reporter.service" "Label reporter service"
    check_file "/etc/systemd/system/label-reporter.timer" "Label reporter timer"
    
    # Check timers
    check_timer "git-sync.timer" "Git sync timer"
    check_timer "docker-redeploy-homelab.timer" "Homelab redeploy timer"
    check_timer "label-reporter.timer" "Label reporter timer"
    
    # Check Docker containers
    local container_count=$(docker ps --format '{{.Names}}' | grep -c "homelab-" || echo "0")
    if [[ $container_count -gt 0 ]]; then
        log_success "Found $container_count homelab containers running"
        echo "   Running containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "homelab-" | sed 's/^/   /'
    else
        log_warning "No homelab containers are running"
    fi
    
    # Check label reporter
    if [[ -f "$REPO_DIR/homelab/label-reporter/report-labels.sh" ]]; then
        log_success "Label reporter script exists"
        if [[ -x "$REPO_DIR/homelab/label-reporter/report-labels.sh" ]]; then
            log_success "Label reporter script is executable"
        else
            log_error "Label reporter script is not executable"
            ((errors++))
        fi
    else
        log_warning "Label reporter script not found"
    fi
    
    # Check label reporter reports
    if [[ -f "$REPO_DIR/homelab/label-reporter/reports/caddy-services.json" ]]; then
        log_success "Label reporter reports exist"
        local report_count=$(jq '. | length' "$REPO_DIR/homelab/label-reporter/reports/caddy-services.json" 2>/dev/null || echo "0")
        log_info "Label reporter found $report_count services"
    else
        log_warning "Label reporter reports not found"
    fi
}

# Function to validate common configuration
validate_common_config() {
    log_info "Validating Common Configuration..."
    
    # Check scripts
    check_file "$REPO_DIR/common/scripts/git-sync.sh" "Git sync script"
    
    # Check if git-sync.sh is executable
    if [[ -x "$REPO_DIR/common/scripts/git-sync.sh" ]]; then
        log_success "Git sync script is executable"
    else
        log_error "Git sync script is not executable"
        ((errors++))
    fi
    
    # Check Docker network
    if docker network ls | grep -q "homelab-net"; then
        log_success "homelab-net Docker network exists"
    else
        log_error "homelab-net Docker network not found"
        ((errors++))
    fi
    
    # Check repository structure
    local required_dirs=("edge" "homelab" "common/scripts" "common/systemd")
    for dir in "${required_dirs[@]}"; do
        if [[ -d "$REPO_DIR/$dir" ]]; then
            log_success "Directory exists: $dir"
        else
            log_error "Directory missing: $dir"
            ((errors++))
        fi
    done
}

# Function to validate Docker
validate_docker() {
    log_info "Validating Docker Installation..."
    
    # Check Docker daemon
    if systemctl is-active --quiet docker; then
        log_success "Docker daemon is running"
    else
        log_error "Docker daemon is not running"
        ((errors++))
    fi
    
    # Check Docker Compose
    check_command "docker" "Docker CLI"
    check_command "docker compose" "Docker Compose"
    
    # Check Docker permissions
    if docker ps &> /dev/null; then
        log_success "Docker permissions are correct"
    else
        log_error "Docker permissions issue - user may not be in docker group"
        ((errors++))
    fi
}

# Function to validate network connectivity
validate_network() {
    log_info "Validating Network Connectivity..."
    
    # Check internet connectivity
    if ping -c 1 google.com &> /dev/null; then
        log_success "Internet connectivity is working"
    else
        log_error "No internet connectivity"
        ((errors++))
    fi
    
    # Check if we can determine server type
    if [[ -f "$REPO_DIR/edge/generate-caddyfile.sh" && -f "$REPO_DIR/homelab/docker-compose.yml" ]]; then
        log_info "Both edge and homelab configurations found - this appears to be a development environment"
    elif [[ -f "$REPO_DIR/edge/generate-caddyfile.sh" ]]; then
        log_info "Edge server configuration detected"
        validate_edge_config
    elif [[ -f "$REPO_DIR/homelab/docker-compose.yml" ]]; then
        log_info "Homelab server configuration detected"
        validate_homelab_config
    else
        log_error "Neither edge nor homelab configuration found"
        ((errors++))
    fi
}

# Function to validate routing configuration
validate_routing() {
    log_info "Validating Routing Configuration..."
    
    # Check routing mode
    if [[ -f "$REPO_DIR/edge/config.env" ]]; then
        local routing_mode=$(grep "^ROUTING_MODE=" "$REPO_DIR/edge/config.env" | cut -d'=' -f2)
        if [[ "$routing_mode" == "path" ]]; then
            log_success "Using path-based routing (DuckDNS compatible)"
        elif [[ "$routing_mode" == "subdomain" ]]; then
            log_success "Using subdomain routing (wildcard DNS required)"
        else
            log_warning "Unknown routing mode: $routing_mode"
        fi
    fi
    
    # Check for path collisions in homelab services
    if [[ -f "$REPO_DIR/homelab/docker-compose.yml" ]]; then
        local paths=$(grep -A 10 "caddy.path:" "$REPO_DIR/homelab/docker-compose.yml" | grep -v "caddy.path:" | grep -E '"/[^"]*"' | sed 's/.*"\([^"]*\)".*/\1/' | sort | uniq -d)
        if [[ -n "$paths" ]]; then
            log_warning "Path collisions detected: $paths"
        else
            log_success "No path collisions detected"
        fi
    fi
}

# Function to provide recommendations
provide_recommendations() {
    echo
    log_info "Recommendations:"
    
    if [[ $errors -eq 0 ]]; then
        log_success "Configuration looks good! No critical issues found."
    else
        log_warning "Found $errors critical issue(s) that need to be addressed."
    fi
    
    # Check for common issues
    if ! systemctl is-active --quiet docker; then
        echo "   - Start Docker: sudo systemctl start docker"
    fi
    
    if ! systemctl is-enabled --quiet docker; then
        echo "   - Enable Docker: sudo systemctl enable docker"
    fi
    
    # Check for missing tools
    if ! command -v yq &> /dev/null; then
        echo "   - Install yq: curl -sSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq"
    fi
    
    if ! command -v jq &> /dev/null; then
        echo "   - Install jq: sudo apt update && sudo apt install -y jq"
    fi
    
    # Check for configuration issues
    if [[ -f "$REPO_DIR/edge/config.env" ]]; then
        if grep -q "yourname.duckdns.org" "$REPO_DIR/edge/config.env"; then
            echo "   - Update DOMAIN in $REPO_DIR/edge/config.env"
        fi
        if grep -q "100.x.x.x" "$REPO_DIR/edge/config.env"; then
            echo "   - Update HOMELAB_IP in $REPO_DIR/edge/config.env"
        fi
    fi
    
    echo
    log_info "Useful Commands:"
    echo "   - View logs: tail -f /var/log/caddy-generator.log"
    echo "   - Check services: systemctl status caddy-reload.timer"
    echo "   - Manual generation: cd $REPO_DIR/edge && ./generate-caddyfile.sh"
    echo "   - Test connectivity: ping \$HOMELAB_IP"
}

# Main validation function
main() {
    echo "$(date): Starting configuration validation..." >> "$LOG_FILE"
    
    # Validate basic requirements
    validate_docker
    validate_common_config
    validate_network
    validate_routing
    
    # Provide recommendations
    provide_recommendations
    
    echo "$(date): Configuration validation completed with $errors errors" >> "$LOG_FILE"
    
    # Exit with error count
    exit $errors
}

# Run main function
main "$@"
