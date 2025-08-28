#!/bin/bash

# Usage: ./resume_franchise_site.sh <container_name>
if [ -z "$1" ]; then
  echo "Usage: $0 <container_name>"
  exit 1
fi

CONTAINER=$1

# --- 경로 표준화 ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
ADMIN_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$ADMIN_BASE/logs"

RESUME_LOG="$LOG_DIR/franchise_site_resume.csv"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
mkdir -p $LOG_DIR

if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER$"; then
  docker start $CONTAINER
  echo "$CONTAINER,$DATE" | tee -a "$RESUME_LOG" > /dev/null
  echo "▶️ $CONTAINER has been resumed."
else
  echo "⚠️ Container $CONTAINER does not exist. Nothing to resume."
fi
