#!/bin/bash
set -e

set -a && source .env && set +a

BACKUP_DIR="${BACKUP_DIR:-/home/airlangga/apps/shared-db/backups}"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUT="$BACKUP_DIR/all-databases-$TIMESTAMP.sql.gz"

docker exec shared-mysql \
  mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" \
  --all-databases --single-transaction --routines --triggers \
  | gzip > "$OUT"

echo "Backup written: $OUT"

ls -1t "$BACKUP_DIR"/all-databases-*.sql.gz | tail -n +15 | xargs -r rm --
