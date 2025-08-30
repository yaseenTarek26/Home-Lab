# 🏠 **Home Lab GitOps Setup - Complete Guide**

A fully automated, production-grade home lab with GitOps deployment, secure external access, and automatic HTTPS certificates.

## 📋 **Table of Contents**

- [🏗️ Architecture Overview](#️-architecture-overview)
- [✨ Features](#-features)
- [📂 Project Structure](#-project-structure)
- [🚀 Quick Start](#-quick-start)
- [📖 Detailed Installation](#-detailed-installation)
- [🔄 Workflow & Usage](#-workflow--usage)
- [🛠️ Management & Monitoring](#️-management--monitoring)
- [🚨 Troubleshooting](#-troubleshooting)
- [📚 Adding New Services](#-adding-new-services)
- [🔧 Advanced Configuration](#-advanced-configuration)

---

## 🏗️ **Architecture Overview**

```
Internet → DuckDNS → Oracle Cloud (Caddy) → Tailscale VPN → Home Lab Services
```

### **Components:**
- **Home Lab Server**: Runs your services (Plex, Nextcloud, etc.)
- **Edge Server** (Oracle Cloud): Reverse proxy with Caddy + DuckDNS
- **Tailscale**: Secure VPN tunnel between servers
- **GitHub**: GitOps repository for configuration
- **DuckDNS**: Free dynamic DNS service

### **Traffic Flow:**
1. User visits `yourusername.duckdns.org/plex`
2. DuckDNS resolves to Oracle Cloud IP
3. Caddy receives request and forwards via Tailscale
4. Home lab Plex service responds
5. Response flows back through secure tunnel

---

## ✨ **Features**

- ✅ **GitOps Deployment**: Push code → automatic deployment
- ✅ **Secure External Access**: Tailscale VPN + Caddy reverse proxy
- ✅ **Free Domain**: DuckDNS with automatic IP updates
- ✅ **Automatic HTTPS**: Let's Encrypt certificates via Caddy
- ✅ **Container Auto-Updates**: Watchtower keeps everything current
- ✅ **Path-Based Routing**: `domain.com/service` for each service
- ✅ **Self-Healing**: Automatic restarts and health checks
- ✅ **Scalable**: Add services by creating folders and pushing

---

## 📂 **Project Structure**

```
Home-Lab/
├── README.md                                   # This file
├── common/
│   ├── systemd/
│   │   ├── git-sync.service                    # Git sync automation
│   │   ├── git-sync.timer                      # Runs git sync every 2min
│   │   ├── docker-redeploy-edge.service        # Edge server deployment
│   │   ├── docker-redeploy-edge.timer          # Edge deployment timer
│   │   ├── docker-redeploy-homelab.service     # Homelab deployment
│   │   └── docker-redeploy-homelab.timer       # Homelab deployment timer
│   └── scripts/
│       └── git-sync.sh                         # Git pull script
│
├── homelab/
│   ├── website/
│   │   ├── docker-compose.yml                  # Nginx web server
│   │   └── index.html                          # Website content
│   └── plex/
│       └── docker-compose.yml                  # Plex media server
│
└── edge/
    ├── docker-compose.yml                      # Caddy + DuckDNS + Watchtower
    └── Caddyfile                               # Reverse proxy configuration
```

---

## 🚀 **Quick Start**

### **Prerequisites:**
- 2 servers (home lab + Oracle Cloud free tier)
- Docker & Docker Compose installed on both
- GitHub account
- Tailscale account (free)
- DuckDNS account (free)
- Sudo/root access on both servers
- At least 5GB free disk space
- Ports 80, 443, and 8080 available

### **Pre-Installation Checklist:**

1. **Clone this repository:**
```bash
git clone https://github.com/yourusername/home-lab.git
cd home-lab
```

2. **Set up environment variables:**
```bash
# Copy the example environment file
cp homelab/.env.example homelab/.env

# Edit the environment file with your settings
nano homelab/.env
```

Required environment variables:
- `DUCKDNS_TOKEN`: Your DuckDNS token
- `DUCKDNS_SUBDOMAIN`: Your DuckDNS subdomain
- `TAILSCALE_AUTH_KEY`: Your Tailscale auth key
```

2. **Setup Tailscale on both servers:**
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

3. **Configure DuckDNS:**
   - Sign up at [duckdns.org](https://duckdns.org)
   - Create subdomain: `yourusername.duckdns.org`
   - Get your token

4. **Update configuration files** (see detailed installation below)

5. **Deploy:**
```bash
# On home lab server
./scripts/install-homelab.sh

# On edge server  
./scripts/install-edge.sh
```

---

## 📖 **Detailed Installation**

### **Step 1: Initial Setup & Validation**

1. **Environment Configuration:**
   ```bash
   # Copy environment template
   cp homelab/.env.example homelab/.env
   
   # Edit with your settings
   nano homelab/.env
   ```

2. **Run System Validation:**
   ```bash
   # Check all prerequisites
   sudo bash common/scripts/validate-setup.sh
   ```
   This validates:
   - System permissions
   - Tailscale connectivity
   - Port availability (80, 443, 8080)
   - Volume directories and permissions
   - Environment configuration

### **Step 2: Server Preparation**

#### **Both Servers:**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install Git
sudo apt install git -y

# Reboot to apply Docker group changes
sudo reboot
```

#### **Setup Tailscale:**
```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to your Tailscale network
sudo tailscale up

# Get your Tailscale IP (save this for later)
tailscale ip -4
```

### **Step 2: DuckDNS Configuration**

1. **Sign up at [duckdns.org](https://duckdns.org)**
2. **Create a subdomain** (e.g., `myhomelabproject`)
3. **Point it to your Oracle Cloud server's public IP**
4. **Get your DuckDNS token** from the dashboard

### **Step 3: Repository Setup**

```bash
# Clone the repository
git clone https://github.com/yourusername/home-lab.git
cd home-lab

# Update configuration files with your details
```

### **Step 4: Configuration Files**

#### **Environment Variables (.env):**
```bash
# Required settings in homelab/.env:
DUCKDNS_TOKEN=your_token_here          # Your DuckDNS token
DUCKDNS_SUBDOMAIN=your_subdomain       # Your DuckDNS subdomain
TAILSCALE_AUTH_KEY=your_authkey       # Your Tailscale auth key
DOCKER_NETWORK_SUBNET=172.20.0.0/16   # Docker network subnet
```

#### **Service Health Checks:**
All services include health checks for reliability:
```yaml
# Example in docker-compose.yml:
services:
  website:
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
```

#### **Update edge/docker-compose.yml:**
```yaml
# Replace these values:
- SUBDOMAINS=myhomelabproject          # Your DuckDNS subdomain
- TOKEN=your-duckdns-token-here        # Your DuckDNS token
- TZ=America/New_York                  # Your timezone
```

#### **Update edge/Caddyfile:**
```caddyfile
# Replace these values:
myhomelabproject.duckdns.org {         # Your DuckDNS domain
    reverse_proxy 100.64.1.2:8080     # Your homelab Tailscale IP
    
    handle_path /plex* {
        reverse_proxy 100.64.1.2:32400 # Your homelab Tailscale IP
    }
}
```

#### **Update common/scripts/git-sync.sh:**
```bash
# Replace this path:
cd /home/yourusername/home-lab         # Your actual repository path
```

#### **Update systemd service files:**
Replace `/path/to/home-lab` with your actual path in:
- `common/systemd/git-sync.service`
- `common/systemd/docker-redeploy-homelab.service`
- `common/systemd/docker-redeploy-edge.service`

### **Step 5: Home Lab Server Installation**

```bash
# Navigate to repository
cd /home/yourusername/home-lab

# Install systemd services
sudo cp common/systemd/git-sync.service /etc/systemd/system/
sudo cp common/systemd/git-sync.timer /etc/systemd/system/
sudo cp common/systemd/docker-redeploy-homelab.service /etc/systemd/system/
sudo cp common/systemd/docker-redeploy-homelab.timer /etc/systemd/system/

# Make scripts executable
chmod +x common/scripts/git-sync.sh

# Create Docker network
docker network create homelab-net

# Enable and start systemd services
sudo systemctl daemon-reload
sudo systemctl enable git-sync.timer docker-redeploy-homelab.timer
sudo systemctl start git-sync.timer docker-redeploy-homelab.timer

# Deploy initial services
cd homelab/website && docker compose up -d
cd ../plex && docker compose up -d

# Verify services are running
docker ps
```

### **Step 6: System Health & Monitoring**

The system includes built-in health monitoring:
- Service health checks run every 30 seconds
- Failed health checks trigger automatic container restarts
- System status available at `http://localhost:8080`
- Logs available in `/var/log/`

To check system health:
```bash
# View service status
docker ps
# Check health status
docker inspect --format "{{.State.Health.Status}}" homelab-website
# View logs
tail -f /var/log/git-sync.log
```

### **Step 7: Edge Server Installation**

```bash
# Navigate to repository
cd /home/yourusername/home-lab

# Install systemd services
sudo cp common/systemd/git-sync.service /etc/systemd/system/
sudo cp common/systemd/git-sync.timer /etc/systemd/system/
sudo cp common/systemd/docker-redeploy-edge.service /etc/systemd/system/
sudo cp common/systemd/docker-redeploy-edge.timer /etc/systemd/system/

# Make scripts executable
chmod +x common/scripts/git-sync.sh

# Enable and start systemd services
sudo systemctl daemon-reload
sudo systemctl enable git-sync.timer docker-redeploy-edge.timer
sudo systemctl start git-sync.timer docker-redeploy-edge.timer

# Deploy edge services
cd edge && docker compose up -d

# Verify services are running
docker ps
```

### **Step 7: Verification**

1. **Check Tailscale connectivity:**
```bash
# From edge server, ping homelab
ping 100.64.1.2  # Replace with your homelab Tailscale IP
```

2. **Check DuckDNS resolution:**
```bash
nslookup myhomelabproject.duckdns.org
```

3. **Test web access:**
   - Visit `https://myhomelabproject.duckdns.org`
   - Visit `https://myhomelabproject.duckdns.org/plex`

---

## 🔄 **Workflow & Usage**

### **Daily Workflow:**

1. **Develop locally** in your repository
2. **Test changes** with `docker compose up -d`
3. **Commit and push** to GitHub
4. **Automatic deployment** happens within 2-3 minutes
5. **Access services** via your DuckDNS domain

### **Adding a New Service:**

1. **Create service directory:**
```bash
mkdir homelab/nextcloud
cd homelab/nextcloud
```

2. **Create docker-compose.yml:**
```yaml
version: "3.9"
services:
  nextcloud:
    image: nextcloud:latest
    container_name: homelab-nextcloud
    volumes:
      - .:/var/www/html
    ports:
      - "8081:80"
    restart: unless-stopped
    networks:
      - homelab-net
    labels:
      - "com.centurylinklabs.watchtower.enable=true"

networks:
  homelab-net:
    external: true
```

3. **Update Caddyfile:**
```caddyfile
# Add to edge/Caddyfile:
handle_path /nextcloud* {
    reverse_proxy homelab-tailscale-ip:8081
}
```

4. **Deploy:**
```bash
git add .
git commit -m "Add Nextcloud service"
git push origin main
```

5. **Access:** `https://yourdomain.duckdns.org/nextcloud`

### **GitOps Automation Flow:**

```
Push to GitHub → Git Sync (2min) → Service Deployment (3min) → Live Service
```

- **Git sync runs every 2 minutes**
- **Deployment runs every 3 minutes after sync**
- **Total time from push to live: ~5 minutes**

---

## 🛠️ **Management & Monitoring**

### **Check System Status:**

```bash
# Systemd services status
sudo systemctl status git-sync.timer
sudo systemctl status docker-redeploy-homelab.timer

# View logs
sudo journalctl -u git-sync.service -f
sudo journalctl -u docker-redeploy-homelab.service -f

# Docker containers status
docker ps
docker compose ps

# Container logs
docker compose logs -f
docker logs container-name -f
```

### **Manual Operations:**

```bash
# Force git sync
sudo systemctl start git-sync.service

# Force service redeploy
sudo systemctl start docker-redeploy-homelab.service

# Restart specific service
cd homelab/plex && docker compose restart

# Update specific service
cd homelab/plex && docker compose pull && docker compose up -d

# View container resource usage
docker stats
```

### **Backup Important Data:**

```bash
# Complete system reset
sudo systemctl stop git-sync.timer docker-redeploy-*.timer caddy-reload.timer
docker compose down
docker system prune -a --volumes
sudo ./setup-complete.sh
```

## 🎯 **Benefits**

✅ **Hybrid Routing**: Support both path and subdomain routing  
✅ **Modular Architecture**: Clean, maintainable codebase  
✅ **Service Discovery**: Automatic detection of all labeled services  
✅ **CasaOS Compatible**: No conflicts with existing setups  
✅ **Validation**: Comprehensive error checking and validation  
✅ **Future-Proof**: Easy to extend and modify  
✅ **Production-Ready**: Robust error handling and logging  

## 📝 **Example Services**

### **Website (Root Site)**
```yaml
website:
  image: nginx:alpine
  ports:
    - "8080:80"
  labels:
    caddy.expose: "true"
    caddy.root: "true"          # This service becomes the root site
    caddy.host_port: "8080"
```

### **Plex Media Server**
```yaml
plex:
  image: plexinc/pms-docker:latest
  ports:
    - "32400:32400"
  labels:
    caddy.expose: "true"
    caddy.path: "/plex"
    caddy.host_port: "32400"
```

### **Jellyfin Media Server**
```yaml
jellyfin:
  image: jellyfin/jellyfin:latest
  ports:
    - "8096:8096"
  labels:
    caddy.expose: "true"
    caddy.path: "/jellyfin"
    caddy.host_port: "8096"
```

### **Portainer (Docker Management)**
```yaml
portainer:
  image: portainer/portainer-ce:latest
  ports:
    - "9000:9000"
  labels:
    caddy.expose: "true"
    caddy.path: "/portainer"
    caddy.host_port: "9000"
```

## 🔒 **Security Considerations**

### **Docker Socket Exposure**
- Watchtower mounts `/var/run/docker.sock` (normal but high-risk)
- Consider using `docker-socket-proxy` for production

### **Firewall Configuration**
- Ensure homelab firewall allows Tailscale ingress on service ports
- Edge server needs ports 80/443 open

### **Secrets Management**
- Use `.env` files for sensitive configuration
- Never commit tokens or secrets to Git

## 🚀 **Advanced Features**

### **FQDN Support**
For real domains with wildcard DNS:
```yaml
labels:
  caddy.expose: "true"
  caddy.fqdn: "plex.example.com"
  caddy.host_port: "32400"
```

### **Multiple Root Services**
Last service with `caddy.root: "true"` wins:
```yaml
labels:
  caddy.expose: "true"
  caddy.root: "true"
  caddy.host_port: "8080"
```

### **Automatic Port Detection**
Label reporter can auto-detect ports if `caddy.host_port` is not specified.

---

**Happy self-hosting! 🚀**
