#!/bin/bash
# 사용법: ./setup_franchise_site.sh <도메인> <사이트_유형: store/api> [<html_파일명>]

set -e

DOMAIN=$1
SITE_TYPE=$2
HTML_FILE=${3:-index.html}

# --- 실행 환경 감지 및 경로 표준화 ---
IN_DOCKER=false
if [ -f /.dockerenv ] || grep -q 'docker' /proc/1/cgroup 2>/dev/null; then
  IN_DOCKER=true
fi

if $IN_DOCKER; then
  # 컨테이너 내부 실행
  ADMIN_BASE="/app"
else
  # 호스트에서 직접 실행
  SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
  ADMIN_BASE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi


STATIC_DIR="$ADMIN_BASE/www/$DOMAIN"
LOG_DIR="$ADMIN_BASE/logs"
HISTORY_CSV="$LOG_DIR/franchise_site_history.csv"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# 입력 검증
if [ -z "$DOMAIN" ] || [ -z "$SITE_TYPE" ]; then
  echo "❌ 오류: 필수 인자 누락"
  echo "사용법: $0 <도메인> <사이트_유형> [<html_파일명>]"
  exit 1
fi

if [ "$SITE_TYPE" != "store" ] && [ "$SITE_TYPE" != "api" ]; then
  echo "❌ 오류: 사이트 유형은 'store' 또는 'api' 여야 함"
  exit 1
fi

# 디렉토리 준비
mkdir -p "$LOG_DIR"
if [ "$SITE_TYPE" == "store" ]; then
  echo "📁 정적 콘텐츠 디렉토리 생성: $STATIC_DIR"
  mkdir -p "$STATIC_DIR"

  # [개선] 디렉토리가 비어있을 경우에만 기본 index.html을 복사하네.
  # 이렇게 하면 API를 통해 업로드된 파일이 실수로 덮어써지는 것을 방지할 수 있지.
  if [ -z "$(ls -A "$STATIC_DIR")" ]; then
    TEMPLATE_FILE="$ADMIN_BASE/scripts/templates/$HTML_FILE"
    if [ -f "$TEMPLATE_FILE" ]; then
      cp "$TEMPLATE_FILE" "$STATIC_DIR/index.html"
      echo "✅ 디렉토리가 비어있어 기본 index.html을 복사했습니다."
    else
      # [수정] 템플릿 파일이 없을 때, 어떤 경로를 확인했는지 명확히 알려주도록 수정
      echo "⚠️  index.html 템플릿이 존재하지 않음: $TEMPLATE_FILE. 빈 디렉토리만 생성됨."
    fi
  else
    echo "ℹ️  정적 콘텐츠가 이미 존재하므로, 기본 파일 복사를 건너뜁니다."
  fi
fi

# 설정 기록 (인증서 발급은 admin이 별도 수행)
echo "$DOMAIN,unknown_port,$SITE_TYPE,$DATE,static_ready" | tee -a "$HISTORY_CSV" > /dev/null

echo "🎉 $DOMAIN 초기 디렉토리 설정 완료 (유형: $SITE_TYPE)"
