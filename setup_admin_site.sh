#!/bin/bash
# 사용법: ./setup_admin_site.sh <도메인> <포트> <사이트_유형: store/api> [<html_파일명>] [--staging]

set -e

# pipefail 옵션을 설정하여 파이프라인의 어느 한 명령어라도 실패하면 전체를 실패로 처리하네.
# 이렇게 하면 certbot 명령어의 실패를 정확히 감지할 수 있지.    $$$$ 07/26 추가
set -o pipefail

DOMAIN=$1
PORT=$2
SITE_TYPE=$3
HTML_FILE=${4:-index.html} # 기본값 설정
STAGING_FLAG=""
for arg in "$@"; do
    if [ "$arg" == "--staging" ]; then
        STAGING_FLAG="--staging"
        echo "ℹ️  Staging mode enabled. Using Let's Encrypt's test environment."
    fi
done
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

# admin docker안에서만 구동하므로. 
LOG_DIR="/app/logs"
WWW_DIR="/app/www"
FRANCHISE_NAME=$(echo "$DOMAIN" | cut -d. -f1)

CONF_DIR="/etc/nginx/sites-available"
ENABLED_DIR="/etc/nginx/sites-enabled"
CONF_FILE="$CONF_DIR/$DOMAIN.conf"
STATIC_DIR="$WWW_DIR/$DOMAIN"
HISTORY_CSV="$LOG_DIR/franchise_site_history.csv"
CERTBOT_LOG="$LOG_DIR/certbot_output.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# --- 1. 입력 검증 ---
if [ -z "$DOMAIN" ] || [ -z "$PORT" ] || [ -z "$SITE_TYPE" ]; then
  echo "❌ 오류: 필수 인자가 누락되었습니다."
  echo "사용법: $0 <도메인> <포트> <사이트_유형> [<html_파일명>] [--staging]"
  exit 1
fi

if [ "$SITE_TYPE" != "store" ] && [ "$SITE_TYPE" != "api" ]; then
  echo "❌ 오류: 사이트 유형은 'store' 또는 'api'여야 합니다."
  exit 1
fi

# --- 2. 디렉토리 준비 ---
echo "📁 로그 및 기록 파일 디렉토리를 준비합니다..."
mkdir -p "$LOG_DIR"
mkdir -p "$CONF_DIR"
mkdir -p "$ENABLED_DIR"

# --- 3. Nginx 설정 생성 ---
echo "📝 Nginx 설정 생성: $CONF_FILE"
# [수정] webroot 인증을 위해, 초기 설정은 항상 포트 80으로만 생성하고,
# 모든 요청이 /.well-known/acme-challenge/ 경로로 올 수 있도록 location 블록을 추가하네.
cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    # Certbot 인증을 위한 공통 경로
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
}
EOF
echo "✅ 설정 파일이 생성되었습니다."

# --- 4. 사이트 활성화 및 nginx 재시작 ---
echo "🔗 Nginx 사이트를 활성화합니다. 링크생성: $CONF_FILE -> $ENABLED_DIR"
ln -sf "$CONF_FILE" "$ENABLED_DIR/"

echo "🔄 Nginx 설정을 적용하기 위해 리로드합니다..."
# [개선] 설정을 리로드하기 전에, 문법이 올바른지 먼저 테스트하네. 더 안전한 방법이지.
docker exec nginx nginx -t && docker exec nginx nginx -s reload

# --- 5. Certbot 인증서 발급 및 Nginx 자동 설정 ---
echo "🔐 [$(date '+%Y-%m-%d %H:%M:%S')] SSL 인증서 상태를 확인합니다..."

# [개선] 'grep' 명령어는 결과가 없을 때 실패 코드를 반환하여 'set -e'와 충돌할 수 있네.
# 'for' 루프를 사용하여 더 안정적으로 대상 컨테이너를 찾도록 수정하네.
TARGET_CONTAINER_TO_PAUSE=""
for container_name in $(docker ps --format '{{.Names}}'); do
    if [[ "$container_name" != "admin" && "$container_name" != "nginx" && "$container_name" != "$FRANCHISE_NAME" ]]; then
        TARGET_CONTAINER_TO_PAUSE="$container_name"
        break # 첫 번째 하나만 찾으면 되므로 루프를 중단하네.
    fi
done

