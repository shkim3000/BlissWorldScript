# BlissWorld SSL Architecture v3 — 전체 리팩토링 작업 Checklist

본 문서는 BlissWorld SSL v3 아키텍처 리팩토링을 위한 전체 업무 절차를 Top‑Down 방식으로 정리한 체크리스트입니다. 운영 환경(ECS + Docker Compose + Admin/NGINX + Certbot)을 기준으로 하며, 모든 설정은 v3 문서(Responsibility Separation) 기반으로 구성됩니다.

---

## 1. 사전 준비 (Pre‑Check)

- 시스템 설정 확인

&#x20;[o] nginx 컨테이너 이름이 nginx로 고정되어 있는가

&#x20;[o] admin 컨테이너가 host /etc/nginx, /etc/letsencrypt에 접근 가능한가

&#x20;[o] host에서 docker exec nginx ... 실행 권한 확인



&#x20;현재 SSL 디렉토리 백업:

  [o] /etc/nginx 백업

    sudo cp -r /etc/nginx /etc/nginx.backup\_v3\_\$(date +%Y%m%d)

  [o] /etc/letsencrypt 백업

    sudo cp -r /etc/letsencrypt /etc/letsencrypt.backup\_v3\_\$(date +%Y%m%d)

  --------------------

  ubuntu\@ip-172-31-15-171:\~/blissworld/scripts\$ ls -l /etc | grep backup&#x20;

  drwxr-xr-x 9 root root 4096 Dec 1 22:44 letsencrypt.backup\_v3\_20251201&#x20;

  drwxr-xr-x 8 root root 4096 Dec 1 22:43 nginx.backup\_v3\_20251201&#x20;

  -----------------

## 2. 컨테이너 구조 정리

### 2-1. Admin 컨테이너

- [o] Dockerfile.admin에서 nginx / certbot 완전 제거

  &#x20;[o] DOCKER\_GID 반영된 상태로 docker socket 정상 mount

  &#x20;[o] admin 내부 /app/scripts 링크 정상 생성



**2-2. Nginx 컨테이너**

[o] nginx\:stable 또는 LTS 정상 적용됨

[o] certbot + python3-certbot-nginx 설치됨&#x20;

[o] /var/www/certbot 디렉토리 존재
[o] volume mount 정상 (/var/www/certbot)
[o] /etc/nginx 및 /etc/letsencrypt 마운트 정상



\## 3. Nginx 설정 구조 확립

📁 각 도메인 conf 공통 규칙

[o] HTTP(80) server 블록에 snippet include

[o] HTTPS(443) server 블록에도 동일 snippet include

[o] default server에도 snippet 포함

[보류] 모든 conf에 syntax 오류 없는지 테스트

[보류] docker exec nginx nginx -t

### 3-1. snippets 구성

[o] snippets/letsencrypt.conf 존재

```
location ^~ /.well-known/acme-challenge/ {
    root /usr/share/nginx/html;
}
```



4\. ACME Webroot 통일

[o] 모든 certbot certonly/renew 설정에서 webroot 통일 — 경로: /usr/share/nginx/html

[o] /etc/letsencrypt/renewal/\*.conf 내부 webroot\_path 확인 (webroot\_path = /usr/share/nginx/html)

[o] 기존 certbot 설정과의 충돌 제거 (과거 /var/www/certbot 기반 설정 치환 완료)

[보류] v3로 재배포 후 모든 renewal conf에서 동일 webroot 적용 여부 최종 검증



\## 5. Admin 책임 영역 정리

📁 Admin 컨테이너가 전담해야 하는 역할

[o] Nginx 설정 파일(/etc/nginx/sites-available/\*.conf) 자동 생성 책임

[o] SSL 인증서 발급/갱신을 위한 certbot 실행 트리거 책임

[o] SSL 적용 이후 HTTPS 서버 블록 구성 책임

[o] 프랜차이즈별 도메인/포트/타입(store/api) 기반 설정 템플릿 생성 책임

[o] Docker DNS 기반 upstream 설정 (resolver 127.0.0.11) 유지 책임

[o] admin 내부에서 docker.sock를 통한 shop/store 컨테이너 제어 책임

[o] SSL 설정 반영 직전 nginx -t VALIDATION 수행 책임 (setup\_admin\_site.sh 포함)

[보류] v3 전환 이후 모든 프랜차이즈 사이트를 재배포하며 admin 책임 영역 전수 검증



## **6. 최초 SSL 발급 절차 고도화**

📁 **초기 인증 발급 과정을 v3 표준에 맞게 통일**

[o] 모든 도메인은 최초 생성 시 HTTP-only conf 로 80 포트 서버 블록만 활성화\
\- HTTPS(443) 설정은 certbot 성공 이후에만 생성됨\
\- 인증 실패 시 HTTPS conf 생성 금지 → 구조 안정성 확보

[o] DNS → 서버 IP(EC2 public IP) 매칭 여부 선확인\
\- certbot 실행 전 nslookup + public IP 비교\
\- mismatch 시 즉시 fail → 불필요한 rate-limit 방지

