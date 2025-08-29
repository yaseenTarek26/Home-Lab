#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_DIR="/opt/home-lab"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if file exists and is readable
check_file() {
    local file="$1"
    local description="$2"
    
    if [ -f "$file" ] && [ -r "$file" ]; then
        print_success "$description: $file"
        return 0
    else
        print_error "$description: $file (missing or not readable)"
        return 1
    fi
}

# Function to check if directory exists
check_directory() {
    local dir="$1"
    local description="$2"
    
    if [ -d "$dir" ]; then
        print_success "$description: $dir"
        return 0
    else
        print_error "$description: $dir (missing)"
        return 1
    fi
}

# Function to check if service is running
check_service() {
    local service="$1"
    local description="$2"
    
    if systemctl is-active --quiet "$service"; then
        print_success "$description: $service (running)"
        return 0
    else
        print_error "$description: $service (not running)"
        return 1
    fi
}

# Function to check if timer is enabled
check_timer() {
    local timer="$1"
    local description="$2"
    
    if systemctl is-enabled --quiet "$timer"; then
        print_success "$description: $timer (enabled)"
        return 0
    else
        print_error "$description: $timer (not enabled)"
        return 1
    fi
}

# Function to validate edge configuration
validate_edge_config() {
    echo
    echo "🔍 Validating Edge Server Configuration"
    echo "======================================"
    
    local errors=0
    
    # Check edge directory
    check_directory "$REPO_DIR/edge" "Edge directory" || ((errors++))
    
    # Check edge files
    check_file "$REPO_DIR/edge/docker-compose.yml" "Edge docker-compose.yml" || ((errors++))
    check_file "$REPO_DIR/edge/generate-caddyfile.sh" "Caddyfile generator script" || ((errors++))
    check_file "$REPO_DIR/edge/git-sync-trigger.sh" "Git sync trigger script" || ((errors++))
    
    # Check if generate-caddyfile.sh is executable
    if [ -x "$REPO_DIR/edge/generate-caddyfile.sh" ]; then
        print_success "Caddyfile generator script is executable"
    else
        print_error "Caddyfile generator script is not executable"
        ((errors++))
    fi
    
    # Check edge systemd files
    check_file "/etc/systemd/system/caddy-reload.service" "Caddy reload service" || ((errors++))
    check_file "/etc/systemd/system/caddy-reload.timer" "Caddy reload timer" || ((errors++))
    
    # Check edge services
    check_timer "caddy-reload.timer" "Caddy reload timer" || ((errors++))
    
    # Check Docker containers
    if docker ps --format '{{.Names}}' | grep -q "edge-caddy"; then
        print_success "Caddy container is running"
    else
        print_error "Caddy container is not running"
        ((errors++))
    fi
    
    if docker ps --format '{{.Names}}' | grep -q "edge-duckdns"; then
        print_success "DuckDNS container is running"
    else
        print_error "DuckDNS container is not running"
        ((errors++))
    fi
    
    # Check Caddyfile
    if [ -f "$REPO_DIR/edge/Caddyfile" ]; then
        print_success "Caddyfile exists"
        echo "   Generated Caddyfile content:"
        cat "$REPO_DIR/edge/Caddyfile" | sed 's/^/   /'
    else
        print_error "Caddyfile does not exist"
        ((errors++))
    fi
    
    return $errors
}

# Function to validate homelab configuration
validate_homelab_config() {
    echo
    echo "🔍 Validating Homelab Server Configuration"
    echo "========================================="
    
    local errors=0
    
    # Check homelab directory
    check_directory "$REPO_DIR/homelab" "Homelab directory" || ((errors++))
    
    # Check homelab files
    check_file "$REPO_DIR/homelab/docker-compose.yml" "Homelab docker-compose.yml" || ((errors++))
    
    # Check Docker network
    if docker network ls | grep -q "homelab-net"; then
        print_success "Homelab Docker network exists"
    else
        print_error "Homelab Docker network does not exist"
        ((errors++))
    fi
    
    # Check running containers
    local container_count=$(docker ps --format '{{.Names}}' | grep -c "homelab-" || echo "0")
    if [ "$container_count" -gt 0 ]; then
        print_success "Found $container_count homelab containers running"
        echo "   Running containers:"
        docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' | grep "homelab-" | sed 's/^/   /'
    else
        print_warning "No homelab containers are running"
    fi
    
    return $errors
}

# Function to validate common configuration
validate_common_config() {
    echo
    echo "🔍 Validating Common Configuration"
    echo "================================="
    
    local errors=0
    
    # Check common directory
    check_directory "$REPO_DIR/common" "Common directory" || ((errors++))
    
    # Check common files
    check_directory "$REPO_DIR/common/scripts" "Common scripts directory" || ((errors++))
    check_directory "$REPO_DIR/common/systemd" "Common systemd directory" || ((errors++))
    
    # Check git-sync script
    check_file "$REPO_DIR/common/scripts/git-sync.sh" "Git sync script" || ((errors++))
    
    # Check if git-sync script is executable
    if [ -x "$REPO_DIR/common/scripts/git-sync.sh" ]; then
        print_success "Git sync script is executable"
    else
        print_error "Git sync script is not executable"
        ((errors++))
    fi
    
    # Check systemd services
    check_file "/etc/systemd/system/git-sync.service" "Git sync service" || ((errors++))
    check_file "/etc/systemd/system/git-sync.timer" "Git sync timer" || ((errors++))
    check_file "/etc/systemd/system/docker-redeploy-homelab.service" "Homelab redeploy service" || ((errors++))
    check_file "/etc/systemd/system/docker-redeploy-homelab.timer" "Homelab redeploy timer" || ((errors++))
    check_file "/etc/systemd/system/docker-redeploy-edge.service" "Edge redeploy service" || ((errors++))
    check_file "/etc/systemd/system/docker-redeploy-edge.timer" "Edge redeploy timer" || ((errors++))
    
    # Check systemd timers
    check_timer "git-sync.timer" "Git sync timer" || ((errors++))
    check_timer "docker-redeploy-homelab.timer" "Homelab redeploy timer" || ((errors++))
    check_timer "docker-redeploy-edge.timer" "Edge redeploy timer" || ((errors++))
    
    # Check log files
    check_file "/var/log/git-sync.log" "Git sync log file" || ((errors++))
    check_file "/var/log/caddy-generator.log" "Caddy generator log file" || ((errors++))
    
    return $errors
}

