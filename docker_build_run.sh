#!/bin/bash
# Usage: ./docker_build_run.sh <franchise_name> <port> <jar_file> [profile] [network_name] [site_type]

set -e

#-----------------------------
# Args & Defaults
#-----------------------------
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ] || [ -z "$7" ]; then
  echo "Usage: $0 <franchise_name> <port> <jar_file> <profile> <network_name> <site_type> <domain>"
  exit 1
fi

APP_NAME="$1"
PORT="$2"
JAR_FILE="$3"
PROFILE="${4:-prod}"
NETWORK="${5:-bridge}"
SITE_TYPE="${6:-store}"
DOMAIN="${7}" # 도메인은 store 타입일 때만 의미가 있지만, 일관성을 위해 항상 받습니다.
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "🌐 Docker 네트워크: $NETWORK"
echo "🏷  SITE_TYPE: $SITE_TYPE"

#-----------------------------
# Where am I?
#-----------------------------
SCRIPT_DIR=$(
  cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd
)

IN_DOCKER=false
if [ -f /.dockerenv ] || grep -q 'docker' /proc/1/cgroup 2>/dev/null; then
  IN_DOCKER=true
fi

#-----------------------------
# Base Paths (ADMIN_BASE vs HOST_BASE)
#  - ADMIN_BASE: 현재 프로세스(admin 컨테이너 또는 호스트)에서 보이는 경로
#  - HOST_BASE : docker 데몬이 바라보는 호스트 경로( -v 좌측 )
#-----------------------------
if $IN_DOCKER; then
  # admin 컨테이너 내부
  ADMIN_BASE="/app"
  HOST_BASE="${HOST_PROJECT_PATH:-/home/ubuntu/blissworld}"   # compose에서 주입됨
else
  # 호스트에서 직접 실행
  ADMIN_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
  HOST_BASE="$ADMIN_BASE"
fi

## WWW base paths (store 타입 전용)
WWW_BASE_ADMIN="$ADMIN_BASE/www"
WWW_BASE_HOST="$HOST_BASE/www"

# Admin(현재 프로세스)에서 접근할 경로 (존재 확인/복사/로그 기록 등)
APP_DIR_ADMIN="$ADMIN_BASE/apps/$APP_NAME"
LOG_DIR_ADMIN="$ADMIN_BASE/logs"
KEY_FILE_ADMIN="$ADMIN_BASE/keys/blissworld-firebase-key.json"
WWW_DIR_ADMIN="$WWW_BASE_ADMIN/$DOMAIN" # [수정] www 경로는 이제 domain을 기준으로 합니다.

# docker run -v 소스로 사용할 호스트 경로
APP_DIR_HOST="$HOST_BASE/apps/$APP_NAME"
LOG_DIR_HOST="$HOST_BASE/logs"
KEY_FILE_HOST="$HOST_BASE/keys/blissworld-firebase-key.json"
WWW_DIR_HOST="$WWW_BASE_HOST/$DOMAIN" # [수정] www 경로는 이제 domain을 기준으로 합니다.

# 공용 경로/파일
JAR_PATH="$APP_DIR_ADMIN/$JAR_FILE"
LOG_FILE="$LOG_DIR_ADMIN/docker_build.log"
DOCKERFILE_NAME="Dockerfile.store"

# 디렉토리 준비 (admin 측에서 생성하면 호스트에도 반영됨)
mkdir -p "$LOG_DIR_ADMIN" "$APP_DIR_ADMIN"
mkdir -p "$LOG_DIR_ADMIN/$APP_NAME"

chown 1001:1001 "$LOG_DIR_ADMIN" "$LOG_DIR_ADMIN/$APP_NAME"


#-----------------------------
# Sanity Checks
#-----------------------------
if [ ! -f "$SCRIPT_DIR/$DOCKERFILE_NAME" ]; then
  echo "[ERROR] Dockerfile not found: $SCRIPT_DIR/$DOCKERFILE_NAME" | tee -a "$LOG_FILE"
  exit 1
fi

if [ ! -f "$JAR_PATH" ]; then
  echo "[ERROR] JAR file not found: $JAR_PATH" | tee -a "$LOG_FILE"
  exit 1
fi

# Firebase 키는 store 타입에서만 필수
if [ "$SITE_TYPE" = "store" ]; then
  if [ ! -f "$KEY_FILE_ADMIN" ]; then
    echo "❌ [ERROR] Firebase key file does not exist: $KEY_FILE_ADMIN" | tee -a "$LOG_FILE"
    exit 1
  fi

  # [수정] store 타입이면 www 디렉터리를 준비합니다.
  # 이 스크립트는 setup_franchise_site.sh 보다 먼저 실행되므로, www 디렉터리의 존재를 직접 보장해야 합니다.
  if [ ! -d "$WWW_DIR_ADMIN" ]; then
    echo "[INFO] www 디렉터리 생성: $WWW_DIR_ADMIN" | tee -a "$LOG_FILE"
    mkdir -p "$WWW_DIR_ADMIN" || { echo "[ERROR] $WWW_DIR_ADMIN 생성 실패"; exit 1; }
  fi