if [ -n "$TARGET_CONTAINER_TO_PAUSE" ]; then
  echo "⏸️  메모리 확보를 위해 '$TARGET_CONTAINER_TO_PAUSE' 컨테이너를 임시로 중지합니다..."
  docker stop "$TARGET_CONTAINER_TO_PAUSE"
  # [안전장치] 스크립트가 성공하든, 실패하든, 중단되든 항상 컨테이너를 다시 시작하도록 trap을 설정하네.
  trap 'echo "▶️  임시 중지했던 컨테이너 '$TARGET_CONTAINER_TO_PAUSE'를 다시 시작합니다..."; docker start "$TARGET_CONTAINER_TO_PAUSE" >/dev/null 2>&1' EXIT
else
  echo "ℹ️  임시로 중지할 다른 가맹점 컨테이너가 없습니다."
fi

# [개선] Certbot을 실행하기 전에, 도메인이 실제로 이 서버의 IP로 연결되는지 확인하네.
# 이렇게 하면 DNS 설정 오류를 미리 발견하여 불필요한 Certbot 실패를 방지할 수 있지.
echo "🔎 도메인 '$DOMAIN'의 DNS 설정을 확인합니다..."
SERVER_IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(nslookup "$DOMAIN" | awk '/^Address: / { print $2 }' | tail -n1)

if [ -z "$DOMAIN_IP" ]; then
  echo "❌ DNS 조회 실패: 도메인 '$DOMAIN'을 찾을 수 없습니다. DNS A 레코드가 올바르게 설정되었는지 확인하세요."
  exit 1
fi

if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
  echo "❌ DNS 설정 오류: 도메인 '$DOMAIN'($DOMAIN_IP)이 현재 서버 IP($SERVER_IP)를 가리키고 있지 않습니다."
  echo "   DNS 전파에 시간이 걸릴 수 있습니다. 잠시 후 다시 시도하거나 DNS 설정을 확인하세요."
  exit 1
fi
echo "✅ DNS 설정이 올바릅니다. ($DOMAIN -> $SERVER_IP)"

# [개선] Certbot을 실행하기 전에, 유효한 인증서가 이미 있는지 먼저 확인하네.
if docker exec nginx certbot certificates -d "$DOMAIN" 2>/dev/null | grep -q "VALID"; then
  echo "✅ 유효한 인증서가 이미 존재합니다. 발급 단계를 건너뜁니다."
  CERT_RESULT="skipped"
else
  echo "ℹ️  유효한 인증서가 없거나 만료가 가까워지고 있습니다. 새 인증서 발급을 시도합니다..."
fi

if [ "$CERT_RESULT" != "skipped" ]; then
  CERTBOT_CMD="/usr/bin/certbot"

  # [개선] Certbot 실행 시 리소스 문제를 방지하기 위해 몇 가지 옵션을 추가하고, 출력을 파일로 리디렉션하네.
  # --no-self-upgrade: certbot이 스스로 업데이트하는 것을 방지하여 예상치 못한 동작을 막네.
  # --quiet: 불필요한 출력을 줄여주네.
  # 출력을 tee로 파이핑하는 대신, 임시 파일로 리디렉션하여 파이프 관련 문제를 회피하네.
  # [수정] --nginx 플러그인 대신 --webroot 플러그인을 사용하네.
  # 'certonly'는 인증서만 발급하고 Nginx 설정을 건드리지 않아 훨씬 안전하네.
  if ! docker exec nginx $CERTBOT_CMD certonly --webroot -w /var/www/certbot -d "$DOMAIN" --non-interactive --agree-tos -m "admin@$DOMAIN" --no-self-upgrade --quiet $STAGING_FLAG > "$CERTBOT_LOG.tmp" 2>&1; then
    cat "$CERTBOT_LOG.tmp" >> "$CERTBOT_LOG" && rm -f "$CERTBOT_LOG.tmp"
    CERT_RESULT="failed"
    echo "❌ Certbot 인증 실패. 로그 확인: $CERTBOT_LOG"
    exit 1 # Certbot이 실패하면 스크립트를 즉시 중단하여 상위 프로세스에 오류를 알리네.
  else
    cat "$CERTBOT_LOG.tmp" >> "$CERTBOT_LOG" && rm -f "$CERTBOT_LOG.tmp"
    echo "✅ Certbot 인증 성공."
    CERT_RESULT="success"
  fi
fi

