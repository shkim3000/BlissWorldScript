#!/bin/bash
#
# 이 스크립트는 새로운 JAR 파일로 이미지를 다시 빌드하고,
# 기존 설정을 유지하며 컨테이너를 재시작하여, 실행 중인 WAS를 안전하게 업데이트하네.
#
# 사용법: ./update_franchise_site.sh <컨테이너_이름> <새_JAR_파일_이름>
#
# 예시 (shop 컨테이너 업데이트):
#   ./update_franchise_site.sh shop BlissWorldShop-0.0.2-SNAPSHOT.jar

set -e # 오류 발생 시 스크립트 중단

# --- 입력 값 검증 ---
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "❌ 오류: 필수 인자가 누락되었습니다."
  echo "사용법: $0 <컨테이너_이름> <새_JAR_파일_이름>"
  exit 1
fi

APP_NAME=$1

# 'admin' 컨테이너는 시스템의 핵심이므로, 이 스크립트로 업데이트하는 것을 명시적으로 금지하네.
# update_admin_site.sh를 사용하도록 안내.
if [ "$APP_NAME" == "admin" ]; then
  echo "🛡️  안전 조치: 'admin' 컨테이너는 이 스크립트로 업데이트할 수 없네."
  echo "   'update_admin_site.sh' 스크립트를 사용하게."
  exit 1
fi

# --- 실행 환경 감지 및 경로 표준화 ---
IN_DOCKER=false
if [ -f /.dockerenv ] || grep -q 'docker' /proc/1/cgroup 2>/dev/null; then
  IN_DOCKER=true
fi

if $IN_DOCKER; then
  # 컨테이너 내부 실행 (API 호출)
  ADMIN_BASE="/app"
else
  # 호스트에서 직접 실행 (sudo)
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
  ADMIN_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

# [수정] 이제 파일 경로 대신 파일 이름을 인자로 받습니다.
# new_jars 디렉토리에서 해당 파일을 찾아 전체 경로를 구성합니다.
NEW_JAR_FILE_NAME=$2
NEW_JARS_DIR="$ADMIN_BASE/new_jars"
NEW_JAR_PATH="$NEW_JARS_DIR/$NEW_JAR_FILE_NAME"

if [ ! -f "$NEW_JAR_PATH" ]; then
    echo "❌ 오류: 새로운 JAR 파일을 찾을 수 없습니다: '$NEW_JAR_PATH'"
    exit 1
fi

# --- 메인 로직 ---
echo "🚀 컨테이너 업데이트를 시작합니다: $APP_NAME"

# 1. 실행 중인 컨테이너와 설정을 확인하네.
if ! docker ps -q -f name=^/${APP_NAME}$ > /dev/null; then
    echo "⚠️  컨테이너 '$APP_NAME'가 실행 중이 아니므로 업데이트할 수 없네. 'redeploy_franchise_site.sh'로 먼저 생성하게."
    exit 1
fi

echo "🔍 실행 중인 컨테이너를 발견했습니다. 설정을 확인합니다..."

# 호스트 포트 추출
HOST_PORT=$(docker inspect --format='{{(index (index .HostConfig.PortBindings "8080/tcp") 0).HostPort}}' "$APP_NAME")
if [ -z "$HOST_PORT" ]; then
    echo "❌ 오류: 컨테이너 '$APP_NAME'의 호스트 포트를 확인할 수 없습니다. 중단합니다."
    exit 1
fi
echo "  - 확인된 호스트 포트: $HOST_PORT"

# Spring 프로파일 추출 (grep과 cut을 사용하는 더 안정적인 방식으로 변경)
# docker inspect의 Go 템플릿에는 substr 함수가 없어서 오류가 발생했네.
SPRING_PROFILE=$(docker inspect --format='{{range .Config.Env}}{{.}}{{"\n"}}{{end}}' "$APP_NAME" | grep '^SPRING_PROFILES_ACTIVE=' | cut -d'=' -f2)
SPRING_PROFILE=${SPRING_PROFILE:-prod} # 없으면 'prod'를 기본값으로 사용
echo "  - 확인된 Spring 프로파일: $SPRING_PROFILE"

# 네트워크 이름 추출
NETWORK_NAME=$(docker inspect --format='{{range $net, $v := .NetworkSettings.Networks}}{{$net}}{{end}}' "$APP_NAME")
if [ -z "$NETWORK_NAME" ]; then
    echo "❌ 오류: 컨테이너 '$APP_NAME'의 네트워크를 확인할 수 없습니다. 중단합니다."
    exit 1
fi
echo "  - 확인된 네트워크: $NETWORK_NAME"

# [수정] 사이트 유형(site.type) 라벨을 컨테이너에서 직접 읽어옵니다.
# 이렇게 하면 API에서 잘못된 유형을 보내더라도 항상 올바른 유형으로 업데이트됩니다.
SITE_TYPE=$(docker inspect --format='{{index .Config.Labels "site.type"}}' "$APP_NAME")
if [ -z "$SITE_TYPE" ]; then
    echo "❌ 오류: 컨테이너 '$APP_NAME'에서 'site.type' 라벨을 찾을 수 없습니다. 이전 버전의 컨테이너일 수 있습니다."
    echo "   업데이트를 중단합니다. 수동으로 확인 후 재배포해주세요."
    exit 1
fi
echo "  - 확인된 사이트 유형 (라벨): $SITE_TYPE"

# [추가] 사이트 도메인(site.domain) 라벨을 컨테이너에서 직접 읽어옵니다.
DOMAIN=$(docker inspect --format='{{index .Config.Labels "site.domain"}}' "$APP_NAME")
if [ -z "$DOMAIN" ]; then
    echo "❌ 오류: 컨테이너 '$APP_NAME'에서 'site.domain' 라벨을 찾을 수 없습니다. 이전 버전의 컨테이너일 수 있습니다."
    echo "   업데이트를 중단합니다. 수동으로 확인 후 재배포해주세요."
    exit 1
fi
echo "  - 확인된 사이트 도메인 (라벨): $DOMAIN"

# JAR 파일 이름만 추출
NEW_JAR_FILE="$NEW_JAR_FILE_NAME"

# 2. 새로운 JAR 파일을 준비하네.
APP_DIR="$ADMIN_BASE/apps/$APP_NAME"
mkdir -p "$APP_DIR"
cp "$NEW_JAR_PATH" "$APP_DIR/$NEW_JAR_FILE"
echo "✅ 새로운 JAR 파일을 '$APP_DIR/$NEW_JAR_FILE' 경로에 복사했습니다."

# 3. 기존의 docker_build_run.sh를 호출하여 업데이트를 수행하네.
echo "🔄 docker_build_run.sh를 호출하여 업데이트를 진행합니다..."

"$ADMIN_BASE/scripts/docker_build_run.sh" "$APP_NAME" "$HOST_PORT" "$NEW_JAR_FILE" "$SPRING_PROFILE" "$NETWORK_NAME" "$SITE_TYPE" "$DOMAIN"

UPDATE_STATUS=$?

if [ $UPDATE_STATUS -eq 0 ]; then
  echo "🎉 컨테이너 '$APP_NAME' 업데이트가 성공적으로 완료되었습니다."
else
  echo "🔥 컨테이너 '$APP_NAME' 업데이트에 실패했습니다."
  exit 1
fi
