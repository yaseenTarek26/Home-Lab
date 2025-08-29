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
LOG_FILE="/var/log/home-lab-setup.log"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "$(date): [INFO] $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "$(date): [SUCCESS] $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date): [WARNING] $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date): [ERROR] $1" >> "$LOG_FILE"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to validate configuration
validate_config() {
    print_status "Validating configuration..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
    
    # Check if we're on a supported system
    if ! command_exists apt-get && ! command_exists yum && ! command_exists dnf; then
        print_error "Unsupported package manager. This script supports Ubuntu/Debian and CentOS/RHEL"
        exit 1
    fi
    
    # Check if Docker is installed
    if ! command_exists docker; then
        print_warning "Docker not found. Will install Docker..."
    fi
    
    # Check if Docker Compose is installed
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        print_warning "Docker Compose not found. Will install Docker Compose..."
    fi
    
    print_success "Configuration validation completed"
}

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."
    
    if command_exists apt-get; then
        # Ubuntu/Debian
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        
        # Add Docker's official GPG key
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        
        # Add Docker repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io
    elif command_exists yum || command_exists dnf; then
        # CentOS/RHEL
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io
    fi
    
    # Start and enable Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker installed successfully"
}

# Function to install Docker Compose
install_docker_compose() {
    print_status "Installing Docker Compose..."
    
    # Download Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    # Create symlink for docker compose (newer syntax)
    ln -sf /usr/local/bin/docker-compose /usr/local/bin/docker-compose-v1
    
    print_success "Docker Compose installed successfully"
}

# Function to setup repository
setup_repository() {
    print_status "Setting up repository..."
    
    # Create directory
    mkdir -p "$REPO_DIR"
    
    # Check if repository already exists
    if [ -d "$REPO_DIR/.git" ]; then
        print_warning "Repository already exists at $REPO_DIR"
        read -p "Do you want to pull latest changes? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd "$REPO_DIR"
            git pull origin main
        fi
    else
        print_status "Cloning repository..."
        # Note: User will need to manually clone or copy files
        print_warning "Please ensure your home-lab files are in $REPO_DIR"
        print_warning "You can either:"
        print_warning "1. Clone your repository: git clone <your-repo-url> $REPO_DIR"
        print_warning "2. Copy files manually to $REPO_DIR"
        read -p "Press Enter when files are ready..."
    fi
    
    # Make scripts executable
    find "$REPO_DIR" -name "*.sh" -exec chmod +x {} \;
    
    print_success "Repository setup completed"
}

# Function to setup systemd services
setup_systemd() {
    print_status "Setting up systemd services..."
    
    # Copy systemd files
    cp "$REPO_DIR/common/systemd/"*.service /etc/systemd/system/
    cp "$REPO_DIR/common/systemd/"*.timer /etc/systemd/system/
    
    # Reload systemd
    systemctl daemon-reload
    
    # Enable timers
    systemctl enable git-sync.timer
    systemctl enable docker-redeploy-homelab.timer
    systemctl enable docker-redeploy-edge.timer
    
    print_success "Systemd services setup completed"
}

# Function to setup Docker network
setup_docker_network() {
    print_status "Setting up Docker network..."
    
    # Create homelab network if it doesn't exist
    if ! docker network ls | grep -q "homelab-net"; then
        docker network create homelab-net
        print_success "Created homelab-net Docker network"
    else
        print_warning "homelab-net Docker network already exists"
    fi
}

# Function to setup logging
setup_logging() {
    print_status "Setting up logging..."
    
    # Create log directory
    mkdir -p /var/log
    
    # Create log files
    touch /var/log/git-sync.log
    touch /var/log/caddy-generator.log
    touch /var/log/home-lab-setup.log
    
    # Set permissions
    chmod 644 /var/log/git-sync.log
    chmod 644 /var/log/caddy-generator.log
    chmod 644 /var/log/home-lab-setup.log
    
    print_success "Logging setup completed"
}

