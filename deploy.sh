#!/bin/bash
set -e

if [ ! -f ".env" ]; then
  echo "Error: .env not found. Copy .env.example to .env and fill in your passwords."
  exit 1
fi

echo "Checking shared-db-net exists on Pi..."
if ! ssh rpi5 'docker network inspect shared-db-net' > /dev/null 2>&1; then
  echo "Error: shared-db-net network not found on Pi."
  echo "Create it first with: ssh rpi5 'docker network create shared-db-net'"
  exit 1
fi

RSYNC_EXTRA=""
if [ "$1" = "--with-env" ]; then
  RSYNC_EXTRA="--include=.env"
fi

echo "Syncing files to Pi..."
rsync -avz --delete \
  --exclude='.git' \
  --exclude='backups/' \
  --exclude='.DS_Store' \
  --exclude='.env' \
  $RSYNC_EXTRA \
  . airlangga@rpi5:/home/airlangga/apps/shared-db/

echo "Starting stack on Pi..."
ssh rpi5 'cd ~/apps/shared-db && docker compose pull && docker compose up -d'

echo "Waiting for container to settle..."
sleep 10

echo "Stack status:"
ssh rpi5 'cd ~/apps/shared-db && docker compose ps'
