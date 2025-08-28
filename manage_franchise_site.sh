#!/bin/bash
#
# BlissWorld 가맹점 컨테이너 중앙 관리 스크립트
#
# 이 스크립트는 BlissWorldAdmin 컨테이너 내부에서 실행되며,
# 호스트의 Docker 소켓을 사용하여 다른 가맹점 컨테이너를 제어합니다.
#
# 사용법: ./manage_franchise_site.sh <action> [options]
#
# Actions:
#   start <site_name> <image_name> <port> <profile> <site_type>
#   stop <site_name>
#   remove <site_name> <domain>
#   restart-with-state <site_name> <new_state>
#

set -e

# --- 경로 및 기본 변수 설정 ---
# 이 스크립트는 admin 컨테이너 내부에서 실행되도록 설계되었습니다.
# HOST_PROJECT_PATH는 docker-compose.yml에서 환경 변수로 주입받습니다.
HOST_PROJECT_PATH="${HOST_PROJECT_PATH:-/home/ubuntu/blissworld}"
ADMIN_BASE="/app"
SCRIPTS_DIR="$ADMIN_BASE/scripts"

ACTION=$1
SITE_NAME=$2

if [ -z "$ACTION" ] || [ -z "$SITE_NAME" ]; then
  echo "❌ Error: Action and site_name are required."
  echo "Usage: $0 <action> <site_name> [options...]"
  exit 1
fi

CONTAINER_NAME="$SITE_NAME"

# --- 함수 정의 ---

fn_start() {
  local IMAGE_NAME=${3:?Image name is required}
  local PORT=${4:?Port is required}
  local PROFILE=${5:-prod}
  local SITE_TYPE=${6:-store}
  echo "🚀 Starting container '$CONTAINER_NAME' with standard options..."
  echo "   - Image: $IMAGE_NAME, Port: $PORT, Profile: $PROFILE, Type: $SITE_TYPE"

  # 기존 컨테이너가 있다면 강제 제거
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

  # 호스트에 디렉토리 생성 (admin 컨테이너를 통해)
  mkdir -p "$ADMIN_BASE/logs/$SITE_NAME"
  mkdir -p "$ADMIN_BASE/data/$SITE_NAME"

  # [개선] docker_build_run.sh와 동일한 표준 옵션을 사용
  DOCKER_RUN_ARGS=(
    -d
    --restart unless-stopped
    --name "$CONTAINER_NAME"
    --network "blissworld-net"
    -p "$PORT:8080"
    -e "SPRING_PROFILES_ACTIVE=$PROFILE"
    -e "GLOBAL_START_STATE=setup"
    --memory="256m"
    --cpus="0.5"
    -v "$HOST_PROJECT_PATH/logs/$SITE_NAME":/app/logs
    -v "$HOST_PROJECT_PATH/data/$SITE_NAME":/app/data
    --label "site.type=$SITE_TYPE"
  )

  # store 타입일 때만 Firebase 키를 읽기 전용으로 마운트
  if [ "$SITE_TYPE" = "store" ]; then
    if [ -f "$ADMIN_BASE/keys/blissworld-firebase-key.json" ]; then
      DOCKER_RUN_ARGS+=( -v "$HOST_PROJECT_PATH/keys/blissworld-firebase-key.json":/app/keys/blissworld-firebase-key.json:ro )
    else
      echo "⚠️  Warning: Firebase key not found for store type. Skipping mount."
    fi
  fi

  docker run "${DOCKER_RUN_ARGS[@]}" "$IMAGE_NAME"
  echo "✅ Container '$CONTAINER_NAME' started successfully."
}

fn_stop() {
  echo "🛑 Stopping container '$CONTAINER_NAME'..."
  if [ "$(docker ps -q -f name=$CONTAINER_NAME)" ]; then
      docker stop $CONTAINER_NAME
      echo "✅ Container stopped."
  else
      echo "ℹ️ Container '$CONTAINER_NAME' is not running."
  fi
}

fn_remove() {
  local DOMAIN=${3:?Domain is required for remove action}
  echo "🗑️ Delegating removal for '$SITE_NAME' to the master script..."
  # [핵심 개선] 복잡한 로직을 직접 수행하는 대신, 표준 제거 스크립트에 작업을 위임
  bash "$SCRIPTS_DIR/remove_franchise_site.sh" "$DOMAIN" "$CONTAINER_NAME"
  echo "🎉 Removal process for site '$SITE_NAME' completed."
}

