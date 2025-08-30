#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# Error handling
error_exit() {
    log_error "$1"
    log_error "Installation failed. Check the logs above for details."
    exit 1
}

# Cleanup function for interrupted installations
cleanup() {
    log_warning "Installation interrupted. Cleaning up..."
    systemctl stop git-sync.timer 2>/dev/null || true
    systemctl stop caddy-reload.timer 2>/dev/null || true
    exit 1
}

# Set trap for cleanup on script interruption
trap cleanup SIGINT SIGTERM

echo "🌐 Edge Server Installation Script"
echo "=================================="

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root (use sudo)"
fi

# Configuration variables
REPO_DIR="/opt/home-lab"
LOG_FILE="/var/log/edge-install.log"

# Function to get user input with validation
get_input() {
    local prompt="$1"
    local default="$2"
    local validation="$3"
    local input
    
    while true; do
        if [[ -n "$default" ]]; then
            read -p "$prompt [$default]: " input
            input="${input:-$default}"
        else
            read -p "$prompt: " input
        fi
        
        if [[ -n "$input" ]]; then
            if [[ -n "$validation" ]]; then
                if eval "$validation"; then
                    echo "$input"
                    return 0
                else
                    log_warning "Invalid input. Please try again."
                fi
            else
                echo "$input"
                return 0
            fi
        else
            log_warning "Input cannot be empty. Please try again."
        fi
    done
}

# Function to detect public IP
detect_public_ip() {
    log_info "Detecting public IP address..."
    
    # Try multiple methods to get public IP
    local public_ip=""
    
    # Method 1: curl ifconfig.me
    if command -v curl &> /dev/null; then
        public_ip=$(curl -s --max-time 10 ifconfig.me 2>/dev/null || echo "")
    fi
    
    # Method 2: curl ipinfo.io
    if [[ -z "$public_ip" ]] && command -v curl &> /dev/null; then
        public_ip=$(curl -s --max-time 10 ipinfo.io/ip 2>/dev/null || echo "")
    fi
    
    # Method 3: wget ifconfig.me
    if [[ -z "$public_ip" ]] && command -v wget &> /dev/null; then
        public_ip=$(wget -qO- --timeout=10 ifconfig.me 2>/dev/null || echo "")
    fi
    
    if [[ -n "$public_ip" ]]; then
        log_success "Detected public IP: $public_ip"
        echo "$public_ip"
    else
        log_warning "Could not automatically detect public IP"
        echo ""
    fi
}

