#!/bin/bash
set -e

LOG_FILE="/var/log/docker-redeploy.log"
REPO_DIR="/opt/home-lab"

echo "$(date): Starting docker redeploy..." >> "$LOG_FILE"

cd "$REPO_DIR" || {
    echo "$(date): ERROR - Cannot access $REPO_DIR" >> "$LOG_FILE"
    exit 1
}

# Determine which compose files to deploy based on hostname or environment
if [[ -f "homelab/docker-compose.yml" && $(hostname) != *"edge"* ]]; then
    echo "$(date): Deploying homelab services..." >> "$LOG_FILE"
    cd homelab
    docker compose up -d >> "$LOG_FILE" 2>&1
    cd ..
fi

if [[ -f "edge/docker-compose.yml" && $(hostname) == *"edge"* ]]; then
    echo "$(date): Deploying edge services..." >> "$LOG_FILE"
    cd edge
    docker compose up -d >> "$LOG_FILE" 2>&1
    cd ..
fi

echo "$(date): Docker redeploy completed successfully" >> "$LOG_FILE"