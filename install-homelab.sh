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

# Run validation checks
log_info "Running pre-installation validation..."
if ! bash common/scripts/validate-setup.sh; then
    error_exit "Pre-installation validation failed"
fi
    exit 1
}

# Cleanup function for interrupted installations
cleanup() {
    log_warning "Installation interrupted. Cleaning up..."
    # Stop any services that might have been started
    systemctl stop git-sync.timer 2>/dev/null || true
    systemctl stop docker-redeploy-homelab.timer 2>/dev/null || true
    exit 1
}

# Set trap for cleanup on script interruption
trap cleanup SIGINT SIGTERM

# Configuration variables
REPO_DIR="/opt/home-lab"
LOG_FILE="/var/log/homelab-install.log"

echo "🏠 Homelab Server Installation Script"
echo "===================================="

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

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check available disk space (minimum 10GB)
    available_space=$(df / | awk 'NR==2 {print $4}')
    required_space=10485760  # 10GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        error_exit "Insufficient disk space. Required: 10GB, Available: $((available_space/1024/1024))GB"
    fi
    
    # Check available RAM (minimum 2GB)
    available_ram=$(free -m | awk 'NR==2{print $7}')
    required_ram=2048
    
    if [[ $available_ram -lt $required_ram ]]; then
        log_warning "Low available RAM. Available: ${available_ram}MB, Recommended: 2GB+"
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error_exit "No internet connection available"
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
    
    # Validate repository structure
    required_dirs=("common/systemd" "common/scripts" "homelab" "edge")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            error_exit "Invalid repository structure: missing $dir directory"
        fi
    done
    
    log_success "Repository setup completed"
}

