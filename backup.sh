#!/usr/bin/env bash
# backup.sh — tarball world/ into backups/, prune to last 24 snapshots.
# Add to cron for hourly backups:
#   0 * * * * /path/to/btwce-server/backup.sh >> /path/to/btwce-server/logs/backup.log 2>&1
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

WORLD="world"
BACKUP_DIR="backups"
MAX=24

mkdir -p "$BACKUP_DIR"
if [ ! -d "$WORLD" ]; then
  echo "[$(date)] no $WORLD/, nothing to back up"
  exit 0
fi

TS=$(date +%Y-%m-%d_%H-%M-%S)
FILE="$BACKUP_DIR/world_${TS}.tar.gz"
echo "[$(date)] archiving $WORLD -> $FILE"
tar -czf "$FILE" -C . "$WORLD"
SIZE=$(du -h "$FILE" | cut -f1)
echo "[$(date)] saved $FILE ($SIZE)"

COUNT=$(ls -1t "$BACKUP_DIR"/world_*.tar.gz 2>/dev/null | wc -l)
if [ "$COUNT" -gt "$MAX" ]; then
  N=$((COUNT - MAX))
  ls -1t "$BACKUP_DIR"/world_*.tar.gz | tail -n "$N" | xargs -r rm -f
  echo "[$(date)] pruned $N old backup(s)"
fi
