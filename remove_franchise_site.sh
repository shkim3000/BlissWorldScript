#!/bin/bash

# ---------------------------------------------
# BlissWorld 일반 가맹점(site) 삭제 스크립트
# - Docker 컨테이너 및 이미지 삭제
# - 정적 디렉토리 삭제
# - Nginx conf 제거
# - SSL 인증서 (admin 컨테이너를 통해) 삭제
# ---------------------------------------------
# Usage: ./remove_franchise_site.sh <domain> <container_name>

set -e

# 사용법 체크 추가
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <domain> <container_name>"
  exit 1
fi
DOMAIN=$1
CONTAINER_NAME=$2

# --- 실행 환경 감지 (in-docker or host) ---
IN_DOCKER=false
if [ -f /.dockerenv ] || grep -q 'docker' /proc/1/cgroup 2>/dev/null; then
  IN_DOCKER=true
fi

# --- 경로 표준화 (ADMIN_BASE) ---
if $IN_DOCKER; then
  ADMIN_BASE="/app"
else
  SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
  ADMIN_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

LOG_DIR="$ADMIN_BASE/logs"
WWW_DIR="$ADMIN_BASE/www"
APP_DIR="$ADMIN_BASE/apps"
REMOVE_LOG="$LOG_DIR/franchise_site_remove.csv"
CONF_DIR="/etc/nginx/sites-available"
ENABLED_DIR="/etc/nginx/sites-enabled"

DATE=$(date '+%Y-%m-%d %H:%M:%S')

mkdir -p "$LOG_DIR"

# --- 1. Nginx 설정 제거 ---
echo "🧹 Removing nginx config for $DOMAIN..."
rm -f "$CONF_DIR/$DOMAIN.conf"
rm -f "$ENABLED_DIR/$DOMAIN.conf"

# --- 2. Docker 컨테이너 및 이미지 제거 ---
if docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
  echo "🛑 Stopping and removing container $CONTAINER_NAME..."
  docker stop "$CONTAINER_NAME" || true
  docker rm "$CONTAINER_NAME" || true
  docker rmi -f "${CONTAINER_NAME}-app" || true
else
  echo "⚠️ No such container: $CONTAINER_NAME"
fi

# --- 3. 정적 디렉토리 제거 ---
echo "🗑️ Removing static directories..."
rm -rf "$WWW_DIR/$DOMAIN"
rm -rf "$APP_DIR/$CONTAINER_NAME"

# --- 4. Certbot 인증서 삭제 (nginx 컨테이너를 통해) ---
echo "🔐 Checking for existing SSL certificate for $DOMAIN..."

CERT_NAME=$(docker exec -u root nginx certbot certificates | \
  awk '/Certificate Name: / {cn=$3} /Domains: / && $0 ~ domain {print cn}' domain="$DOMAIN")

if [ -n "$CERT_NAME" ]; then
  echo "   - Certificate found: $CERT_NAME. Deleting..."
  docker exec -u root nginx certbot delete --cert-name "$CERT_NAME" --non-interactive
else
  echo "   - No certificate found for $DOMAIN. Skipping deletion."
fi

# --- 5. Nginx 재시작 ---
echo "🔁 Reloading nginx container..."
docker exec nginx nginx -t && docker exec nginx nginx -s reload

# --- 6. 로그 기록 ---
echo "$DOMAIN,$CONTAINER_NAME,$DATE" | tee -a "$REMOVE_LOG"

echo "✅ $DOMAIN has been fully removed."
