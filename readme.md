# 🏠 Home Lab - Modular Labels-Based Automation

A **production-ready, scalable** home lab setup with **hybrid routing support** using Docker labels. Supports both path-based routing (DuckDNS) and subdomain routing (wildcard DNS) with automatic service discovery.

## 🎯 **Key Features**

- ✅ **Hybrid Routing**: Path-based (DuckDNS) or subdomain (wildcard DNS) - switch with one line
- ✅ **Modular Architecture**: Clean separation of concerns, maintainable codebase
- ✅ **Service Discovery**: Discovers services from compose files AND running containers
- ✅ **CasaOS Compatible**: Works alongside CasaOS without conflicts
- ✅ **Validation & Error Handling**: Comprehensive validation and error recovery
- ✅ **Future-Proof**: Easy to switch DNS providers or add new features

## 🏗️ **Architecture Overview**

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   GitHub Repo   │    │   Edge Server   │    │   Homelab       │
│                 │    │   (Oracle)      │    │   (Local)       │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │ docker-     │ │    │ │ Caddy       │ │    │ │ Services    │ │
│ │ compose.yml │ │───▶│ │ (Reverse    │ │───▶│ │ (Plex, etc) │ │
│ │ with labels │ │    │ │  Proxy)     │ │    │ │             │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                │                        │
                                │                        │
                        ┌───────▼───────┐        ┌───────▼───────┐
                        │ Label        │        │ Label        │
                        │ Reporter     │        │ Reporter     │
                        │ (Edge)       │        │ (Homelab)    │
                        └───────────────┘        └───────────────┘
```

## 📁 **Project Structure**

```
home-lab/
├── edge/                          # Edge server (Oracle Cloud)
│   ├── docker-compose.yml         # Caddy + Watchtower + DuckDNS
│   ├── generate-caddyfile.sh      # Modular Caddyfile generator
│   ├── config.env                 # Edge configuration
│   ├── Caddyfile                  # Auto-generated (do not edit)
│   └── systemd/
│       ├── caddy-reload.service   # Regenerates Caddyfile
│       └── caddy-reload.timer     # Runs every minute
├── homelab/                       # Homelab server (Local)
│   ├── docker-compose.yml         # Your services with labels
│   ├── website/                   # Static website files
│   └── label-reporter/            # Service discovery
│       ├── report-labels.sh       # Container label scanner
│       └── reports/               # Generated reports
├── common/                        # Shared scripts and configs
│   ├── scripts/
│   │   └── git-sync.sh            # Git sync automation
│   └── systemd/
│       ├── git-sync.service       # Git sync service
│       ├── git-sync.timer         # Git sync timer
│       ├── docker-redeploy-homelab.service
│       ├── docker-redeploy-homelab.timer
│       ├── label-reporter.service # Label reporter service
│       └── label-reporter.timer   # Label reporter timer
├── setup-complete.sh              # Complete automated setup
├── validate-config.sh             # Comprehensive validation
├── install-edge.sh               # Edge server setup script
├── install-homelab.sh            # Homelab server setup script
└── CRITICAL_FIXES.md             # Detailed fix documentation
```

## 🚀 **Quick Start**

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
- Configure logging and validation
- Validate configuration

### **Option 2: Manual Setup**

#### 1. Edge Server Setup (Oracle Cloud)

```bash
# Clone and run setup
git clone https://github.com/yourusername/home-lab.git
cd home-lab
chmod +x install-edge.sh

# Edit configuration
nano edge/config.env

# Run setup
sudo ./install-edge.sh
```

#### 2. Homelab Server Setup (Local)

```bash
# Clone and run setup
git clone https://github.com/yourusername/home-lab.git
cd home-lab
chmod +x install-homelab.sh
sudo ./install-homelab.sh
```

### **3. Validate Installation**

```bash
# Run comprehensive validation
chmod +x validate-config.sh
sudo ./validate-config.sh
```

### 4. Add Your First Service

Edit `homelab/docker-compose.yml`:

```yaml
services:
  my-app:
    image: nginx:alpine
    ports:
      - "8080:80"
    labels:
      caddy.expose: "true"
      caddy.path: "/myapp"
      caddy.host_port: "8080"
```

Push to GitHub:
```bash
git add .
git commit -m "Add my-app service"
git push origin main
```

**Result**: `https://yourdomain.com/myapp` is automatically live! 🎉

## 📋 **Available Labels**

| Label | Description | Example |
|-------|-------------|---------|
| `caddy.expose` | Enable Caddy routing for this service | `"true"` |
| `caddy.path` | Path under root domain (DuckDNS friendly) | `"/plex"`, `"/jellyfin"` |
| `caddy.host_port` | Host-side port (left side of HOST:CONTAINER) | `"32400"`, `"8080"` |
| `caddy.root` | Make this service the root site | `"true"` |
| `caddy.fqdn` | Full domain for real domains | `"plex.example.com"` |

