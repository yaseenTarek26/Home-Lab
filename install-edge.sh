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
    # Stop any services that might have been started
    systemctl stop git-sync.timer 2>/dev/null || true
    systemctl stop docker-redeploy-edge.timer 2>/dev/null || true
    # Stop Docker containers
    cd /opt/home-lab/edge 2>/dev/null && docker compose down 2>/dev/null || true
    exit 1
}

# Set trap for cleanup on script interruption
trap cleanup SIGINT SIGTERM

echo "🌐 Installing Edge Server..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error_exit "This script must be run as root (use sudo)"
fi

# Detect OS and version
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        log_info "Detected OS: $OS $VER"
    else
        error_exit "Cannot detect operating system"
    fi
}

# Check system requirements for edge server
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check available disk space (minimum 5GB for edge server)
    available_space=$(df / | awk 'NR==2 {print $4}')
    required_space=5242880  # 5GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        error_exit "Insufficient disk space. Required: 5GB, Available: $((available_space/1024/1024))GB"
    fi
    
    # Check available RAM (minimum 1GB for edge server)
    available_ram=$(free -m | awk 'NR==2{print $7}')
    required_ram=1024
    
    if [[ $available_ram -lt $required_ram ]]; then
        log_warning "Low available RAM. Available: ${available_ram}MB, Recommended: 1GB+"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error_exit "No internet connection available"
    fi
    
    # Check if ports 80 and 443 are available
    if ss -tlnp | grep -q ":80 "; then
        error_exit "Port 80 is already in use. Edge server requires ports 80 and 443."
    fi
    
    if ss -tlnp | grep -q ":443 "; then
        error_exit "Port 443 is already in use. Edge server requires ports 80 and 443."
    fi
    
    log_success "System requirements check passed"
}

# Backup existing configuration
backup_existing() {
    if [[ -d "/opt/home-lab" ]]; then
        log_info "Backing up existing installation..."
        backup_dir="/opt/home-lab-backup-$(date +%Y%m%d-%H%M%S)"
        cp -r /opt/home-lab "$backup_dir" || error_exit "Failed to backup existing installation"
        log_success "Backup created at $backup_dir"
    fi
}

# Update system with retry logic
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

# Install Docker with proper error handling
install_docker() {
    log_info "Installing Docker and dependencies..."
    
    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        log_warning "Docker already installed, checking version..."
        docker_version=$(docker --version | cut -d' ' -f3 | cut -d',' -f1)
        log_info "Current Docker version: $docker_version"
    else
        # Install Docker using official script for better compatibility
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
        "certbot"
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

# Setup repository with validation
setup_repository() {
    log_info "Setting up home-lab repository..."
    
    # Prompt for repository URL if not set
    if [[ -z "$REPO_URL" ]]; then
        read -p "Enter your GitHub repository URL (https://github.com/username/home-lab.git): " REPO_URL
        if [[ -z "$REPO_URL" ]]; then
            error_exit "Repository URL is required"
        fi
    fi
    
    # Validate repository URL format
    if [[ ! "$REPO_URL" =~ ^https://github\.com/.+/.*\.git$ ]]; then
        error_exit "Invalid GitHub repository URL format"
    fi
    
    # Clone or update repository
    if [[ -d "/opt/home-lab" ]]; then
        log_info "Repository exists, updating..."
        cd /opt/home-lab
        
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
    
    # Validate repository structure for edge server
    required_files=("edge/docker-compose.yml" "edge/Caddyfile" "common/systemd" "common/scripts")
    for file in "${required_files[@]}"; do
        if [[ ! -e "$file" ]]; then
            error_exit "Invalid repository structure: missing $file"
        fi
    done
    
    log_success "Repository setup completed"
}

# Configure DuckDNS settings
configure_duckdns() {
    log_info "Configuring DuckDNS settings..."
    
    # Check if DuckDNS is already configured
    if grep -q "SUBDOMAINS=yourusername" /opt/home-lab/edge/docker-compose.yml; then
        log_warning "DuckDNS configuration needs to be updated!"
        log_info "Please update the following in edge/docker-compose.yml:"
        log_info "  - SUBDOMAINS=your-actual-subdomain"
        log_info "  - TOKEN=your-duckdns-token"
        log_info "  - TZ=your-timezone"
        
        read -p "Have you updated the DuckDNS configuration? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            error_exit "Please update DuckDNS configuration before continuing"
        fi
    fi
    
    # Validate Caddyfile configuration
    if grep -q "yourusername.duckdns.org" /opt/home-lab/edge/Caddyfile; then
        log_warning "Caddyfile needs to be updated!"
        log_info "Please update the domain in edge/Caddyfile to your actual DuckDNS domain"
        
        read -p "Have you updated the Caddyfile? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            error_exit "Please update Caddyfile before continuing"
        fi
    fi
    
    log_success "DuckDNS configuration validated"
}

# Install systemd services with validation
install_systemd_services() {
    log_info "Installing systemd services..."
    
    cd /opt/home-lab
    
    # Make scripts executable
    chmod +x common/scripts/*.sh || error_exit "Failed to make scripts executable"
    
    # Validate systemd service files for edge
    service_files=(
        "common/systemd/git-sync.service"
        "common/systemd/git-sync.timer"
        "common/systemd/docker-redeploy-edge.service"
        "common/systemd/docker-redeploy-edge.timer"
    )
    
    for file in "${service_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            error_exit "Missing systemd service file: $file"
        fi
        
        # Update paths in service files
        sed -i "s|/path/to/home-lab|/opt/home-lab|g" "$file"
        sed -i "s|your-user|$SUDO_USER|g" "$file"
    done
    
    # Copy service files
    if ! cp common/systemd/git-sync.service /etc/systemd/system/; then
        error_exit "Failed to copy git-sync service file"
    fi
    
    if ! cp common/systemd/git-sync.timer /etc/systemd/system/; then
        error_exit "Failed to copy git-sync timer file"
    fi
    
    if ! cp common/systemd/docker-redeploy-edge.service /etc/systemd/system/; then
        error_exit "Failed to copy edge redeploy service file"
    fi
    
    if ! cp common/systemd/docker-redeploy-edge.timer /etc/systemd/system/; then
        error_exit "Failed to copy edge redeploy timer file"
    fi
    
    # Reload systemd
    if ! systemctl daemon-reload; then
        error_exit "Failed to reload systemd"
    fi
    
    #