# Function to check Docker installation
validate_docker() {
    echo
    echo "🔍 Validating Docker Installation"
    echo "================================"
    
    local errors=0
    
    # Check if Docker is installed
    if command -v docker >/dev/null 2>&1; then
        print_success "Docker is installed"
        
        # Check if Docker daemon is running
        if systemctl is-active --quiet docker; then
            print_success "Docker daemon is running"
        else
            print_error "Docker daemon is not running"
            ((errors++))
        fi
        
        # Check Docker Compose
        if command -v docker-compose >/dev/null 2>&1 || docker compose version >/dev/null 2>&1; then
            print_success "Docker Compose is available"
        else
            print_error "Docker Compose is not available"
            ((errors++))
        fi
        
    else
        print_error "Docker is not installed"
        ((errors++))
    fi
    
    return $errors
}

# Function to check network connectivity
validate_network() {
    echo
    echo "🔍 Validating Network Connectivity"
    echo "================================="
    
    local errors=0
    
    # Check internet connectivity
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        print_success "Internet connectivity is working"
    else
        print_error "Internet connectivity is not working"
        ((errors++))
    fi
    
    # Check GitHub connectivity
    if ping -c 1 github.com >/dev/null 2>&1; then
        print_success "GitHub connectivity is working"
    else
        print_error "GitHub connectivity is not working"
        ((errors++))
    fi
    
    # Check if this is an edge server and has Tailscale
    if [ -d "$REPO_DIR/edge" ]; then
        if command -v tailscale >/dev/null 2>&1; then
            print_success "Tailscale is installed"
            
            # Get Tailscale IP
            local tailscale_ip=$(tailscale ip -4 2>/dev/null || echo "")
            if [ -n "$tailscale_ip" ]; then
                print_success "Tailscale IP: $tailscale_ip"
            else
                print_warning "Tailscale IP not found"
            fi
        else
            print_warning "Tailscale is not installed (may be needed for homelab connectivity)"
        fi
    fi
    
    return $errors
}

# Function to provide recommendations
provide_recommendations() {
    echo
    echo "💡 Recommendations"
    echo "=================="
    
    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Consider using a dedicated user for security."
    fi
    
    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 80 ]; then
        print_warning "Disk usage is high: ${disk_usage}%. Consider cleaning up."
    else
        print_success "Disk usage is good: ${disk_usage}%"
    fi
    
    # Check memory usage
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [ "$mem_usage" -gt 80 ]; then
        print_warning "Memory usage is high: ${mem_usage}%. Consider adding more RAM."
    else
        print_success "Memory usage is good: ${mem_usage}%"
    fi
    
    # Check if firewall is configured
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q "Status: active"; then
            print_success "UFW firewall is active"
        else
            print_warning "UFW firewall is not active"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        print_warning "iptables is available but UFW is recommended for easier management"
    fi
}

# Main function
main() {
    echo "🔍 Home Lab Configuration Validator"
    echo "==================================="
    echo
    
    local total_errors=0
    
    # Determine server type
    if [ -d "$REPO_DIR/edge" ]; then
        SERVER_TYPE="edge"
        print_status "Detected EDGE server"
    elif [ -d "$REPO_DIR/homelab" ]; then
        SERVER_TYPE="homelab"
        print_status "Detected HOMELAB server"
    else
        print_error "Cannot determine server type. Neither edge/ nor homelab/ directory found."
        exit 1
    fi
    
    # Run validations
    validate_docker
    total_errors=$((total_errors + $?))
    
    validate_common_config
    total_errors=$((total_errors + $?))
    
    validate_network
    total_errors=$((total_errors + $?))
    
    if [ "$SERVER_TYPE" = "edge" ]; then
        validate_edge_config
        total_errors=$((total_errors + $?))
    else
        validate_homelab_config
        total_errors=$((total_errors + $?))
    fi
    
    provide_recommendations
    
    echo
    echo "📊 Validation Summary"
    echo "===================="
    
    if [ $total_errors -eq 0 ]; then
        print_success "All validations passed! Your $SERVER_TYPE server is properly configured."
        echo
        echo "🎉 Your system is ready to use!"
    else
        print_error "Found $total_errors validation error(s). Please fix them before proceeding."
        echo
        echo "🔧 Common fixes:"
        echo "   - Run setup script: sudo ./setup-complete.sh"
        echo "   - Check logs: tail -f /var/log/git-sync.log"
        echo "   - Restart services: sudo systemctl restart git-sync.timer"
        exit 1
    fi
}

# Run main function
main "$@"