# Function to validate edge configuration
validate_edge_config() {
    print_status "Validating edge configuration..."
    
    # Check if edge directory exists
    if [ ! -d "$REPO_DIR/edge" ]; then
        print_error "Edge directory not found at $REPO_DIR/edge"
        return 1
    fi
    
    # Check if generate-caddyfile.sh exists
    if [ ! -f "$REPO_DIR/edge/generate-caddyfile.sh" ]; then
        print_error "generate-caddyfile.sh not found"
        return 1
    fi
    
    # Check if docker-compose.yml exists
    if [ ! -f "$REPO_DIR/edge/docker-compose.yml" ]; then
        print_error "edge/docker-compose.yml not found"
        return 1
    fi
    
    print_success "Edge configuration validation completed"
}

# Function to validate homelab configuration
validate_homelab_config() {
    print_status "Validating homelab configuration..."
    
    # Check if homelab directory exists
    if [ ! -d "$REPO_DIR/homelab" ]; then
        print_error "Homelab directory not found at $REPO_DIR/homelab"
        return 1
    fi
    
    # Check if docker-compose.yml exists
    if [ ! -f "$REPO_DIR/homelab/docker-compose.yml" ]; then
        print_error "homelab/docker-compose.yml not found"
        return 1
    fi
    
    print_success "Homelab configuration validation completed"
}

# Function to start services
start_services() {
    print_status "Starting services..."
    
    # Start git sync timer
    systemctl start git-sync.timer
    
    # Start deployment timers
    systemctl start docker-redeploy-homelab.timer
    systemctl start docker-redeploy-edge.timer
    
    print_success "Services started successfully"
}

# Function to show status
show_status() {
    print_status "Checking system status..."
    
    echo
    echo "=== Systemd Services Status ==="
    systemctl status git-sync.timer --no-pager -l
    systemctl status docker-redeploy-homelab.timer --no-pager -l
    systemctl status docker-redeploy-edge.timer --no-pager -l
    
    echo
    echo "=== Docker Status ==="
    docker ps
    
    echo
    echo "=== Network Status ==="
    docker network ls | grep homelab
    
    echo
    echo "=== Log Files ==="
    echo "Git sync logs: tail -f /var/log/git-sync.log"
    echo "Caddy generator logs: tail -f /var/log/caddy-generator.log"
    echo "Setup logs: tail -f /var/log/home-lab-setup.log"
}

# Main function
main() {
    echo "🏠 Home Lab Complete Setup Script"
    echo "================================="
    echo
    
    # Initialize log file
    touch "$LOG_FILE"
    echo "$(date): Starting home lab setup..." >> "$LOG_FILE"
    
    # Get server type
    echo "What type of server is this?"
    echo "1) Homelab server (runs your services)"
    echo "2) Edge server (Oracle Cloud, reverse proxy)"
    read -p "Enter choice (1 or 2): " server_type
    
    case $server_type in
        1)
            SERVER_TYPE="homelab"
            print_status "Setting up HOMELAB server"
            ;;
        2)
            SERVER_TYPE="edge"
            print_status "Setting up EDGE server"
            ;;
        *)
            print_error "Invalid choice. Exiting."
            exit 1
            ;;
    esac
    
    # Run setup steps
    validate_config
    install_docker
    install_docker_compose
    setup_repository
    setup_systemd
    setup_docker_network
    setup_logging
    
    # Server-specific validation
    if [ "$SERVER_TYPE" = "edge" ]; then
        validate_edge_config
    else
        validate_homelab_config
    fi
    
    start_services
    
    print_success "Setup completed successfully!"
    echo
    echo "🎉 Your $SERVER_TYPE server is now configured!"
    echo
    echo "📋 Next steps:"
    echo "1. Update configuration files with your specific values"
    echo "2. Test the system with: ./test-labels.sh (edge) or docker ps (homelab)"
    echo "3. Check logs: tail -f /var/log/git-sync.log"
    echo
    echo "🔧 Configuration files to update:"
    if [ "$SERVER_TYPE" = "edge" ]; then
        echo "   - $REPO_DIR/edge/generate-caddyfile.sh (domain and homelab IP)"
        echo "   - $REPO_DIR/edge/docker-compose.yml (DuckDNS token)"
    else
        echo "   - $REPO_DIR/homelab/docker-compose.yml (add your services)"
    fi
    
    show_status
}

# Run main function
main "$@"