## 🔧 **Configuration**

### **Edge Server Settings**

Edit `edge/config.env`:
```bash
# Domain Configuration
DOMAIN=yourname.duckdns.org
HOMELAB_IP=100.x.x.x

# Routing Mode
# Options: "path" (for DuckDNS) or "subdomain" (for wildcard DNS providers)
ROUTING_MODE=path

# Validation and Debugging
ENABLE_VALIDATION=true
ENABLE_DEBUG=false
```

### **Switching Routing Modes**

#### **Path-Based Routing (DuckDNS)**
```bash
# In edge/config.env
ROUTING_MODE=path
```
**URLs**: `yourdomain.com/plex`, `yourdomain.com/jellyfin`

#### **Subdomain Routing (Wildcard DNS)**
```bash
# In edge/config.env
ROUTING_MODE=subdomain
```
**URLs**: `plex.yourdomain.com`, `jellyfin.yourdomain.com`

### **DuckDNS Setup**

Edit `edge/docker-compose.yml`:
```yaml
duckdns:
  environment:
    - SUBDOMAINS=yourusername
    - TOKEN=your-duckdns-token
```

## 📊 **Monitoring & Logs**

### **Check Service Status**
```bash
# Edge server
sudo systemctl status caddy-reload.timer
sudo systemctl status git-sync.timer
sudo systemctl status label-reporter.timer

# View logs
tail -f /var/log/caddy-generator.log
tail -f /var/log/git-sync.log
tail -f /var/log/label-reporter.log
```

### **Manual Caddyfile Regeneration**
```bash
cd /opt/home-lab/edge
./generate-caddyfile.sh
```

### **Validation**
```bash
# Run comprehensive validation
sudo ./validate-config.sh
```

## 🔄 **Adding New Services**

### **Step 1: Add Service to Homelab**
Edit `homelab/docker-compose.yml`:

```yaml
services:
  new-service:
    image: your-image:latest
    ports:
      - "8080:80"
    labels:
      caddy.expose: "true"
      caddy.path: "/newservice"
      caddy.host_port: "8080"
```

### **Step 2: Deploy**
```bash
# On homelab server
docker compose up -d new-service

# Push to GitHub
git add .
git commit -m "Add new-service"
git push origin main
```

### **Step 3: Done!**
The route `https://yourdomain.com/newservice` is automatically created! 🎉

## 🛠️ **Troubleshooting**

### **Quick Diagnostics**

```bash
# Run comprehensive validation
sudo ./validate-config.sh

# Check system status
sudo systemctl status git-sync.timer docker-redeploy-homelab.timer caddy-reload.timer

# View recent logs
tail -f /var/log/git-sync.log
tail -f /var/log/caddy-generator.log
tail -f /var/log/label-reporter.log
```

### **Common Issues & Solutions**

#### **Route Not Working?**
1. **Check service status**: `docker ps`
2. **Verify labels**: `docker inspect container-name`
3. **Check Caddyfile**: `cat /opt/home-lab/edge/Caddyfile`
4. **View logs**: `tail -f /var/log/caddy-generator.log`
5. **Test connectivity**: `ping homelab-tailscale-ip`
6. **Check routing mode**: `grep ROUTING_MODE /opt/home-lab/edge/config.env`

#### **Git Sync Issues?**
1. **Check timer status**: `sudo systemctl status git-sync.timer`
2. **View sync logs**: `tail -f /var/log/git-sync.log`
3. **Manual sync**: `sudo systemctl start git-sync.service`
4. **Check permissions**: `ls -la /opt/home-lab/common/scripts/git-sync.sh`

#### **Caddy Not Reloading?**
1. **Check container**: `docker ps | grep caddy`
2. **Manual reload**: `docker exec edge-caddy caddy reload`
3. **Restart Caddy**: `docker compose restart caddy`
4. **Check timer**: `sudo systemctl status caddy-reload.timer`
5. **Check configuration**: `cat /opt/home-lab/edge/config.env`

#### **Label Reporter Issues?**
1. **Check service**: `sudo systemctl status label-reporter.timer`
2. **View logs**: `tail -f /var/log/label-reporter.log`
3. **Manual scan**: `sudo /opt/home-lab/homelab/label-reporter/report-labels.sh`
4. **Check reports**: `cat /opt/home-lab/homelab/label-reporter/reports/caddy-services.json`

#### **Docker Issues?**
1. **Check Docker daemon**: `sudo systemctl status docker`
2. **Check disk space**: `df -h`
3. **Clean up Docker**: `docker system prune -a`
4. **Restart Docker**: `sudo systemctl restart docker`

### **Emergency Recovery**

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