# Install systemd services with validation
install_systemd_services() {
    log_info "Installing systemd services..."
    
    cd /opt/home-lab
    
    # Make scripts executable
    chmod +x common/scripts/*.sh || error_exit "Failed to make scripts executable"
    
    # Validate systemd service files
    service_files=(
        "common/systemd/git-sync.service"
        "common/systemd/git-sync.timer"
        "common/systemd/docker-redeploy-homelab.service"
        "common/systemd/docker-redeploy-homelab.timer"
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
    if ! cp common/systemd/*.service /etc/systemd/system/; then
        error_exit "Failed to copy systemd service files"
    fi
    
    if ! cp common/systemd/*.timer /etc/systemd/system/; then
        error_exit "Failed to copy systemd timer files"
    fi
    
    # Reload systemd
    if ! systemctl daemon-reload; then
        error_exit "Failed to reload systemd"
    fi
    
    # Enable and start services
    services=("git-sync.timer" "docker-redeploy-homelab.timer")
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

# Configure firewall with security best practices
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
    
    # Allow Tailscale
    ufw allow in on tailscale0
    
    # Allow homelab services (only from Tailscale network)
    ufw allow from 100.64.0.0/10 to any port 8080 comment 'Website'
    ufw allow from 100.64.0.0/10 to any port 32400 comment 'Plex'
    
    # Enable firewall
    if ! ufw --force enable; then
        log_warning "Failed to enable firewall"
    else
        log_success "Firewall configured and enabled"
    fi
}

# Setup automatic security updates
setup_security_updates() {
    log_info "Configuring automatic security updates..."
    
    # Configure unattended-upgrades
    cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF

    # Enable automatic security updates
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    log_success "Automatic security updates configured"
}

# Function to get configuration from user
get_configuration() {
    log_info "Getting configuration details..."
    
    # Get repository URL
    REPO_URL=$(get_input "Enter your GitHub repository URL" "https://github.com/yourusername/home-lab.git" "")
    
    # Get timezone
    TIMEZONE=$(get_input "Enter your timezone" "$(timedatectl show --property=Timezone --value 2>/dev/null || echo 'America/New_York')" "")
    
    # Get Tailscale setup preference
    read -p "Do you want to install Tailscale? (Y/n): " install_tailscale
    if [[ ! "$install_tailscale" =~ ^[Nn]$ ]]; then
        INSTALL_TAILSCALE=true
        log_info "Tailscale will be installed"
    else
        INSTALL_TAILSCALE=false
        log_warning "Tailscale will not be installed. You'll need to configure it manually."
    fi
    
    # Confirm configuration
    echo
    log_info "Configuration Summary:"
    echo "  Repository URL: $REPO_URL"
    echo "  Timezone: $TIMEZONE"
    echo "  Install Tailscale: $INSTALL_TAILSCALE"
    echo
    
    read -p "Is this configuration correct? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Please run the script again with correct configuration."
        exit 1
    fi
}

# Function to install Tailscale
install_tailscale() {
    if [[ "$INSTALL_TAILSCALE" == "true" ]]; then
        log_info "Installing Tailscale..."
        
        # Install Tailscale
        if ! curl -fsSL https://tailscale.com/install.sh | sh; then
            error_exit "Failed to install Tailscale"
        fi
        
        # Start Tailscale
        if ! systemctl start tailscaled; then
            error_exit "Failed to start Tailscale daemon"
        fi
        
        if ! systemctl enable tailscaled; then
            error_exit "Failed to enable Tailscale daemon"
        fi
        
        log_success "Tailscale installed successfully"
        log_info "Please run 'tailscale up' to connect to your network"
        log_info "Your Tailscale IP will be needed for edge server configuration"
    fi
}

# Function to setup Docker network
setup_docker_network() {
    log_info "Setting up Docker network..."
    
    # Create homelab network if it doesn't exist
    if ! docker network ls | grep -q "homelab-net"; then
        if ! docker network create homelab-net; then
            error_exit "Failed to create homelab-net Docker network"
        fi
        log_success "Created homelab-net Docker network"
    else
        log_warning "homelab-net Docker network already exists"
    fi
}

# Function to deploy initial services
deploy_services() {
    log_info "Deploying initial services..."
    
    cd "$REPO_DIR/homelab"
    
    # Start Docker services
    if ! docker compose up -d; then
        error_exit "Failed to start Docker services"
    fi
    
    # Wait for services to be ready
    log_info "Waiting for services to be ready..."
    sleep 10
    
    # Verify services are running
    local container_count=$(docker ps --format '{{.Names}}' | grep -c "homelab-" || echo "0")
    if [[ $container_count -gt 0 ]]; then
        log_success "Found $container_count homelab containers running"
    else
        log_warning "No homelab containers are running"
    fi
    
    log_success "Initial services deployed successfully"
}

# Function to run final tests
run_tests() {
    log_info "Running final tests..."
    
    # Test Docker containers
    local container_count=$(docker ps --format '{{.Names}}' | grep -c "homelab-" || echo "0")
    if [[ $container_count -gt 0 ]]; then
        log_success "Found $container_count homelab containers running"
        echo "Running containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "homelab-" | sed 's/^/  /'
    else
        log_warning "No homelab containers are running"
    fi
    
    # Test systemd services
    services=("git-sync.timer" "docker-redeploy-homelab.timer")
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_success "$service is active"
        else
            log_warning "$service is not active"
        fi
    done
    
    # Test Docker network
    if docker network ls | grep -q "homelab-net"; then
        log_success "homelab-net Docker network exists"
    else
        log_warning "homelab-net Docker network not found"
    fi
}

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

# Main installation function
main() {
    echo "$(date): Starting homelab server installation..." >> "$LOG_FILE"
    
    # Run installation steps
    detect_os
    check_requirements
    backup_existing
    update_system
    install_docker
    get_configuration
    setup_repository
    install_systemd_services
    configure_firewall
    setup_security_updates
    install_tailscale
    setup_docker_network
    deploy_services
    run_tests
    
    echo "$(date): Homelab server installation completed successfully" >> "$LOG_FILE"
    
    # Show final status
    echo
    log_success "🎉 Homelab server installation completed successfully!"
    echo
    echo "📋 Services Status:"
    systemctl status git-sync.timer --no-pager -l
    systemctl status docker-redeploy-homelab.timer --no-pager -l
    echo
    echo "🐳 Docker Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo
    echo "🔍 Next Steps:"
    echo "  1. Configure your services in /opt/home-lab/homelab/docker-compose.yml"
    echo "  2. Push changes to your GitHub repository"
    echo "  3. Services will be automatically deployed"
    if [[ "$INSTALL_TAILSCALE" == "true" ]]; then
        echo "  4. Run 'tailscale up' to connect to your Tailscale network"
        echo "  5. Note your Tailscale IP for edge server configuration"
    fi
    echo
    echo "📚 Useful Commands:"
    echo "  - View logs: tail -f /var/log/git-sync.log"
    echo "  - Check services: docker ps"
    echo "  - Restart services: systemctl restart docker-redeploy-homelab.timer"
    echo "  - Check Tailscale: tailscale status"
    echo
}

# Run main function
main "$@"