fn_restart_with_state() {
  local NEW_STATE=${3:?New state is required}

  echo "🔄 Restarting container '$CONTAINER_NAME' with new state: '$NEW_STATE'..."
  if ! docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
    echo "❌ Error: Container '$CONTAINER_NAME' not found."
    exit 1
  fi

  # [개선] update_franchise_site.sh와 동일한 방식으로 기존 설정을 정확히 추출
  local IMAGE_NAME=$(docker inspect --format='{{.Config.Image}}' "$CONTAINER_NAME")
  local PORT=$(docker inspect --format='{{(index (index .HostConfig.PortBindings "8080/tcp") 0).HostPort}}' "$CONTAINER_NAME")
  local PROFILE=$(docker inspect --format='{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' "$CONTAINER_NAME" | grep '^SPRING_PROFILES_ACTIVE=' | cut -d'=' -f2)
  local NETWORK_NAME=$(docker inspect --format='{{range $net, $v := .NetworkSettings.Networks}}{{$net}}{{end}}' "$CONTAINER_NAME")
  # [수정] 컨테이너의 라벨에서 직접 SITE_TYPE과 DOMAIN을 읽어옵니다.
  local DOMAIN=$(docker inspect --format='{{index .Config.Labels "site.domain"}}' "$CONTAINER_NAME")
  local SITE_TYPE=$(docker inspect --format='{{index .Config.Labels "site.type"}}' "$CONTAINER_NAME")
  PROFILE=${PROFILE:-prod}

  if [ -z "$SITE_TYPE" ]; then
      echo "⚠️  Warning: 'site.type' label not found. Defaulting to 'store'. This may be incorrect for older containers."
      SITE_TYPE="store"
  fi

  if [ -z "$DOMAIN" ] && [ "$SITE_TYPE" == "store" ]; then
      echo "❌ Error: 'site.domain' label not found for a 'store' type container. Cannot restart with www mount."
      exit 
  fi

  docker rm -f "$CONTAINER_NAME"

  DOCKER_RUN_ARGS=(
    -d
    --restart unless-stopped
    --name "$CONTAINER_NAME"
    --network "$NETWORK_NAME"
    -p "$PORT:8080"
    -e "SPRING_PROFILES_ACTIVE=$PROFILE"
    -e "GLOBAL_START_STATE=$NEW_STATE" # 새로운 상태 적용
    --memory="256m"
    --cpus="0.5"
    -v "$HOST_PROJECT_PATH/logs/$SITE_NAME":/app/logs
    -v "$HOST_PROJECT_PATH/data/$SITE_NAME":/app/data
    --label "site.type=$SITE_TYPE"
    --label "site.domain=$DOMAIN"
  )

  if [ "$SITE_TYPE" = "store" ]; then
    if [ -f "$ADMIN_BASE/keys/blissworld-firebase-key.json" ]; then
      DOCKER_RUN_ARGS+=( -v "$HOST_PROJECT_PATH/keys/blissworld-firebase-key.json":/app/keys/blissworld-firebase-key.json:ro )
    fi

    if [ -d "$ADMIN_BASE/www/$DOMAIN" ]; then
      DOCKER_RUN_ARGS+=( -v "$HOST_PROJECT_PATH/www/$DOMAIN":/app/www:ro )
    else
      echo "⚠️  Warning: Static directory $ADMIN_BASE/www/$DOMAIN not found. Skipping www mount."
    fi
  fi

  docker run "${DOCKER_RUN_ARGS[@]}" "$IMAGE_NAME"
  echo "✅ Container '$CONTAINER_NAME' restarted in '$NEW_STATE' mode."
}

# --- 메인 실행 로직 ---
case "$ACTION" in
  start)
    if [ -z "$6" ]; then echo "Usage: $0 start <site_name> <image_name> <port> <profile> <site_type>"; exit 1; fi
    fn_start "$@" ;;
  stop) fn_stop ;;
  remove)
    if [ -z "$3" ]; then echo "Usage: $0 remove <site_name> <domain>"; exit 1; fi
    fn_remove "$@" ;;
  restart-with-state)
    fn_restart_with_state "$@" ;;
  *)
    echo "❌ Error: Unknown action '$ACTION'"
    exit 1
    ;;
esac
