#!/bin/bash

# ----------------------------------------------------
# BlissWorld - 정적 파일 압축 해제 및 배포 스크립트
# ----------------------------------------------------
# 역할:
# 1. /scripts/uploads/ 에 있는 ZIP 파일을
# 2. /app/www/{도메인}/ 경로에 압축 해제
# 3. 원본 ZIP 파일 삭제
#
# 주의: 이 스크립트는 root 권한으로 실행되어야 합니다.
# (예: docker exec -u root ...)
# ----------------------------------------------------

# 오류 발생 시 즉시 중단
set -e

# --- 1. 입력 인자 검증 ---
FRANCHISE_NAME=$1
DOMAIN=$2

if [ -z "$FRANCHISE_NAME" ] || [ -z "$DOMAIN" ]; then
  echo "❌ 오류: 필수 인자가 누락되었습니다."
  echo "사용법: $0 <가맹점_이름> <도메인>"
  echo "예시:   $0 store1 store1.blissworld.org"
  exit 1
fi

# --- 2. 경로 설정 ---
UPLOADS_DIR="/scripts/uploads"
WWW_DIR="/app/www"
SOURCE_ZIP="$UPLOADS_DIR/$FRANCHISE_NAME.zip"
DEST_DIR="$WWW_DIR/$DOMAIN"

echo "🚀 정적 파일 배포를 시작합니다..."
echo "   - 소스 파일: $SOURCE_ZIP"
echo "   - 대상 디렉토리: $DEST_DIR"

# --- 3. 소스 파일 존재 여부 확인 ---
if [ ! -f "$SOURCE_ZIP" ]; then
  echo "❌ 오류: 소스 ZIP 파일이 존재하지 않습니다: $SOURCE_ZIP"
  exit 1
fi

# --- 4. 대상 디렉토리 생성 및 압축 해제 ---
echo "📦 파일을 압축 해제하고 원본을 정리합니다..."
mkdir -p "$DEST_DIR"
unzip -o "$SOURCE_ZIP" -d "$DEST_DIR" && rm -f "$SOURCE_ZIP"
# BlissWorldWas가 직접 static data update가능할 수 있도록 appuser 소유로 변경.
chown -R 1001:1001 "$DEST_DIR"

echo "✅ 성공: '$DOMAIN'에 대한 정적 파일 배포가 완료되었습니다."
