#!/bin/bash
# Docker 설치 스크립트 (Ubuntu 24.04 기준)

# 1. 기본 패키지 설치
sudo apt update
sudo apt install -y ca-certificates curl gnupg

# 2. GPG 키 디렉토리 생성 및 등록
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 3. Docker 저장소 등록
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Docker 설치
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# 5. 현재 사용자를 docker 그룹에 추가
sudo usermod -aG docker $USER

echo "✅ Docker 설치 완료! 재접속 후 'docker --version'으로 확인하세요."
