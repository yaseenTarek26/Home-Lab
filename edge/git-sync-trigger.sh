#!/bin/bash
set -e

LOG_FILE="/var/log/git-sync.log"
REPO_DIR="/opt/home-lab"

echo "$(date): Starting git sync with Caddy reload trigger..." >> "$LOG_FILE"

cd "$REPO_DIR" || {
    echo "$(date): ERROR - Cannot access $REPO_DIR" >> "$LOG_FILE"
    exit 1
}

# Reset any local changes and pull latest
git reset --hard >> "$LOG_FILE" 2>&1
git pull origin main >> "$LOG_FILE" 2>&1

echo "$(date): Git sync completed successfully" >> "$LOG_FILE"

# Trigger Caddy reload immediately after git sync
echo "$(date): Triggering Caddy reload..." >> "$LOG_FILE"
cd "$REPO_DIR/edge" || {
    echo "$(date): ERROR - Cannot access edge directory" >> "$LOG_FILE"
    exit 1
}

./generate-caddyfile.sh >> "$LOG_FILE" 2>&1
echo "$(date): Caddy reload triggered successfully" >> "$LOG_FILE"
