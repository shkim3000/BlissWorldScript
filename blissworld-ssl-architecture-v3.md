# BlissWorld SSL Architecture v3

### (Nginx / Certbot / Admin Container Responsibility Separation)

**Version:** 2025.12\
**Author:** ChatGPT × 친구\
**Purpose:** 안정적이고 유지보수 가능한 SSL 자동갱신 구조 정립

------------------------------------------------------------------------

# 1. 개요

BlissWorld 시스템은 여러 가맹점(Shop / Store / PosSim / VanSim /
Admin)을 단일 EC2 노드 내에서 Docker Compose 기반으로 운영한다.\
SSL 자동 갱신 실패는 곧 서비스 전체 중단으로 직결되므로, Nginx--Certbot
구조는 절대적으로 안정적이어야 한다.

이 문서는 기존 SSL/ACME 구조(BW-ECN-2025-SSL-001)를 기반으로,\
**admin 컨테이너와 nginx 컨테이너의 역할을 명확하게 분리한 v3
아키텍처**를 정의한다.

------------------------------------------------------------------------

# 2. 기존 문제점 (Why v3?)

기존 구조에서는 다음과 같은 문제가 존재했다:

### ❌ (1) nginx 버전을 Ubuntu 패치 단위까지 고정

→ 특정 버전이 repo에서 제거되면 docker build 실패\
→ reboot 후 admin 컨테이너 미기동 / SSL 관리 불능

### ❌ (2) admin 컨테이너와 nginx 컨테이너 모두 certbot·nginx를 설치

→ 책임 중복\
→ 관리 포인트 증가\
→ renewal 프로세스 충돌 위험

### ❌ (3) SSL 파일, renewal conf, nginx conf의 관리 경계 불명확

→ 도메인 추가/삭제 시 실수 위험\
→ ACME 경로 설정 누락 가능성

### ❌ (4) ECN-2025-SSL-001에서 제안된 HTTPS ACME 처리 방식과 실제 운영 구조의 괴리

→ 443 challenge 실패 시 renew 전체 실패

------------------------------------------------------------------------

# 3. BlissWorld SSL Architecture v3 -- 핵심 개념

## 🧠 목표

1.  nginx는 오직 **reverse proxy + certbot 실행 + challenge 서빙**만
    담당\
2.  admin은 **모든 설정 생성/관리 및 초기 인증 orchestration** 담당\
3.  host cron이 certbot renew를 담당\
4.  nginx는 **버전 고정하지 않음** (또는 major/minor까지만 고정)\
5.  `/etc/nginx`, `/etc/letsencrypt` 파일은 host 디렉토리로 유지 →
    컨테이너 재배포와 무관

------------------------------------------------------------------------

# 4. 역할 분리 (Responsibility Matrix)

  -----------------------------------------------------------------------
  기능        admin 컨테이너                nginx 컨테이너
  ----------- ----------------------------- -----------------------------
  nginx 실행  ❌ 없음                       ⭕ 있음

  nginx 설치  ❌ 제거                       ⭕ 유지

  certbot     ❌ 제거                       ⭕ 유지
  설치                                      

  certbot     ⭕ 최초 발급 (docker exec     ⭕ 갱신(renew)
  실행        nginx certbot)                

  nginx conf  ⭕ admin이 생성               ❌ 없음
  생성                                      

  SSL 파일    ⭕ 일부 관리                  ⭕ 공유 디렉토리
  관리        (/etc/letsencrypt)            

  ACME        ❌ 없음                       ⭕ nginx
  webroot                                   
  제공                                      

  renewal     ❌ 없음                       ❌ 없음 (host에서 실행)
  cron 실행                                 

  host cron   ⭕ admin 스크립트에서 설정    ❌
  실행                                      
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 5. 디렉토리 / Volume 구조

    /etc/nginx              ← host 디렉토리
    /etc/letsencrypt        ← host 디렉토리
    /var/www/certbot        ← docker volume

모든 컨테이너는 다음과 같이 공유한다:

### admin:

    /etc/nginx:/etc/nginx
    /etc/letsencrypt:/etc/letsencrypt

### nginx:

    /etc/nginx:/etc/nginx
    /etc/letsencrypt:/etc/letsencrypt
    certbot-webroot:/var/www/certbot

