#!/bin/bash

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ BlissWorld - admin 서비스 전체 재배포 스크립트 ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

# 스크립트 실행 중 오류가 발생하면 즉시 중단하도록 설정하네.
# 이렇게 해야 중간에 SSL 발급 등이 실패했을 때, 문제가 있음을 바로 알 수 있지.
set -e

JAR_FILE_NAME=$1
DOMAIN="admin.blissworld.org"
PORT=8082
SITE_TYPE="api"
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BLISS_DIR="/home/ubuntu/blissworld"
JAR_PATH="$BLISS_DIR/apps/admin/$JAR_FILE_NAME"

if [ -z "$JAR_FILE_NAME" ]; then
  echo "❌ 사용법: ./redeploy_admin_site.sh <JAR_FILE_NAME>"
  echo "예시: ./redeploy_admin_site.sh BlissWorldAdminWas-0.0.3-SNAPSHOT.jar"
  exit 1
fi

if [ ! -f "$JAR_PATH" ]; then
  echo "❌ 지정한 JAR 파일이 존재하지 않습니다: $JAR_PATH"
  exit 1
fi

echo "📦 admin jar 복사: $JAR_PATH → $SCRIPT_DIR/app.jar"
cp "$JAR_PATH" "$SCRIPT_DIR/app.jar"

echo "🧹 1. 기존 컨테이너 및 설정 정리"
# docker-compose.yml이 있는 blissworld 디렉토리로 이동
cd "$BLISS_DIR"
# docker-compose로 모든 관련 컨테이너와 네트워크를 안전하게 정리하네.
sudo docker compose down --remove-orphans
sudo rm -f /etc/nginx/sites-enabled/*.conf
sudo rm -f /etc/nginx/sites-available/*.conf


echo "🌐 2. Docker 네트워크 생성 (blissworld-net)"
# docker-compose가 사용할 외부 네트워크가 존재하는지 확인하고, 없으면 생성하네.
if ! sudo docker network inspect blissworld-net >/dev/null 2>&1; then
  echo "   - 🔧 네트워크 'blissworld-net'가 없으므로 새로 생성합니다."
  sudo docker network create blissworld-net
else
  echo "   - ✅ 네트워크 'blissworld-net'가 이미 존재합니다."
fi

echo "🚀 3. Docker Compose로 전체 스택 빌드 및 실행"
sudo docker compose up -d --build

echo "🛠️ 4. admin site 설정 및 certbot SSL 발급"
## # docker exec는 컨테이너가 완전히 시작된 후에 실행하는 것이 안전하므로 잠시 대기   ???? 07/26 3줄 삭제
## echo "   - 컨테이너가 안정적으로 시작되도록 5초 대기합니다..."
## sleep 5

# Nginx 컨테이너가 명령을 받을 준비가 될 때까지 안정적으로 기다리네.                  ???? 07/26 line 64~78 추가.
# 'sleep'보다 훨씬 신뢰할 수 있는 방법이지.
echo "   - Nginx 컨테이너가 준비될 때까지 대기 중..."
RETRY_COUNT=0
MAX_RETRIES=12 # 최대 60초 대기 (12 * 5초)
until sudo docker exec nginx nginx -t >/dev/null 2>&1; do
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ Nginx 컨테이너가 시간 내에 준비되지 않았습니다. 로그를 확인해주세요."
    exit 1
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "   - (시도 ${RETRY_COUNT}/${MAX_RETRIES}) 대기 중..."
  sleep 5
done
echo "   - ✅ Nginx 컨테이너 준비 완료."
sudo docker exec -u root admin /app/scripts/setup_admin_site.sh $DOMAIN $PORT $SITE_TYPE

echo "🧪 5. docker.sock 접근 권한 테스트"
if sudo docker exec -u appuser admin docker ps >/dev/null 2>&1; then
  echo "✅ docker.sock 접근 성공 (admin 컨테이너 내부에서 docker ps 동작함)"
else
  echo "❌ docker.sock 접근 실패!"
  echo "    ▶ admin 컨테이너 내부에서 docker 그룹 GID가 호스트와 일치하지 않을 수 있습니다."
fi

echo "🧹 6. 임시 app.jar 파일 정리"
rm -f "$SCRIPT_DIR/app.jar"

# [추가] Java 애플리케이션이 ZIP 파일을 임시 저장할 디렉토리를 미리 생성합니다.
echo "🔧 임시 업로드 디렉토리 준비..."
mkdir -p "$SCRIPT_DIR/uploads"

echo "🧹 7. logs, apps, www, new_jars 디렉토리 소유권 재정의 (도장 찍기)"
for dir in "$SCRIPT_DIR/../logs" "$SCRIPT_DIR/../apps" "$SCRIPT_DIR/../www" "$SCRIPT_DIR/../new_jars" "$SCRIPT_DIR/../data" "$SCRIPT_DIR/uploads"; do
  if [ -d "$dir" ]; then
    echo "    🔧 fixing ownership for $dir"
    sudo chown -R 1001:1001 "$dir"
  else
    echo "    ⚠️  directory $dir not found, skipping."
  fi
done

echo "🎉 완료: https://$DOMAIN"