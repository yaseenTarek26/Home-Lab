<<<<<<< HEAD
# 🏠 Home Lab - Labels-Based Automation

A self-hosted home lab setup with **automatic route generation** using Docker labels. Add a service → push to GitHub → route appears automatically!

## 🎯 How It Works

### Labels-Based Routing
Instead of manually editing configuration files, each service declares its own routing information using Docker labels:

```yaml
services:
  plex:
    image: plexinc/pms-docker:latest
    ports:
      - "32400:32400"
    labels:
      - "caddy.subdomain=plex"    # Creates plex.yourdomain.com
      - "caddy.port=32400"        # Routes to port 32400
```

### Automatic Workflow
1. **Add service** to `homelab/docker-compose.yml` with labels
2. **Push to GitHub** 
3. **Edge server syncs** and regenerates Caddyfile
4. **Route is live** automatically!

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub Repo   │    │   Edge Server   │    │   Homelab       │
│                 │    │   (Oracle)      │    │   (Local)       │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ docker-     │ │    │ │ Caddy       │ │    │ │ Plex        │ │
│ │ compose.yml │ │───▶│ │ (Reverse    │ │───▶│ │ Jellyfin    │ │
│ │ with labels │ │    │ │  Proxy)     │ │    │ │ Website     │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 📁 File Structure

```
home-lab/
├── edge/                          # Edge server (Oracle Cloud)
│   ├── docker-compose.yml         # Caddy + Watchtower
│   ├── generate-caddyfile.sh      # Auto-generates routes from labels
│   ├── git-sync-trigger.sh        # Git sync + Caddy reload
│   ├── Caddyfile                  # Auto-generated (do not edit)
│   └── systemd/
│       ├── caddy-reload.service   # Regenerates Caddyfile
│       └── caddy-reload.timer     # Runs every minute
├── homelab/                       # Homelab server (Local)
│   ├── docker-compose.yml         # Your services with labels
│   └── website/                   # Static website files
├── common/                        # Shared scripts and configs
├── install-edge-labels.sh         # Edge server setup script
└── install-homelab.sh            # Homelab server setup script
```

## 🚀 Quick Start

### **Option 1: Automated Setup (Recommended)**

```bash
# Clone repository
git clone https://github.com/yourusername/home-lab.git
cd home-lab

# Run comprehensive setup script
chmod +x setup-complete.sh
sudo ./setup-complete.sh
```

The script will:
- Detect server type (homelab/edge)
- Install Docker & Docker Compose
- Setup all systemd services
- Configure logging
- Validate configuration

### **Option 2: Manual Setup**

#### 1. Edge Server Setup (Oracle Cloud)

```bash
# Clone and run setup
git clone https://github.com/yourusername/home-lab.git
cd home-lab
chmod +x install-edge-labels.sh

# Edit the script to set your domain and homelab IP
nano install-edge-labels.sh

# Run setup
./install-edge-labels.sh
```

#### 2. Homelab Server Setup (Local)

```bash
# Clone and run setup
git clone https://github.com/yourusername/home-lab.git
cd home-lab
chmod +x install-homelab.sh
./install-homelab.sh
```

### **3. Validate Installation**

```bash
# Run validation script
chmod +x validate-config.sh
./validate-config.sh
```

### 3. Add Your First Service

Edit `homelab/docker-compose.yml`:

```yaml
services:
  my-app:
    image: nginx:alpine
    ports:
      - "8080:80"
    labels:
      - "caddy.subdomain=myapp"
      - "caddy.port=80"
```

Push to GitHub:
```bash
git add .
git commit -m "Add my-app service"
git push origin main
```

**Result**: `https://myapp.yourdomain.com` is automatically live! 🎉

## 📋 Available Labels

| Label | Description | Example |
|-------|-------------|---------|
| `caddy.subdomain` | Subdomain for the service | `plex`, `jellyfin`, `portainer` |
| `caddy.port` | Internal container port | `32400`, `8096`, `9000` |

## 🔧 Configuration

### Edge Server Settings

Edit `edge/generate-caddyfile.sh`:
```bash
DOMAIN="yourname.duckdns.org"
HOMELAB_IP="100.x.x.x"  # Your homelab Tailscale IP
```

### DuckDNS Setup

Edit `edge/docker-compose.yml`:
```yaml
duckdns:
  environment:
    - SUBDOMAINS=yourusername
    - TOKEN=your-duckdns-token
```

## 📊 Monitoring & Logs

### Check Service Status
```bash
# Edge server
sudo systemctl status caddy-reload.timer
sudo systemctl status git-sync.timer

# View logs
tail -f /var/log/caddy-generator.log
tail -f /var/log/git-sync.log
```

### Manual Caddyfile Regeneration
```bash
cd /opt/home-lab/edge
./generate-caddyfile.sh
```

## 🔄 Adding New Services

### Step 1: Add Service to Homelab
Edit `homelab/docker-compose.yml`:

```yaml
services:
  new-service:
    image: your-image:latest
    ports:
      - "8080:80"
    labels:
      - "caddy.subdomain=newservice"
      - "caddy.port=80"
```

### Step 2: Deploy
```bash
# On homelab server
docker-compose up -d new-service

# Push to GitHub
git add .
git commit -m "Add new-service"
git push origin main
```

### Step 3: Done!
The route `https://newservice.yourdomain.com` is automatically created! 🎉

## 🛠️ Troubleshooting

### **Quick Diagnostics**

```bash
# Run comprehensive validation
./validate-config.sh

# Check system status
sudo systemctl status git-sync.timer docker-redeploy-homelab.timer docker-redeploy-edge.timer

# View recent logs
tail -f /var/log/git-sync.log
tail -f /var/log/caddy-generator.log
```