[o] certbot certonly + webroot 방식으로 통일\
사용 명령:

```
certbot certonly --webroot -w /usr/share/nginx/html -d <DOMAIN> --non-interactive --agree-tos --quiet

```

\- nginx 플러그인(`--nginx`) 완전 제거\
\- webroot fallback + HTTPS fallback 모두 지원됨

[o] certbot 실행 중 로그는 /app/logs/certbot\_output.log 에 기록\
\- certonly 출력은 tee 대신 tmp 파일 → pipefail 문제 해결\
\- 실패 시 즉시 exit 1

[o] 성공/스킵 상태에 따라 SSL conf 자동 생성\
\- success → 신규 SSL(443) conf 생성\
\- skipped → 기존 인증서 유지하되 v3 템플릿으로 conf 재생성\
\- failed → HTTPS conf 생성 금지

[o] SSL conf 생성 후 nginx -t → reload 순서 철저히 유지

```
docker exec nginx nginx -t
docker exec nginx nginx -s reload

```

[o] 대용량 업로드가 필요한 admin(api) 서비스는 300초 타임아웃 및 100MB upload size 자동 반영\
\- 서비스별 custom behavior 를 v3 템플릿에서 자동 반영

[보류] 모든 도메인에 대해 v3 초기 발급 플로우 재현 테스트(dry-run 포함)


## 7. Host Cron 자동 갱신 구성

📁 **Certbot 자동 갱신(renew) 작업을 Host 수준에서 안정적으로 수행**

[o] cron.daily 또는 crontab -e 기반의 갱신 스케줄 관리 — Host(EC2)에서 실행

[o] Nginx 컨테이너 내부에서 certbot renew 실행하도록 docker exec 방식 통일
예시:
```
0 3,15 * * * docker exec nginx certbot renew --quiet && docker exec nginx nginx -s reload
```

[o] renew 수행 전 webroot(/usr/share/nginx/html) 접근 정상 여부 확인 — snippet 구조로 자동 처리됨

[o] 갱신 성공 시 Nginx reload 자동 수행 → 최신 인증서 반영

[o] 모든 renewal 로그는 /etc/letsencrypt/renewal.log 또는 Host syslog에서 추적 가능

[o] admin 컨테이너는 cron을 절대 실행하지 않으며, cron 책임은 Host 단일화

[보류] v3 기준으로 모든 도메인의 certbot renew → nginx reload end-to-end 시뮬레이션 테스트

## 8. 테스트 절차 정리 (ACME → Nginx → Renewal End-to-End)

📁 **v3 구조가 실제로 정상 동작하는지 end-to-end로 검증하는 절차**

### 8-1. ACME Webroot 및 인증 경로 테스트
[o] nginx 컨테이너에서 ACME 인증 경로 직접 확인
```
docker exec nginx ls -l /usr/share/nginx/html/.well-known/acme-challenge/
```

[o] HTTP 인증 경로 테스트 (Host에서):
```
curl -I http://<DOMAIN>/.well-known/acme-challenge/test
```
→ HTTP 200 또는 404 응답이어야 하며, **HTTP 500/502/503이면 실패**

[o] HTTPS fallback 인증 경로 테스트:
```
curl -Ik https://<DOMAIN>/.well-known/acme-challenge/test
```
→ snippet이 HTTPS에도 적용되는지 확인 (v3 핵심 변경점)

### 8-2. certbot --dry-run 테스트
[o] 인증서 갱신 모의 테스트:
```
docker exec nginx certbot renew --dry-run
```
→ 성공 시 "**Congratulations, all renewals succeeded**" 출력
→ 실패 시 webroot/snippet/Nginx 설정 불일치

### 8-3. Nginx 문법 및 동작 검증
[o] Nginx conf 문법 검사:
```
docker exec nginx nginx -t
```

[o] conf reload 테스트:
```
docker exec nginx nginx -s reload
```
→ 오류 없이 종료되면 정상 적용

### 8-4. 실제 HTTPS 응답 테스트
[o] Host 또는 외부에서 다음 확인:
```
curl -I https://<DOMAIN>
```
확인 포인트:
- `HTTP/2 200` 또는 `HTTP/1.1 200` 정상 응답
- `server: nginx` 표시
- 인증서 유효(valid) 여부

### 8-5. Renewal 실제 주기 테스트 (수동 시뮬레이션)
[o] renewal 강제 실행
```
docker exec nginx certbot renew
```

[o] renewal 후 Nginx reload 자동 수행 여부 확인 (cron 방식 시뮬레이션)
→ `/var/log/syslog` 또는 cron 로그에서 확인

### 8-6. 도메인별 End-to-End 점검 체크리스트
- [ ] HTTP 인증 경로 정상 작동
- [ ] HTTPS 인증 경로 정상 작동
- [ ] certbot dry-run 성공
- [ ] nginx -t 성공
- [ ] nginx reload 성공
- [ ] HTTPS 응답 정상(200)
- [ ] 인증서 갱신 성공
- [ ] 갱신 후 nginx 자동 reload 성공
