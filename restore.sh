#!/bin/bash
set -e

set -a && source .env && set +a

BACKUP_FILE="$1"

if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: $0 <path/to/backup.sql.gz>"
  exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
  echo "Error: file not found: $BACKUP_FILE"
  exit 1
fi

read -p "Are you sure? This will overwrite current data [y/N]: " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "Aborted."
  exit 0
fi

gunzip -c "$BACKUP_FILE" | docker exec -i shared-mysql mysql -uroot -p"$MYSQL_ROOT_PASSWORD"

echo "Restore complete from: $BACKUP_FILE"
