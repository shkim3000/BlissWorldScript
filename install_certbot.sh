#!/bin/bash
# Ubuntu 24.04 기준 Certbot 설치 스크립트

echo "🔧 Snap 기반 Certbot 설치를 시작합니다..."

# Snap core 설치 및 갱신
sudo snap install core
sudo snap refresh core

# Certbot 설치
sudo snap install --classic certbot

# /usr/bin/certbot 심볼릭 링크 생성
sudo ln -s /snap/bin/certbot /usr/bin/certbot

# 버전 확인
certbot --version

echo "✅ Certbot 설치 완료! 이제 certbot 명령을 사용할 수 있습니다."