------------------------------------------------------------------------

# 6. Webroot / Renewal / ACME 구조

### ECN-2025-SSL-001 준수 사항:

-   모든 renewal conf → 단일 webroot로 통일
-   80 / 443 모두 ACME challenge 처리
-   snippet 파일로 라우팅 구성
-   renew 후 nginx reload 필수

### v3에서 구현

#### `snippets/letsencrypt.conf` 예시:

``` nginx
location ^~ /.well-known/acme-challenge/ {
    root /var/www/certbot;
}
```

#### server 블록 규칙

HTTP(80), HTTPS(443) 모두 다음 라인 포함:

    include /etc/nginx/snippets/letsencrypt.conf;

#### renewal conf 예시

    webroot_path = /var/www/certbot

------------------------------------------------------------------------

# 7. Dockerfile 구조

## 7-1. Dockerfile.admin (정상화 버전)

``` dockerfile
FROM eclipse-temurin:21-jdk-jammy
ENV DEBIAN_FRONTEND=noninteractive

ARG DOCKER_GID

RUN groupadd --gid 1001 appgroup &&     groupadd --gid "${DOCKER_GID}" docker &&     useradd --uid 1001 --gid 1001 --groups docker --shell /bin/bash --create-home appuser

RUN apt-get update &&     apt-get install -y       dnsutils ca-certificates curl gnupg lsb-release sudo unzip       --no-install-recommends &&     rm -rf /var/lib/apt/lists/*

RUN mkdir -m 0755 -p /etc/apt/keyrings &&     curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg &&     echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable"         > /etc/apt/sources.list.d/docker.list &&     apt-get update &&     apt-get install -y docker-ce-cli --no-install-recommends &&     rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY app.jar .

RUN ln -s /app/scripts /scripts
RUN chown -R appuser:appgroup /app

USER appuser
CMD ["java", "-jar", "app.jar"]
```

------------------------------------------------------------------------

## 7-2. Dockerfile.nginx (정상화 버전)

``` dockerfile
FROM nginx:stable

RUN apt-get update &&     apt-get install -y certbot python3-certbot-nginx &&     rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/certbot
```

------------------------------------------------------------------------

# 8. Host Cron (자동 갱신)

호스트에서:

    sudo crontab -e

추가:

    0 3,15 * * * docker exec nginx certbot renew --quiet && docker exec nginx nginx -s reload

------------------------------------------------------------------------

# 9. Deploy 순서

1.  admin에서 설정 생성 (shop, store, possim 등)
2.  admin이 생성한 Nginx 설정이 `/etc/nginx`에 적용됨
3.  Nginx 컨테이너 시작 → conf load
4.  새로운 도메인 최초 SSL 발급:

```{=html}
<!-- -->
```
    docker exec nginx certbot certonly --webroot -w /var/www/certbot     -d store1.bliss13world.org --email admin@blissworld.org --agree-tos

5.  Host에서 cron 자동 갱신 시작

------------------------------------------------------------------------

# 10. 결론: v3 아키텍처 안정성 분석

### ✔ ECN 요구사항 100% 충족

### ✔ nginx 버전 고정 문제 제거

### ✔ admin/nginx 역할 완전 분리

### ✔ certbot 갱신 실패 확률 최소화

### ✔ 운영 난이도↓, 복구 가능성↑

### ✔ 재부팅/재배포에 영향 없는 구조 확보

**→ BlissWorld에서 가장 안전하고 유지보수 가능한 구조**

------------------------------------------------------------------------

# 11. 부록 -- 위험 포인트 점검 체크리스트

-   [ ] `/var/www/certbot` webroot 통일\
-   [ ] 80/443에 snippet include 적용\
-   [ ] `/etc/nginx` 및 `/etc/letsencrypt` host 디렉토리로 유지\
-   [ ] admin은 certbot 설치하지 않음\
-   [ ] nginx 컨테이너가 certbot + nginx 단일 책임\
-   [ ] cron 호출 대상은 nginx 컨테이너\
-   [ ] 배포 전 `docker exec nginx nginx -t`\
-   [ ] `docker exec nginx certbot renew --dry-run`
