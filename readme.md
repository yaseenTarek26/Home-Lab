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
