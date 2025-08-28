#!/bin/bash
# usage: ./audit_vhosts.sh store1.blissworld.org store2.blissworld.org ...

set -e
NGINX=nginx

for DOMAIN in "$@"; do
  FRANCHISE="${DOMAIN%%.*}"  # 첫 라벨이 컨테이너명이라고 가정 (store1 등)
  echo "=== $DOMAIN (upstream: $FRANCHISE:8080) ==="

  docker exec $NGINX bash -lc "test -f /etc/nginx/sites-enabled/$DOMAIN.conf && echo '[OK] conf enabled' || echo '[MISS] conf missing'"
  docker exec $NGINX nginx -t >/dev/null && echo "[OK] nginx -t" || { echo "[ERR] nginx -t"; exit 1; }

  docker exec $NGINX bash -lc "grep -q \"server_name $DOMAIN;\" /etc/nginx/sites-enabled/$DOMAIN.conf && echo '[OK] server_name' || echo '[ERR] server_name'"

  docker exec $NGINX bash -lc "grep -q \"set \\$upstream http://$FRANCHISE:8080;\" /etc/nginx/sites-enabled/$DOMAIN.conf && echo '[OK] upstream var' || echo '[WARN] upstream var not found'"

  docker exec $NGINX bash -lc "curl -s -o /dev/null -w '%{http_code}' http://$FRANCHISE:8080/actuator/health" | grep -q 200 \
    && echo "[OK] upstream health" || echo "[ERR] upstream health"

  curl -s -o /dev/null -w "%{http_code} https_status=%{http_code}\n" "https://$DOMAIN/api/actuator/health" | grep -q 200 \
    && echo "[OK] external via vhost" || echo "[ERR] external via vhost"

  echo
done
