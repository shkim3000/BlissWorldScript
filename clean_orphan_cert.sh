#!/bin/bash

# -------------------------------
# 고아(Orphan) 인증서 정리 스크립트
# - 대상: nginx 컨테이너 내부의 Let's Encrypt 디렉토리
# - 기준: /etc/letsencrypt/live에 디렉토리는 존재하지만, `certbot certificates` 목록에는 없는 인증서
# - 동작: 고아 인증서와 관련된 live, archive, renewal 파일을 모두 삭제
# - 사용법: ./clean_orphan_cert.sh [--dry-run]
# -------------------------------
# ** Dry-run 모드 추가: --dry-run 플래그를 추가해서, 실제로 파일을 삭제하지 않고 어떤 인증서가 삭제될지 미리 확인해 볼 수 있는 기능을 넣었네.
# ** 컨테이너 상태 확인: 스크립트 실행 전에 nginx 컨테이너가 정말로 실행 중인지 먼저 확인하도록 했네.
# ** 정확한 디렉토리 스캔: ls 대신 find 명령어를 사용해서 오직 디렉토리만 스캔하도록 수정했네.
# ** 사용자 피드백 개선: 삭제할 인증서가 없을 때 "발견된 고아 인증서가 없습니다"와 같은 명확한 메시지를 보여주도록 개선
# -------------------------------

set -e

NGINX_CONTAINER=nginx       ## nginx 컨테이너 이름, 꼭 확인.
DRY_RUN=false

if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "💧 Dry-run 모드로 실행합니다. 실제 파일은 삭제되지 않습니다."
fi

# nginx 컨테이너가 실행 중인지 확인
if ! docker ps --format '{{.Names}}' | grep -q "^${NGINX_CONTAINER}$"; then
  echo "❌ 오류: nginx 컨테이너('$NGINX_CONTAINER')가 실행 중이 아닙니다."
  exit 1
fi

echo "🔍 nginx 컨테이너 내부에서 orphan 인증서 정리 중..."
echo "📦 대상 컨테이너: $NGINX_CONTAINER"

# [개선] -e 플래그를 사용하여 호스트의 DRY_RUN 변수를 컨테이너 내부 환경으로 안전하게 전달하네.
docker exec -u root -e DRY_RUN="$DRY_RUN" $NGINX_CONTAINER bash -c '
set -e

# 1. certbot 등록된 인증서 목록 수집
mapfile -t VALID_CERTS < <(certbot certificates 2>/dev/null | awk -F": " "/Certificate Name/ {print \$2}" | sort)

# 2. live 디렉토리 기준으로 실제 존재하는 모든 인증서 목록 수집
# ls 대신 find를 사용하여 디렉토리만 정확하게 찾도록 개선
mapfile -t LIVE_CERTS < <(find /etc/letsencrypt/live -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort)

# [개선] 만약 live 디렉토리에 인증서가 하나도 없다면, 사용자에게 알려주고 바로 종료하네.
if [ ${#LIVE_CERTS[@]} -eq 0 ]; then
    echo "✨ /etc/letsencrypt/live 디렉토리에 인증서가 없습니다. 정리할 내용이 없습니다."
    exit 0
fi

# 3. orphan 인증서 식별
echo "🔎 orphan 인증서 목록:"
ORPHAN_FOUND=false
for cert in "${LIVE_CERTS[@]}"; do
  if ! printf "%s\n" "${VALID_CERTS[@]}" | grep -qx "$cert"; then
    ORPHAN_FOUND=true
    echo "  🐀 $cert (삭제 대상)"

    # 4. 삭제 처리
    # [수정] 컨테이너 내부에서 환경 변수를 올바르게 확인하도록 수정했네.
    if [[ "$DRY_RUN" == "false" ]]; then
      echo "  - live, archive, renewal 디렉토리에서 $cert 관련 파일을 삭제합니다..."
      rm -rf "/etc/letsencrypt/live/$cert"
      rm -rf "/etc/letsencrypt/archive/$cert"
      rm -f  "/etc/letsencrypt/renewal/$cert.conf"
      echo "  ✅ 삭제 완료: $cert"
    else
      echo "  (건너뛰기: Dry-run 모드)"
    fi
  fi
done

if [[ "$ORPHAN_FOUND" == "false" ]]; then
    echo "  ✨ 발견된 고아 인증서가 없습니다."
fi

echo "🎉 orphan 인증서 정리 완료."
'
