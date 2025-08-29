#!/bin/bash
set -e

echo "🚀 Setting up Edge Server with Labels-Based Automation"

# Configuration
REPO_DIR="/opt/home-lab"
EDGE_DIR="$REPO_DIR/edge"
DOMAIN="yourname.duckdns.org"
HOMELAB_IP="100.x.x.x"  # Replace with your homelab Tailscale IP

echo "📝 Please update the following in the script:"
echo "   - DOMAIN: $DOMAIN"
echo "   - HOMELAB_IP: $HOMELAB_IP"
echo "   - DuckDNS token in edge/docker-compose.yml"
read -p "Press Enter to continue after updating..."

# Create directories
sudo mkdir -p "$REPO_DIR"
sudo mkdir -p "$EDGE_DIR/systemd"
sudo mkdir -p /var/log

# Clone repository (if not already present)
if [ ! -d "$REPO_DIR/.git" ]; then
    echo "📥 Cloning repository..."
    sudo git clone https://github.com/yourusername/home-lab.git "$REPO_DIR"
fi

# Update configuration files
echo "⚙️  Updating configuration..."

# Update domain and IP in generate-caddyfile.sh
sudo sed -i "s/yourname.duckdns.org/$DOMAIN/g" "$EDGE_DIR/generate-caddyfile.sh"
sudo sed -i "s/100.x.x.x/$HOMELAB_IP/g" "$EDGE_DIR/generate-caddyfile.sh"

# Make scripts executable
sudo chmod +x "$EDGE_DIR/generate-caddyfile.sh"
sudo chmod +x "$EDGE_DIR/git-sync-trigger.sh"

# Create initial Caddyfile
echo "📄 Generating initial Caddyfile..."
cd "$EDGE_DIR"
sudo ./generate-caddyfile.sh

# Install systemd services
echo "🔧 Installing systemd services..."

# Copy systemd files
sudo cp "$EDGE_DIR/systemd/caddy-reload.service" /etc/systemd/system/
sudo cp "$EDGE_DIR/systemd/caddy-reload.timer" /etc/systemd/system/

# Update paths in systemd files
sudo sed -i "s|/opt/home-lab|$REPO_DIR|g" /etc/systemd/system/caddy-reload.service

# Reload systemd
sudo systemctl daemon-reload

# Enable and start services
echo "🚀 Starting services..."

# Start Docker Compose
cd "$EDGE_DIR"
sudo docker-compose up -d

# Enable and start timers
sudo systemctl enable caddy-reload.timer
sudo systemctl start caddy-reload.timer

# Create git-sync service (if not exists)
if [ ! -f /etc/systemd/system/git-sync.service ]; then
    sudo tee /etc/systemd/system/git-sync.service > /dev/null <<EOF
[Unit]
Description=Git sync service
After=network.target

[Service]
Type=oneshot
WorkingDirectory=$REPO_DIR
ExecStart=$EDGE_DIR/git-sync-trigger.sh
User=root

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/git-sync.timer > /dev/null <<EOF
[Unit]
Description=Git sync timer
Requires=git-sync.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=git-sync.service

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable git-sync.timer
    sudo systemctl start git-sync.timer
fi

echo "✅ Edge server setup complete!"
echo ""
echo "📋 Services will be available at:"
echo "   - Main site: https://$DOMAIN"
echo "   - Plex: https://plex.$DOMAIN"
echo "   - Jellyfin: https://jellyfin.$DOMAIN"
echo "   - Portainer: https://portainer.$DOMAIN"
echo ""
echo "🔍 Check logs:"
echo "   - Caddy generator: tail -f /var/log/caddy-generator.log"
echo "   - Git sync: tail -f /var/log/git-sync.log"
echo "   - Systemd: journalctl -u caddy-reload.service -f"
echo ""
echo "🔄 To add a new service:"
echo "   1. Add service to homelab/docker-compose.yml with labels"
echo "   2. Push to GitHub"
echo "   3. Route will be automatically created!"
