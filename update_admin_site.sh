#!/bin/bash
#
# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ BlissWorld - admin 서비스 선택적 업그레이드 스크립트 ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
#
# 이 스크립트는 nginx 등 다른 서비스는 그대로 둔 채,
# admin 서비스만 새로운 JAR 파일로 교체하여 재시작합니다.
# 전체 재배포가 필요할 경우 redeploy_admin_site.sh를 사용하세요.

set -e # 오류 발생 시 스크립트 중단

# --- 입력 값 검증 ---
if [ -z "$1" ]; then
  echo "❌ 오류: 필수 인자인 새 JAR 파일 이름이 누락되었습니다."
  echo "사용법: $0 <새_JAR_파일_이름>"
  echo "예시:   $0 BlissWorldAdminWas-0.0.4-SNAPSHOT.jar"
  echo "주의:   JAR 파일은 '/home/ubuntu/blissworld/new_jars' 디렉토리에 미리 업로드되어 있어야 합니다."
  exit 1
fi

NEW_JAR_FILE=$1
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
BLISS_DIR="/home/ubuntu/blissworld"
NEW_JARS_DIR="$BLISS_DIR/new_jars"
ADMIN_APPS_DIR="$BLISS_DIR/apps/admin"
SOURCE_JAR_PATH="$NEW_JARS_DIR/$NEW_JAR_FILE"

# --- 메인 로직 ---
echo "🚀 admin 서비스 업그레이드를 시작합니다..."
echo "   - 새 버전: $NEW_JAR_FILE"

# 1. 새 JAR 파일 존재 확인
if [ ! -f "$SOURCE_JAR_PATH" ]; then
  echo "❌ 오류: '$SOURCE_JAR_PATH'에서 새 JAR 파일을 찾을 수 없습니다."
  echo "   파일을 해당 경로에 업로드한 후 다시 시도해주세요."
  exit 1
fi

# 2. 새 JAR 파일을 애플리케이션 디렉토리로 이동 (기존 파일 덮어쓰기)
echo "📦 새 JAR 파일을 '$ADMIN_APPS_DIR'으로 이동합니다..."
sudo mv "$SOURCE_JAR_PATH" "$ADMIN_APPS_DIR/."


# 3. Docker 이미지 빌드를 위해 JAR 파일을 빌드 컨텍스트로 복사
# redeploy_admin_site.sh와 동일한 빌드 메커니즘을 따릅니다.
echo "📦 빌드를 위해 admin jar 복사: $ADMIN_APPS_DIR/$NEW_JAR_FILE → $SCRIPT_DIR/app.jar"
sudo cp "$ADMIN_APPS_DIR/$NEW_JAR_FILE" "$SCRIPT_DIR/app.jar"

# 스크립트 종료 시 임시 파일 자동 삭제
trap 'sudo rm -f "$SCRIPT_DIR/app.jar"' EXIT

# 4. docker-compose.yml이 있는 디렉토리로 이동
cd "$BLISS_DIR"
echo "📂 작업 디렉토리 변경: $(pwd)"

# 5. Docker Compose를 사용하여 admin 서비스만 재빌드 및 재시작
echo "🔄 'docker compose up -d --build admin' 명령으로 admin 서비스를 업그레이드합니다..."
sudo docker compose up -d --build admin

# [추가] admin 서비스가 정상적으로 실행되었는지 Health Check를 수행하네.
echo "🩺 Health checking admin service..."
RETRY_COUNT=0
MAX_RETRIES=12 # 최대 60초 (12 * 5초)
HEALTH_CHECK_URL="https://admin.blissworld.org/actuator/health"

until [ "$(curl -s -o /dev/null -w '%{http_code}' --insecure $HEALTH_CHECK_URL)" == "200" ]; do
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ admin 서비스 Health Check 실패. 컨테이너 로그를 확인해주세요."
    echo "   - sudo docker logs admin"
    exit 1
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "   - (시도 ${RETRY_COUNT}/${MAX_RETRIES}) 애플리케이션이 준비되기를 기다리는 중..."
  sleep 5
done

echo "✅ Health Check 통과. admin 서비스가 정상적으로 응답합니다."

# 6. 불필요한 Docker 이미지 정리
echo "🧹 사용하지 않는 이전 Docker 이미지를 정리합니다..."
sudo docker image prune -f

# [추가] admin 서비스 업데이트 후, 관련 Nginx 설정을 리로드하여 변경사항을 즉시 반영하네.
# 이렇게 하면 client_max_body_size 같은 설정이 누락되는 문제를 방지할 수 있지.
echo "🔄 Nginx 설정을 리로드하여 변경사항을 적용합니다..."
sudo docker exec nginx nginx -t && sudo docker exec nginx nginx -s reload

echo "🎉 admin 서비스 업그레이드가 성공적으로 완료되었습니다."