# Function to validate domain format
validate_domain() {
    local domain="$1"
    if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to validate IP address
validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a octets <<< "$ip"
        for octet in "${octets[@]}"; do
            if [[ $octet -lt 0 || $octet -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check available disk space (minimum 5GB for edge server)
    available_space=$(df / | awk 'NR==2 {print $4}')
    required_space=5242880  # 5GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        error_exit "Insufficient disk space. Required: 5GB, Available: $((available_space/1024/1024))GB"
    fi
    
    # Check available RAM (minimum 1GB)
    available_ram=$(free -m | awk 'NR==2{print $7}')
    required_ram=1024
    
    if [[ $available_ram -lt $required_ram ]]; then
        log_warning "Low available RAM. Available: ${available_ram}MB, Recommended: 1GB+"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error_exit "No internet connection available"
    fi
    
    log_success "System requirements check passed"
}

# Function to update system
update_system() {
    log_info "Updating system packages..."
    
    # Update package lists with retry
    for i in {1..3}; do
        if apt update; then
            break
        else
            log_warning "Package update attempt $i failed, retrying..."
            sleep 5
        fi
        
        if [[ $i -eq 3 ]]; then
            error_exit "Failed to update package lists after 3 attempts"
        fi
    done
    
    # Upgrade packages
    if ! apt upgrade -y; then
        error_exit "Failed to upgrade system packages"
    fi
    
    log_success "System packages updated"
}

# Function to install Docker
install_docker() {
    log_info "Installing Docker and dependencies..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        log_warning "Docker already installed, checking version..."
        docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        log_info "Current Docker version: $docker_version"
    else
        # Install Docker using official script
        if ! curl -fsSL https://get.docker.com -o get-docker.sh; then
            error_exit "Failed to download Docker installation script"
        fi
        
        if ! sh get-docker.sh; then
            error_exit "Docker installation failed"
        fi
        
        rm get-docker.sh
        log_success "Docker installed successfully"
    fi
    
    # Install additional packages
    packages=(
        "docker-compose-plugin"
        "git"
        "curl"
        "htop"
        "ufw"
        "fail2ban"
        "unattended-upgrades"
        "jq"
    )
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing $package..."
            if ! apt install -y "$package"; then
                log_warning "Failed to install $package, continuing..."
            fi
        else
            log_info "$package already installed"
        fi
    done

# Start and enable Docker
    if ! systemctl start docker; then
        error_exit "Failed to start Docker service"
    fi
    
    if ! systemctl enable docker; then
        error_exit "Failed to enable Docker service"
    fi
    
    # Add user to docker group
if [[ -n "$SUDO_USER" ]]; then
        usermod -aG docker "$SUDO_USER" || log_warning "Failed to add user to docker group"
        log_success "Added $SUDO_USER to docker group"
    fi
    
    # Test Docker installation
    if ! docker run --rm hello-world &> /dev/null; then
        error_exit "Docker installation test failed"
    fi
    
    log_success "Docker installation completed and tested"
}

# Function to install yq
install_yq() {
    log_info "Installing yq..."
    
    # Check if yq is already installed
    if command -v yq &> /dev/null; then
        log_warning "yq already installed, checking version..."
        yq_version=$(yq --version | cut -d' ' -f3)
        log_info "Current yq version: $yq_version"
    else
        # Install yq
        if ! curl -fsSL https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -o /usr/local/bin/yq; then
            error_exit "Failed to download yq"
        fi
        
        if ! chmod +x /usr/local/bin/yq; then
            error_exit "Failed to make yq executable"
        fi
        
        log_success "yq installed successfully"
    fi
}

# Function to get configuration from user
get_configuration() {
    log_info "Getting configuration details..."
    
    # Get repository URL
    REPO_URL=$(get_input "Enter your GitHub repository URL" "https://github.com/yourusername/home-lab.git" "")
    
    # Get DuckDNS domain
    DUCKDNS_DOMAIN=$(get_input "Enter your DuckDNS domain (e.g., myhomelab.duckdns.org)" "" "validate_domain \"\$input\"")
    
    # Get DuckDNS token
    DUCKDNS_TOKEN=$(get_input "Enter your DuckDNS token" "" "")
    
    # Get homelab Tailscale IP
    HOMELAB_IP=$(get_input "Enter your homelab server Tailscale IP (e.g., 100.64.1.2)" "" "validate_ip \"\$input\"")
    
    # Get timezone
    TIMEZONE=$(get_input "Enter your timezone" "$(timedatectl show --property=Timezone --value 2>/dev/null || echo 'America/New_York')" "")
    
    # Confirm configuration
    echo
    log_info "Configuration Summary:"
    echo "  Repository URL: $REPO_URL"
    echo "  DuckDNS Domain: $DUCKDNS_DOMAIN"
    echo "  DuckDNS Token: ${DUCKDNS_TOKEN:0:8}..."
    echo "  Homelab IP: $HOMELAB_IP"
    echo "  Timezone: $TIMEZONE"
    echo
    
    read -p "Is this configuration correct? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Please run the script again with correct configuration."
        exit 1
    fi
}

# Function to setup repository
setup_repository() {
    log_info "Setting up home-lab repository..."
    
    # Clone or update repository
    if [[ -d "$REPO_DIR" ]]; then
        log_info "Repository exists, updating..."
        cd "$REPO_DIR"
        
        # Stash any local changes
        git stash push -m "Auto-stash before update $(date)" || true
        
        if ! git pull origin main; then
            error_exit "Failed to update repository"
        fi
else
    cd /opt
        if ! git clone "$REPO_URL" home-lab; then
            error_exit "Failed to clone repository"
        fi
    cd home-lab
fi
    
    # Validate repository structure
    required_dirs=("common/systemd" "common/scripts" "edge")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            error_exit "Invalid repository structure: missing $dir directory"
        fi
    done
    
    log_success "Repository setup completed"
}

# Function to configure edge server
configure_edge() {
    log_info "Configuring edge server..."
    
    cd "$REPO_DIR/edge"
    
    # Update generate-caddyfile.sh with user configuration
    sed -i "s/yourname.duckdns.org/$DUCKDNS_DOMAIN/g" generate-caddyfile.sh
    sed -i "s/100.x.x.x/$HOMELAB_IP/g" generate-caddyfile.sh
    
    # Update docker-compose.yml with DuckDNS configuration
    sed -i "s/yourusername/$DUCKDNS_DOMAIN/g" docker-compose.yml
    sed -i "s/your-duckdns-token/$DUCKDNS_TOKEN/g" docker-compose.yml
    sed -i "s/America\/New_York/$TIMEZONE/g" docker-compose.yml
    
    # Make scripts executable
    chmod +x generate-caddyfile.sh
    chmod +x git-sync-trigger.sh
    chmod +x test-labels.sh
    
    log_success "Edge server configured"
}

# Function to install systemd services
install_systemd_services() {
    log_info "Installing systemd services..."
    
    cd "$REPO_DIR"

# Make scripts executable
    chmod +x common/scripts/*.sh || error_exit "Failed to make scripts executable"
    
    # Copy service files
    if ! cp common/systemd/*.service /etc/systemd/system/; then
        error_exit "Failed to copy systemd service files"
    fi
    
    if ! cp common/systemd/*.timer /etc/systemd/system/; then
        error_exit "Failed to copy systemd timer files"
    fi
    
    # Copy edge-specific services
    if ! cp edge/systemd/*.service /etc/systemd/system/; then
        error_exit "Failed to copy edge systemd service files"
    fi
    
    if ! cp edge/systemd/*.timer /etc/systemd/system/; then
        error_exit "Failed to copy edge systemd timer files"
    fi
    
    # Reload systemd
    if ! systemctl daemon-reload; then
        error_exit "Failed to reload systemd"
    fi
    
    # Enable and start services
    services=("git-sync.timer" "caddy-reload.timer")
    for service in "${services[@]}"; do
        if ! systemctl enable "$service"; then
            error_exit "Failed to enable $service"
        fi
        
        if ! systemctl start "$service"; then
            error_exit "Failed to start $service"
        fi
        
        # Verify service is running
        if ! systemctl is-active --quiet "$service"; then
            error_exit "$service is not running"
        fi
    done
    
    log_success "Systemd services installed and started"
}

# Function to setup logging
setup_logging() {
    log_info "Setting up logging..."
    
    # Create log directory
    mkdir -p /var/log
    
    # Create log files
    touch /var/log/git-sync.log
    touch /var/log/caddy-generator.log
    touch /var/log/edge-install.log
    
    # Set permissions
    chmod 644 /var/log/git-sync.log
    chmod 644 /var/log/caddy-generator.log
    chmod 644 /var/log/edge-install.log
    
    log_success "Logging setup completed"
}

# Function to configure firewall
configure_firewall() {
    log_info "Configuring firewall..."
    
    # Reset UFW to defaults
    ufw --force reset
    
    # Set default policies
    ufw default deny incoming
    ufw default allow outgoing
    
    # Allow SSH (detect current SSH port)
    ssh_port=$(ss -tlnp | grep sshd | awk '{print $4}' | cut -d':' -f2 | head -1)
    if [[ -n "$ssh_port" ]]; then
        ufw allow "$ssh_port"/tcp comment 'SSH'
    else
        ufw allow 22/tcp comment 'SSH'
    fi
    
    # Allow HTTP and HTTPS (for Caddy)
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    
    # Allow Tailscale
    ufw allow in on tailscale0
    
    # Enable firewall
    if ! ufw --force enable; then
        log_warning "Failed to enable firewall"
    else
        log_success "Firewall configured and enabled"
    fi
}

# Function to deploy edge services
deploy_services() {
    log_info "Deploying edge services..."
    
    cd "$REPO_DIR/edge"
    
    # Generate initial Caddyfile
    if ! ./generate-caddyfile.sh; then
        error_exit "Failed to generate initial Caddyfile"
    fi
    
    # Start Docker services
    if ! docker compose up -d; then
        error_exit "Failed to start Docker services"
    fi
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10
    
    # Verify services are running
    if ! docker ps --format '{{.Names}}' | grep -q "edge-caddy"; then
        error_exit "Caddy container is not running"
    fi
    
    if ! docker ps --format '{{.Names}}' | grep -q "edge-duckdns"; then
        error_exit "DuckDNS container is not running"
    fi
    
    log_success "Edge services deployed successfully"
}

# Function to run final tests
run_tests() {
    log_info "Running final tests..."
    
    # Test Docker containers
    if ! docker ps | grep -q "edge-caddy"; then
        log_warning "Caddy container test failed"
    else
        log_success "Caddy container is running"
    fi
    
    # Test systemd services
    services=("git-sync.timer" "caddy-reload.timer")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is active"
        else
            log_warning "$service is not active"
        fi
    done
    
    # Test Caddyfile generation
    if [[ -f "$REPO_DIR/edge/Caddyfile" ]]; then
        log_success "Caddyfile generated successfully"
        echo "Generated Caddyfile content:"
        cat "$REPO_DIR/edge/Caddyfile" | sed 's/^/  /'
    else
        log_warning "Caddyfile not found"
    fi
}

# Main installation function
main() {
    echo "$(date): Starting edge server installation..." >> "$LOG_FILE"
    
    # Run installation steps
    check_requirements
    update_system
    install_docker
    install_yq
    get_configuration
    setup_repository
    configure_edge
    install_systemd_services
    setup_logging
    configure_firewall
    deploy_services
    run_tests
    
    echo "$(date): Edge server installation completed successfully" >> "$LOG_FILE"
    
    # Show final status
    echo
    log_success "🎉 Edge server installation completed successfully!"
    echo
    echo "📋 Services Status:"
    systemctl status git-sync.timer --no-pager -l
    systemctl status caddy-reload.timer --no-pager -l
    echo
    echo "🐳 Docker Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    echo "📄 Generated Caddyfile:"
    cat "$REPO_DIR/edge/Caddyfile" | sed 's/^/  /'
    echo
    echo "🔍 Next Steps:"
    echo "  1. Test your domain: https://$DUCKDNS_DOMAIN"
    echo "  2. Check logs: tail -f /var/log/caddy-generator.log"
    echo "  3. Run validation: $REPO_DIR/edge/test-labels.sh"
    echo
    echo "📚 Useful Commands:"
    echo "  - View logs: tail -f /var/log/git-sync.log"
    echo "  - Restart services: systemctl restart caddy-reload.timer"
    echo "  - Manual Caddyfile generation: cd $REPO_DIR/edge && ./generate-caddyfile.sh"
    echo
}

# Run main function
main "$@"