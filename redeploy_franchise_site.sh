#!/bin/bash

# ---------------------------------------------
# BlissWorld 일반 가맹점(site) 재배포 스크립트
# ---------------------------------------------
# - 앱 컨테이너 생성
# - 정적 파일 구조 생성
# - Nginx conf 및 Certbot SSL 처리 (admin 전용)
# ---------------------------------------------
# 사용법:
# ./redeploy_franchise_site.sh <franchise_name> <port> <jar_file> <domain> <site_type> [profile] [--staging]

set -e

# Check for required arguments
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
  echo "❌ 오류: 필수 인자가 누락되었습니다."
  echo "사용법: $0 <franchise_name> <port> <jar_file> <domain> <site_type> [profile] [--staging]"
  exit 1
fi

FRANCHISE_NAME=$1
PORT=$2
JAR_FILE=$3
DOMAIN=$4
SITE_TYPE=$5
PROFILE=${6:-prod}
STAGING_FLAG=""

for arg in "$@"; do
    if [ "$arg" == "--staging" ]; then
        STAGING_FLAG="--staging"
        echo "ℹ️  Staging 모드 활성화됨 (Let's Encrypt 테스트 서버)"
    fi
done

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
ADMIN_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"

NETWORK_NAME="blissworld-net"
if ! docker network ls | grep -q "$NETWORK_NAME"; then
    echo "📡 Docker 네트워크 '$NETWORK_NAME'가 없으므로 생성합니다..."
    docker network create "$NETWORK_NAME"
fi


# (1) 컨테이너 빌드 및 실행
# [수정] docker_build_run.sh에 DOMAIN 인자를 전달하고, 표준 경로를 사용합니다.
"$ADMIN_BASE/scripts/docker_build_run.sh" "$FRANCHISE_NAME" "$PORT" "$JAR_FILE" "$PROFILE" "$NETWORK_NAME" "$SITE_TYPE" "$DOMAIN"

# (2) 정적 디렉토리 구성 (store일 경우)
"$ADMIN_BASE/scripts/setup_franchise_site.sh" "$DOMAIN" "$SITE_TYPE" index.html

# (3) Nginx conf 및 Certbot 인증서 발급
# [수정] setup_admin_site.sh는 컨테이너 내부에서 실행되도록 설계되었으므로, docker exec를 통해 실행해야 하네.
# 이렇게 해야 DNS 확인, 다른 컨테이너 제어 등 모든 기능이 정상적으로 동작하지.
echo "🔐 Nginx 설정 및 SSL 인증서 발급을 위해 admin 컨테이너 내부에서 setup_admin_site.sh를 실행합니다..."
# [수정] admin 컨테이너 내부의 스크립트 경로를 /app/scripts로 변경합니다.
docker exec -u root admin /app/scripts/setup_admin_site.sh "$DOMAIN" "$PORT" "$SITE_TYPE" index.html "$STAGING_FLAG"

# (4) 정적 ZIP 파일 자동 배포 처리 (store 유형만 대상)
if [ "$SITE_TYPE" == "store" ]; then
  echo "📦 정적 ZIP 배포 처리 시작..."

  # [수정] Java 소스 및 다른 스크립트와의 일관성을 위해 경로를 통일합니다.
  UPLOADS_DIR="$ADMIN_BASE/scripts/uploads"
  ORIG_ZIP_PATH=$(find "$UPLOADS_DIR" -maxdepth 1 -type f -name '*.zip' | head -n 1)
  STD_ZIP_PATH="$UPLOADS_DIR/${FRANCHISE_NAME}.zip"

  if [ -f "$ORIG_ZIP_PATH" ]; then
    # 이름이 다르면 표준 명칭으로 변경
    if [ "$ORIG_ZIP_PATH" != "$STD_ZIP_PATH" ]; then
      echo "   - ZIP 파일명을 '${FRANCHISE_NAME}.zip'으로 변경합니다."
      mv "$ORIG_ZIP_PATH" "$STD_ZIP_PATH"
    fi

    echo "   - 압축 해제를 admin 컨테이너에서 수행합니다..."
    # [수정] admin 컨테이너 내부의 스크립트 경로를 /app/scripts로 변경합니다.
    docker exec -u root admin /app/scripts/unzip_static.sh "$FRANCHISE_NAME" "$DOMAIN"
  else
    echo "⚠️  uploads/ 디렉토리에 ZIP 파일이 존재하지 않습니다. 압축 해제를 건너뜁니다."
  fi
fi

echo "✅ 전체 재배포 완료!"
echo "   - 도메인: $DOMAIN"
echo "   - 유형: $SITE_TYPE"
echo "   - 포트: $PORT"
echo "   - 컨테이너: $FRANCHISE_NAME"