# --- 6. SSL 적용된 최종 Nginx 설정 생성 ---
if [[ "$CERT_RESULT" == "success" || "$CERT_RESULT" == "skipped" ]]; then
  echo "📝 SSL이 적용된 최종 Nginx 설정을 생성합니다..."

  # [개선] proxy_pass에 변수를 사용하기 위해, Docker의 내장 DNS 리졸버를 명시적으로 지정하네.
  # 127.0.0.11은 Docker 컨테이너 내부에서 항상 DNS 서버를 가리키는 특수 IP일세.
  # 이렇게 하면 Nginx가 시작 시점이 아닌, 실제 요청이 올 때 동적으로 서비스 이름을 해석하여
  # 다른 컨테이너가 아직 준비되지 않았더라도 Nginx가 정상적으로 시작될 수 있네.
  RESOLVER_LINE="    resolver 127.0.0.11 valid=10s;"
  UPSTREAM_VAR="    set \$upstream http://$FRANCHISE_NAME:8080;"

  # ✅ 조건부 MAX_BODY_SIZE 변수 설정
  MAX_BODY_SIZE_LINE=""
  if [ "$SITE_TYPE" == "api" ] && [ "$FRANCHISE_NAME" == "admin" ]; then
    # [개선] admin 서비스는 대용량 파일 업로드를 처리하므로, 타임아웃 시간을 넉넉하게 300초로 설정하네.
    # 이렇게 하면 파일 업로드 중 연결이 끊어지는 "Error writing to server" 문제를 방지할 수 있지.
    MAX_BODY_SIZE_LINE=$(cat <<-EOF
    client_max_body_size 100M;
    proxy_connect_timeout 300s;
    proxy_send_timeout    300s;
    proxy_read_timeout    300s;
EOF
    )
  fi

  if [ "$SITE_TYPE" == "store" ]; then
    cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    root $STATIC_DIR;
    index $HTML_FILE;

    location / {
        try_files \$uri \$uri/ =404;
    }

    $RESOLVER_LINE
    $UPSTREAM_VAR

    # --- (1) actuator 전용: /api/actuator/* -> /actuator/* ---
    location ~ ^/api/(actuator/.*)$ {
        proxy_pass \$upstream/\$1;          # \$1 = actuator/...
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # --- (2) 일반 API: /api/* 은 그대로 전달 ---
    location /api/ {
        proxy_pass \$upstream;
        proxy_set_header Host \$host; # 클라이언트가 요청한 원래 도메인을 백엔드로 전달
        proxy_set_header X-Real-IP \$remote_addr; # 클라이언트의 실제 IP 주소를 전달
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; # 프록시를 거친 클라이언트 IP 목록을 전달
        proxy_set_header X-Forwarded-Proto \$scheme; # 원래 요청이 http였는지 https였는지 전달
    }
}
EOF

  elif [ "$SITE_TYPE" == "api" ]; then
    cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    $RESOLVER_LINE
    $UPSTREAM_VAR
    $MAX_BODY_SIZE_LINE

    # --- (1) actuator 전용: /api/actuator/* -> /actuator/* ---
    location ~ ^/api/(actuator/.*)$ {
        proxy_pass \$upstream/\$1;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
    
    # --- (2) 나머지 전 경로 프록시 ---
    location / {
        proxy_pass \$upstream;
        proxy_set_header Host \$host; # 클라이언트가 요청한 원래 도메인을 백엔드로 전달
        proxy_set_header X-Real-IP \$remote_addr; # 클라이언트의 실제 IP 주소를 전달
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for; # 프록시를 거친 클라이언트 IP 목록을 전달
        proxy_set_header X-Forwarded-Proto \$scheme; # 원래 요청이 http였는지 https였는지 전달
    }
}
EOF

  fi

  echo "🔁 최종 Nginx 설정을 적용하기 위해 리로드합니다..."
  docker exec nginx nginx -t && docker exec nginx nginx -s reload
  echo "🔐 [$(date '+%Y-%m-%d %H:%M:%S')] SSL 설정 적용 완료: $DOMAIN"
else
  echo "⚠️ 인증서가 발급되지 않아 SSL 설정을 생략합니다."
fi


# --- 7. 기록 저장 ---
echo "$DOMAIN,$PORT,$SITE_TYPE,$DATE,$CERT_RESULT" | tee -a "$HISTORY_CSV" > /dev/null

echo "🎉 $DOMAIN 사이트 설정 완료. 포트: $PORT, SSL 상태: $CERT_RESULT"
