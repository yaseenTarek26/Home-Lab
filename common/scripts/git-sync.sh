
#!/bin/bash

# Navigate to repo root
cd /path/to/home-lab

# Pull latest changes
git fetch origin
git reset --hard origin/main

# Log the sync
echo "$(date): Repository synced successfully" >> /var/log/git-sync.log

exit 0
#!/bin/bash
set -e

LOG_FILE="/var/log/git-sync.log"
REPO_DIR="/opt/home-lab"

echo "$(date): Starting git sync..." >> "$LOG_FILE"

cd "$REPO_DIR" || {
    echo "$(date): ERROR - Cannot access $REPO_DIR" >> "$LOG_FILE"
    exit 1
}

# Reset any local changes and pull latest
git reset --hard >> "$LOG_FILE" 2>&1
git pull origin main >> "$LOG_FILE" 2>&1

echo "$(date): Git sync completed successfully" >> "$LOG_FILE"