fi

#-----------------------------
# Workdir for docker build
#-----------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT
cp "$JAR_PATH" "$WORK_DIR/app.jar"

#-----------------------------
# Build Image
#-----------------------------
echo "🐳 Building Docker image for $APP_NAME using $DOCKERFILE_NAME..."
docker build \
  --label "original.jar.file=$JAR_FILE" \
  -t "$APP_NAME-app" \
  -f "$SCRIPT_DIR/$DOCKERFILE_NAME" \
  "$WORK_DIR" >> "$LOG_FILE" 2>&1 &

BUILD_PID=$!
spin_chars=("⠇" "⠏" "⠋" "⠙" "⠸" "⠴" "⠦" "⠧")
echo -n "   Building... "
while ps -p "$BUILD_PID" > /dev/null; do
  for i in "${spin_chars[@]}"; do
    echo -ne "\033[0;36m${i}\033[0m"
    sleep 0.1
    echo -ne "\b"
  done
done
wait $BUILD_PID
BUILD_STATUS=$?

if [ $BUILD_STATUS -ne 0 ]; then
  echo -e "\r\033[K[$DATE] [ERROR] Build failed for $APP_NAME. See $LOG_FILE" | tee -a "$LOG_FILE"
  exit 1
else
  echo -e "\r\033[K✅ Image built successfully for $APP_NAME."
fi

#-----------------------------
# Deduplicate / Port check
#-----------------------------
if docker ps --format '{{.Names}}' | grep -q "^${APP_NAME}$"; then
  echo "⚠️  [WARNING] 컨테이너 '$APP_NAME' 이 이미 실행 중입니다. 제거 후 재실행합니다."
  docker rm -f "$APP_NAME" >> "$LOG_FILE" 2>&1 || true
fi

if docker ps --format '{{.Names}} {{.Ports}}' | grep -q ":$PORT->8080"; then
  echo "❌ [ERROR] 포트 $PORT 를 이미 사용 중인 컨테이너가 있습니다."
  echo "🛑 스크립트를 중단합니다. 충돌을 해결한 후 다시 실행하십시오."
  exit 1
fi

#-----------------------------
# Run Container
#  -v 좌측은 반드시 HOST 경로를 사용
#-----------------------------
DOCKER_RUN_ARGS=(
  -d
  --restart unless-stopped
  --name "$APP_NAME"
  --network "$NETWORK"
  -p "$PORT:8080"
  -e "SPRING_PROFILES_ACTIVE=$PROFILE"
  -e "GLOBAL_START_STATE=setup"
  --memory="256m"
  --cpus="0.5"
  -v "$LOG_DIR_HOST/$APP_NAME":/app/logs
  --label "site.type=$SITE_TYPE"
  --label "site.domain=$DOMAIN" # [추가] 컨테이너에 도메인 라벨을 추가하여, 업데이트 시 www 경로를 식별할 수 있도록 합니다.
)

# store 타입만 키 마운트
if [ "$SITE_TYPE" = "store" ]; then
  DOCKER_RUN_ARGS+=( -v "$KEY_FILE_HOST":/app/keys/blissworld-firebase-key.json:ro )

  # [ADD] store 타입일 때만 www/{APP_NAME} → /app/www 마운트 (읽기전용 권장)
  DOCKER_RUN_ARGS+=( -v "$WWW_DIR_HOST":/app/www:ro )
  echo "[INFO] Static mount: $WWW_DIR_HOST -> /app/www (ro)" | tee -a "$LOG_FILE"
fi

docker run "${DOCKER_RUN_ARGS[@]}" "$APP_NAME-app" >> "$LOG_FILE" 2>&1
RUN_STATUS=$?

if [ $RUN_STATUS -eq 0 ]; then
  echo "[$DATE] [SUCCESS] $APP_NAME running on port $PORT" | tee -a "$LOG_FILE"
else
  echo "[$DATE] [ERROR] Failed to run $APP_NAME container" | tee -a "$LOG_FILE"
  exit 1
fi

#-----------------------------
# Health Check
#-----------------------------
if $IN_DOCKER; then
  HEALTH_CHECK_URL="http://$APP_NAME:8080/actuator/health"
else
  HEALTH_CHECK_URL="http://localhost:$PORT/actuator/health"
fi
echo "🩺 Health checking $HEALTH_CHECK_URL ..."
RETRY_COUNT=0
MAX_RETRIES=12

until [ "$(curl -s -o /dev/null -w '%{http_code}' "$HEALTH_CHECK_URL")" == "200" ]; do
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "❌ [$DATE] [ERROR] Health check failed for $APP_NAME after ${MAX_RETRIES} attempts." | tee -a "$LOG_FILE"
    # docker rm -f "$APP_NAME"  # 필요 시 활성화
    exit 1
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  echo "   - (Attempt ${RETRY_COUNT}/${MAX_RETRIES}) Waiting for application to be ready..."
  sleep 5
done

echo "✅ [$DATE] [SUCCESS] Health check passed for $APP_NAME." | tee -a "$LOG_FILE"