### **Common Issues & Solutions**

#### Route Not Working?
1. **Check service status**: `docker ps`
2. **Verify labels**: `docker inspect container-name`
3. **Check Caddyfile**: `cat /opt/home-lab/edge/Caddyfile`
4. **View logs**: `tail -f /var/log/caddy-generator.log`
5. **Test connectivity**: `ping homelab-tailscale-ip`

#### Git Sync Issues?
1. **Check timer status**: `sudo systemctl status git-sync.timer`
2. **View sync logs**: `tail -f /var/log/git-sync.log`
3. **Manual sync**: `sudo systemctl start git-sync.service`
4. **Check permissions**: `ls -la /opt/home-lab/common/scripts/git-sync.sh`

#### Caddy Not Reloading?
1. **Check container**: `docker ps | grep caddy`
2. **Manual reload**: `docker exec edge-caddy caddy reload`
3. **Restart Caddy**: `docker-compose restart caddy`
4. **Check timer**: `sudo systemctl status caddy-reload.timer`

#### Docker Issues?
1. **Check Docker daemon**: `sudo systemctl status docker`
2. **Check disk space**: `df -h`
3. **Clean up Docker**: `docker system prune -a`
4. **Restart Docker**: `sudo systemctl restart docker`

### **Emergency Recovery**

```bash
# Complete system reset
sudo systemctl stop git-sync.timer docker-redeploy-*.timer
docker compose down
docker system prune -a --volumes
sudo ./setup-complete.sh
```

## 🎯 Benefits

✅ **Zero Configuration**: Add labels → route appears  
✅ **GitOps Workflow**: Push to GitHub → automatic deployment  
✅ **Self-Healing**: Systemd timers ensure everything stays running  
✅ **Declarative**: Routes live with service definitions  
✅ **Scalable**: Easy to add new services  

## 📝 Example Services

### Plex Media Server
```yaml
plex:
  image: plexinc/pms-docker:latest
  ports:
    - "32400:32400"
  labels:
    - "caddy.subdomain=plex"
    - "caddy.port=32400"
```

### Jellyfin Media Server
```yaml
jellyfin:
  image: jellyfin/jellyfin:latest
  ports:
    - "8096:8096"
  labels:
    - "caddy.subdomain=jellyfin"
    - "caddy.port=8096"
```

### Portainer (Docker Management)
```yaml
portainer:
  image: portainer/portainer-ce:latest
  ports:
    - "9000:9000"
  labels:
    - "caddy.subdomain=portainer"
    - "caddy.port=9000"
```

---

**Happy self-hosting! 🚀**
=======
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

### **5-Minute Setup:**

1. **Clone this repository:**
```bash
git clone https://github.com/yourusername/home-lab.git
cd home-lab
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

### **Step 1: Server Preparation**

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

### **Step 6: Edge Server Installation**

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
# Backup service configurations
tar -czf homelab-backup-$(date +%Y%m%d).tar.gz homelab/

# Backup Docker volumes
docker run --rm -v homelab_plex_config:/data -v $(pwd):/backup alpine tar czf /backup/plex-config-backup.tar.gz /data
```

---

## 🚨 **Troubleshooting**

### **Common Issues:**

#### **1. Services not accessible externally**

**Symptoms:** Can access locally but not via DuckDNS domain

**Solutions:**
```bash
# Check Tailscale connectivity
tailscale status
ping homelab-tailscale-ip

# Check Caddy logs
docker logs edge-caddy

# Verify Caddyfile syntax
docker exec edge-caddy caddy validate --config /etc/caddy/Caddyfile

# Check DuckDNS IP
nslookup yourdomain.duckdns.org
```

#### **2. Git sync not working**

**Symptoms:** Changes pushed but not deployed

**Solutions:**
```bash
# Check git sync status
sudo systemctl status git-sync.timer
sudo journalctl -u git-sync.service -n 20

# Manual git sync test
cd /path/to/home-lab
git fetch origin
git status

# Check file permissions
ls -la common/scripts/git-sync.sh
chmod +x common/scripts/git-sync.sh
```

#### **3. Docker compose deployment fails**

**Symptoms:** Services not starting after git sync

**Solutions:**
```bash
# Check deployment logs
sudo journalctl -u docker-redeploy-homelab.service -n 20

# Manual deployment test
cd homelab/service-name
docker compose config  # Validate syntax
docker compose up -d

# Check Docker daemon
sudo systemctl status docker
docker system df  # Check disk space
```

#### **4. SSL certificate issues**

**Symptoms:** HTTPS not working, certificate errors

**Solutions:**
```bash
# Check Caddy logs for certificate errors
docker logs edge-caddy | grep -i cert

# Force certificate renewal
docker exec edge-caddy caddy reload --config /etc/caddy/Caddyfile

# Verify domain accessibility
curl -I https://yourdomain.duckdns.org
```

#### **5. Port conflicts**

**Symptoms:** Services failing to start with port binding errors

**Solutions:**
```bash
# Check port usage
sudo netstat -tulpn | grep :8080
sudo ss -tulpn | grep :8080

# Find conflicting services
docker ps --format "table {{.Names}}\t{{.Ports}}"

# Update port mappings in docker-compose.yml
```

### **Emergency Recovery:**

#### **Complete system reset:**
```bash
# Stop all services
docker compose down
sudo systemctl stop git-sync.timer docker-redeploy-homelab.timer

# Remove all containers and volumes
docker system prune -a --volumes

# Redeploy from scratch
git pull origin main
docker compose up -d
```

#### **Rollback to previous version:**
```bash
# Check git history
git 
>>>>>>> 734c91a1f5d9ed307765c8ee1043eabe2f773384
