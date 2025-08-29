#!/bin/bash
set -e

echo "🌐 Installing Edge Server..."

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Update system
echo "📦 Updating system packages..."
apt update && apt upgrade -y

# Install required packages
echo "🐳 Installing Docker and dependencies..."
apt install -y \
    docker.io \
    docker-compose-plugin \
    git \
    curl \
    htop \
    ufw

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add current user to docker group (if not root)
if [[ -n "$SUDO_USER" ]]; then
    usermod -aG docker "$SUDO_USER"
    echo "✅ Added $SUDO_USER to docker group"
fi

# Clone repository
echo "📥 Cloning home-lab repository..."
if [[ -d "/opt/home-lab" ]]; then
    echo "⚠️  Repository already exists, updating..."
    cd /opt/home-lab
    git pull origin main
else
    cd /opt
    # Replace with your actual repository URL
    git clone https://github.com/YOUR_USERNAME/home-lab.git
    cd home-lab
fi

# Make scripts executable
echo "🔧 Setting up scripts..."
chmod +x common/scripts/*.sh

# Modify docker-redeploy script for edge server
echo "⚙️  Configuring for edge