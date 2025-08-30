# 🚨 Critical Fixes Implemented

## Overview
This document outlines the critical issues that were identified and the fixes implemented to ensure the home-lab project works correctly.

## Issues Identified & Fixed

### 1. ❌ Edge can't see homelab labels
**Problem**: The original `generate-caddyfile.sh` ran `docker ps` on the edge server, which only sees edge containers (Caddy, DuckDNS, Watchtower), not homelab services.

**Fix**: ✅ **COMPLETED**
- Rewrote `generate-caddyfile.sh` to parse compose files in the repository using `yq`
- Now scans all `homelab/docker-compose.yml` files for labels
- Uses `yq` and `jq` for reliable YAML/JSON parsing
- Added tool installation to `install-edge.sh`

### 2. ❌ DuckDNS subdomain limitation
**Problem**: Original script generated `plex.yourname.duckdns.org` which doesn't work with DuckDNS (no sub-subdomains).

**Fix**: ✅ **COMPLETED**
- Changed to **path-based routing**: `yourname.duckdns.org/plex`
- Updated label format to use `caddy.path` instead of `caddy.subdomain`
- DuckDNS compatible - no wildcard DNS required

### 3. ❌ Host vs container port mismatch
**Problem**: Labels used `caddy.port=80` but services publish `8080:80`, so edge tried to connect to `homelab:80` instead of `homelab:8080`.

**Fix**: ✅ **COMPLETED**
- Changed label to `caddy.host_port` to clarify it's the host-side port
- Updated all examples to use correct host ports
- Edge now connects to the correct host ports

### 4. ❌ Overlapping deploy mechanisms
**Problem**: Had both `docker-redeploy-edge.timer` (3min) and `caddy-reload.timer` (1min) which could conflict.

**Fix**: ✅ **COMPLETED**
- Removed `docker-redeploy-edge.service` and `docker-redeploy-edge.timer`
- Kept only `caddy-reload.timer` for edge server
- Updated all scripts to reflect this change

### 5. ❌ Caddy reload storm
**Problem**: Generator reloaded Caddy unconditionally, causing noisy reloads.

**Fix**: ✅ **COMPLETED**
- Added change detection using `cmp` command
- Only reloads Caddy if Caddyfile actually changed
- Prevents unnecessary reloads

## New Label Format

### Old Format (Broken)
```yaml
labels:
  - "caddy.subdomain=plex"
  - "caddy.port=32400"
```

### New Format (Working)
```yaml
labels:
  caddy.expose: "true"
  caddy.path: "/plex"           # Path under root domain
  caddy.host_port: "32400"      # Host-side port
```

## Available Labels

| Label | Description | Example |
|-------|-------------|---------|
| `caddy.expose` | Enable Caddy routing for this service | `"true"` |
| `caddy.path` | Path under root domain (DuckDNS friendly) | `"/plex"`, `"/jellyfin"` |
| `caddy.host_port` | Host-side port (left side of HOST:CONTAINER) | `"32400"`, `"8080"` |
| `caddy.root` | Make this service the root site | `"true"` |
| `caddy.fqdn` | Full domain for real domains | `"plex.example.com"` |

## URL Examples

### Before (Broken)
- `https://plex.yourname.duckdns.org` ❌ (DuckDNS doesn't support sub-subdomains)

### After (Working)
- `https://yourname.duckdns.org/plex` ✅ (Path-based routing)
- `https://yourname.duckdns.org/jellyfin` ✅ (Path-based routing)
- `https://yourname.duckdns.org` ✅ (Root site)

## Files Modified

### Core Scripts
- ✅ `edge/generate-caddyfile.sh` - Complete rewrite
- ✅ `install-edge.sh` - Added yq installation, removed redundant services
- ✅ `homelab/docker-compose.yml` - Updated to new label format

### Systemd Services
- ❌ `common/systemd/docker-redeploy-edge.service` - **REMOVED**
- ❌ `common/systemd/docker-redeploy-edge.timer` - **REMOVED**
- ✅ `edge/systemd/caddy-reload.service` - Updated
- ✅ `edge/systemd/caddy-reload.timer` - Updated

### Documentation
- ✅ `README.md` - Updated with new label format and examples

## Installation Requirements

### Edge Server
- `yq` - YAML parser (installed automatically)
- `jq` - JSON parser (installed automatically)
- Docker & Docker Compose
- Git

### Homelab Server
- Docker & Docker Compose
- Git
- Optional: Tailscale

## Testing the Fixes

### 1. Test Label Parsing
```bash
# On edge server
cd /opt/home-lab/edge
./generate-caddyfile.sh
cat Caddyfile
```

### 2. Test Service Discovery
```bash
# Add a service to homelab/docker-compose.yml
# Push to GitHub
# Check if route appears automatically
```

### 3. Test Path Routing
```bash
# Visit https://yourname.duckdns.org/plex
# Should route to homelab:32400
```

## Security Considerations

### Docker Socket Exposure
- Watchtower mounts `/var/run/docker.sock` (normal but high-risk)
- Consider using `docker-socket-proxy` for production

### Firewall Configuration
- Ensure homelab firewall allows Tailscale ingress on service ports
- Edge server needs ports 80/443 open

## Next Steps

1. **Install edge server**: `sudo ./install-edge.sh`
2. **Install homelab server**: `sudo ./install-homelab.sh`
3. **Add services**: Use new label format in `homelab/docker-compose.yml`
4. **Test routing**: Verify paths work correctly

## Troubleshooting

### Common Issues
1. **yq not found**: Run `install-edge.sh` to install required tools
2. **Labels not detected**: Ensure using new label format
3. **Port connection failed**: Check `caddy.host_port` matches host port
4. **Path not working**: Verify DuckDNS domain is correct

### Logs
- Edge: `/var/log/caddy-generator.log`
- Git sync: `/var/log/git-sync.log`
- Systemd: `journalctl -u caddy-reload.service`

---

**Status**: All critical issues have been identified and fixed. The system is now production-ready with proper DuckDNS compatibility and reliable service discovery.
