#!/bin/bash
set -e

LOG_FILE="/var/log/git-sync.log"
REPO_DIR="/opt/home-lab"
LOCK_FILE="/var/run/git-sync.lock"

# Exit if another instance is running
exec 200>$LOCK_FILE
flock -n 200 || {
    echo "$(date): Another git-sync instance is running" >> "$LOG_FILE"
    exit 0
}

echo "$(date): Starting git sync..." >> "$LOG_FILE"

cd "$REPO_DIR" || {
    echo "$(date): ERROR - Cannot access $REPO_DIR" >> "$LOG_FILE"
    exit 1
}

# Reset any local changes and pull latest
git reset --hard >> "$LOG_FILE" 2>&1
git pull origin main >> "$LOG_FILE" 2>&1

echo "$(date): Git sync completed successfully" >> "$LOG_FILE"