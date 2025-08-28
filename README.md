# BlissWorld 가맹점 사이트 운영 가이드 (업데이트 포함)

이 문서는 새로운 가맹점 사이트를 EC2 서버에 추가하고, 필요 시 중지/삭제까지 전 과정을 설명합니다.
스크립트만 순서대로 실행하면 누구나 쉽게 운영할 수 있습니다.

---

## 📁 디렉토리 구조

```
~/blissworld/
├── apps/                 # 가망점별 JAR 파일 저장
│   └── store1/BlissWorldWas-0.0.1-SNAPSHOT.jar
├── www/                  # 가망점별 정적 HTML 저장
│   └── store1.blissworld.org/
├── logs/                 # 실행 로그 및 이력 저장
│   ├── docker_build.log
│   ├── franchise_site_history.csv
│   ├── franchise_site_pause.csv
│   ├── franchise_site_resume.csv
│   └── franchise_site_remove.csv
├── scripts/              # 설치/운영 스크립트 모음
│   ├── docker_build_run.sh
│   ├── setup_franchise_site.sh
│   ├── remove_franchise_site.sh
│   ├── pause_franchise_site.sh
│   ├── resume_franchise_site.sh
│   └── Dockerfile
└── new_jars/				# update시 임시 가맹점 JAR파일 저장.
```
참고1. new_jars directory 왜 필요한가?
update시 userId는 'ubuntu'이다. 그러나 API 'update', 'add'등을 지원하기 위해서는 
./apps, /www, ...등이 "1001"(API사용자)로 지정된어있다(docker_build_run.sh 참고).
따라서 update_container.sh를 수작업(관리자에 의한 긴급복구)으로 진행할 수 있게 만들려면 
신규 jar file을 임시로 넣어두고 작업을 진행하는게 좋다.

---

## 🛍️ 가망점 사이트 추가 순서 (Step-by-Step)

### ✅ STEP 1: JAR 파일 업로드

Eclipse에서 생성한 `*.jar` 파일을 `new_jars/` 디렉토리에 업로드합니다.

예시:

```
apps/store1/BlissWorldWas-0.0.1-SNAPSHOT.jar
```

---

### ✅ STEP 2: Docker 이미지 빌드 및 커테이너 실행

```bash
cd ~/blissworld/scripts

## 관리자 (admin))
sudo ./redeploy_admin_site.sh BlissWorldAdminWas-0.0.2-SNAPSHOT.jar

## 가맹점 (store))
# ./redeploy_site.sh <franchise_name> <port> <jar_file> <domain> <site_type: store/api> [--staging]
sudo ./redeploy_franchise_site.sh store1 8091 my-store.jar store1.blissworld.org store --staging


# 기본 application.properties를 사용하고, 기본 네트워크에 연결
./docker_build_run.sh real-store-001 9001 real-store.jar
```

📌 결과:

* Docker 이미지: `store1-app`
* 커테이너 이름: `store1`
* 연결 포트: EC2 외부 8081 → 내부 8080
* 로그: `logs/docker_build.log`

---

### ✅ STEP 3: Nginx 설정 + HTTPS 인증서 발급

```bash
# 사용법: ./setup_franchise_site.sh <도메인> <포트> <사이트_유형> [<html_파일명>]
#   <도메인>: 사이트의 도메인 이름 (예: store1.blissworld.org)
#   <포트>: 백엔드 WAS 애플리케이션의 포트 번호 (예: 8091)
#   <사이트_유형>: 사이트의 유형. 'store'는 웹 프론트엔드가 있는 경우,
#                 'api'는 순수 백엔드/API 서비스인 경우에 사용합니다.
#   <html_파일명>: [선택 사항] 'store' 유형 사이트의 인덱스 HTML 파일명입니다.
#                  지정하지 않으면 'index.html'이 기본값입니다.
## store 예제)
./setup_franchise_site.sh store1.blissworld.org 8081 store standard.html
## api 예제)
./setup_franchise_site.sh admin.blissworld.org 8082 api
```

📌 결과:

* 정적 루트 생성: `www/store1.blissworld.org/`
* Nginx conf 생성: `/etc/nginx/sites-available/store1.blissworld.org.conf`
* 심볼릭 링크 연결: `/etc/nginx/sites-enabled/`
* Certbot으로 SSL 인증서 발급 → 자동 반영
* 기록 저장: `logs/franchise_site_history.csv`

---
## 🔄 WAS 업데이트

### ✅ `admin` WAS 업데이트 (수동)

`admin` WAS는 시스템의 핵심이므로, 서버 관리자가 직접 접속하여 신중하게 업데이트를 수행합니다.

# update_admin_site.sh (수동: 스크립트)
```bash
  ./update_admin_site.sh BlissWorldAdminWas-0.0.3-SNAPSHOT.jar
```
<< 내용 >>
1.  **새 JAR 파일 업로드:** 새로운 `~/blissworld/new_jars/BlissWorldAdminWas-x.x.x.jar` 파일을 `~/blissworld/apps/admin/` 디렉토리에 업로드하여 기존 파일을 덮어씁니다.
2.  **스크립트 실행:** 아래 명령어를 실행하여 컨테이너를 재시작합니다.

    ```bash
    ./update_admin_site.sh BlissWorldAdminWas-0.0.3-SNAPSHOT.jar
    ```

### ✅ 가맹점(`store`) WAS 업데이트 (자동)

가맹점 WAS는 `BlissWorldManager` 관리자 툴을 통해 원격으로 안전하게 업데이트할 수 있습니다.

---------------------------
## 🖯️ 운영 중단 및 재계

### 🌐 원격 제어 (권장 방식)

가맹점 컨테이너의 시작, 중지, 재시작, 상태 변경 등 모든 생명주기 관리는 **`BlissWorldManager` 관리자 툴**을 통해 원격으로 수행하는 것을 원칙으로 합니다.

관리자 툴은 내부적으로 `BlissWorldAdmin`의 `/api/franchise/ops` API를 호출하며, 최종적으로 각 서버의 중앙 관리 스크립트(`manage_franchise_site.sh`)를 실행하여 Docker 컨테이너를 제어합니다.

### 🛠️ 서버 직접 제어 (수동/긴급 시)

`BlissWorldManager` 또는 `BlissWorldAdmin` 시스템에 문제가 발생했을 경우, 서버 관리자는 SSH로 직접 접속하여 아래 스크립트를 통해 컨테이너를 수동으로 제어할 수 있습니다.

#### ⏸️ 일시 중지

```bash
./pause_franchise_site.sh store1
```

#### ▶️ 재계

```bash
./resume_franchise_site.sh store1
```

---

## 🚹 완전 삭제

`BlissWorldManager`를 통한 원격 삭제를 권장합니다. 부득이하게 수동으로 삭제해야 할 경우, 아래 스크립트를 사용합니다.

```bash
./remove_franchise_site.sh store1.blissworld.org store1
```

📌 삭제 항목:

* Nginx conf 및 심볼릭 링크 제거
* Docker 커테이너 및 이미지 제거
* JAR 파일 및 HTML 포더 삭제
* Certbot 인증서 삭제
* 로그 기록: `logs/franchise_site_remove.csv`

---

## 🔍 확인

* 브라우저 접속:

  ```
  https://store1.blissworld.org
  ```

* 실행 상태 확인:

  ```bash
  docker ps
  ```

* 로그 확인:

  ```
  logs/docker_build.log
  logs/certbot_output.log
  logs/franchise_site_history.csv
  logs/franchise_site_pause.csv
  logs/franchise_site_resume.csv
  logs/franchise_site_remove.csv
  ```

---

## 📌 유의사항

* 도메인은 `*.blissworld.org` 와일드캐릭 A레코드로 EC2 IP에 연결되어야 합니다
* 포트는 중복되지 않게 지정해야 하며, 인증서 발급 제한(하루 5회)도 고려해야 합니다

---

이 가이드는 실제 운영 환경에서 가망점 생성, 중지, 삭제를 모두 자동화할 수 있도록 구성되었습니다.
스크립트만 따라하면 운영이 쉽습니다. 🛠️


#########################
[[docker compose 재 설치]]
# 사용법:
#   ./redeploy_admin_site.sh <franchise_name> <jar_file>
## 관리자 (admin))
기본: 
./redeploy_admin_site.sh BlissWorldAdminWas-0.0.2-SNAPSHOT.jar

## 일반 (api)
#   ./redeploy_franchise_site.sh <franchise_name> <port> <jar_file> <domain> <site_type: store/api> <profile: test/dev/prod> [--staging]
기본:
sudo ./redeploy_franchise_site.sh shop 8083 BlissWorldShop-0.0.1-SNAPSHOT.jar shop.blissworld.org api prod

staging option처리:
sudo ./redeploy_franchise_site.sh shop 8083 BlissWorldShop-0.0.1-SNAPSHOT.jar shop.blissworld.org api prod --staging

## 가맹점 (store)
전처리: store의 경우 apps/storeXY는 동적인 site라서 기존 api용과 달리 setup_admin_site.sh 등에서 관리가 안된다.
    따라서 directory를 만들어 주고 owner를 appuser('1001:1001')로 바꿔줘야한다. 
    반면 www/store1은 해줄 필요없다. setup_franchise_site.sh에서 directory를 appuser가 생성한다.
sudo chown -R 1001:1001 ../apps/store1

기본:
sudo ./redeploy_franchise_site.sh store1 9001 BlissWorldWas-0.0.1-SNAPSHOT.jar store1.blissworld.org store prod

staging option처리:
sudo ./redeploy_franchise_site.sh store1 9001 BlissWorldWas-0.0.1-SNAPSHOT.jar store1.blissworld.org store prod --staging

##################
1. 컨테이너의 실시간 로그 보기
docker logs -f store-001

2. admin-app 이름으로 컨테이너에 돌고있는 확인할 수 있다.
docker image inspect admin-app | grep original.jar.file
```bash
ubuntu@ip-172-31-15-171:~/blissworld/scripts$ docker ps
CONTAINER ID   IMAGE       COMMAND               CREATED          STATUS          PORTS                                         NAMES
b55df6da1cba   admin-app   "java -jar app.jar"   18 seconds ago   Up 17 seconds   0.0.0.0:8082->8080/tcp, [::]:8082->8080/tcp   admin
4dd2dc402a93   shop-app    "java -jar app.jar"   27 hours ago     Up 46 minutes   0.0.0.0:9001->8080/tcp, [::]:9001->8080/tcp   shop
ubuntu@ip-172-31-15-171:~/blissworld/scripts$ docker image inspect admin-app | grep original.jar.file
                "original.jar.file": "BlissWorldAdminWas-0.0.2-SNAPSHOT.jar"
ubuntu@ip-172-31-15-171:~/blissworld/scripts$ 
```

3. docker container에 진입 방법
# 일반 사용자(appuser)로 "admin" container에 접속 (권장)
sudo docker exec -it -u appuser admin /bin/bash
# 관리자(root)로 "admin" container에 접속
sudo docker exec -it admin /bin/bash
# 컨테이너에서 나오기
exit

4. docker network 설정 확인 (ex: blissworld-net)
# 호스트에서
docker network ls
# docker container 내부에서 (ex: admin)
sudo docker exec -it -u appuser admin /bin/bash
docker network ls

[[ 마운트된 www 경로가 admin과 nginx 간에 동기화 확인]]
## admin /app/www .test.txt 생성.
docker exec -it admin bash -c "mkdir -p /app/www/.well-known/acme-challenge && echo hi > /app/www/.well-known/acme-challenge/test.txt"

## ngix에서 test.txt 확인.
docker exec -it nginx cat /usr/share/nginx/html/.well-known/acme-challenge/test.txt

** 'hi' 출력되면 www경로 동기화됨.

5. docker config.Label 확인
# .Config.Labels 전체를 JSON 형태로 출력
```bash
docker inspect --format='{{json .Config.Labels}}' <컨테이너_이름>
```
[[ 메모리 정리 ]]
사용하지 않는 모든 Docker 리소스를 한번에 정리.
sudo docker system prune -a -f


[[ admin 외부 접속 test ]]
curl -v https://admin.blissworld.org

## [[ 고아(Orphan) 인증서 확인 절차 ]]
```bash
## 1. 인증서 실제로 전재 여부 확인
sudo docker exec -u root nginx ls /etc/letsencrypt/live
# 여기에 shop.blissworld.org, possim.blissworld.org, ... 가 보이지 않으면 실제로 인증서가 발급되지 않은 것임.

## 2. certbot 내부 등록 cert-name 목록 확인
sudo docker exec -u root nginx certbot certificates
# 결과에 도메인이 아닌 shop.blissworld.org-0001, shop 같은 이름이 있다면
# --cert-name과 도메인이 달라서 --domain 기준으로 조회할 때 "없음"으로 나오는 것임.

## 3 setup_admin_site.sh 로그 확인
cat /app/logs/certbot_output.log | grep shop.blissworld.org -A 10
# 실제 certbot 실행이 성공했는지 실패했는지 확인 가능.
```
## [[ 고아(Orphan) 인증서 삭제 방법 ]]
```bash
## 1.[[ store의 인증서 확인 절차 ]] 결과에 나온 리스트중 certbot 내부 등록 cert-name 목록에 없는 것들 삭제.
  # 1.1 Dry-run 모드로 먼저 검토
  ./clean_orphan_certs.sh --dry-run
  # 1.2 확인 후 실제 삭제
  ./clean_orphan_certs.sh
  # 1.3 삭제 후 재확인
  sudo docker exec -u root nginx certbot certificates

## 2. [[ store의 인증서 확인 절차 ]] 결과에 나온 리스트중 certbot 내부 등록cert-name 목록에는 있는 것들 삭제.
## 이것들은 고아(Orphan) cert로 생각하지 않는다. 따라서 정식 삭제 방법(스크립트)을 사용해야한다.
sudo ./remove_franchise_site.sh possim.blissworld.org possim
```

# 📌 docker-compose admin 컨테이너 재사용 / 재생성 가이드

| 명령어 | 동작 방식 | 기존 컨테이너 내부 변경 내용 유지 여부 | 이미지 재빌드 여부 | 사용 시점 / 주의사항 |
|--------|-----------|-----------------------------------|-------------------|----------------------|
| docker compose up -d admin | 설정/이미지 변경 없으면 기존 컨테이너 재사용 | 유지됨 | 변경 시만 빌드 | 빠른 재시작, 내부 데이터 유지 필요 시 |
| docker compose up -d --build admin | 설정/이미지 변경 없으면 기존 컨테이너 재사용 | 유지됨 | 항상 새 빌드 | 새 JAR 또는 코드 반영, 내부 데이터 유지 필요 시 |
| docker compose up -d --force-recreate admin | 무조건 기존 컨테이너 삭제 후 새로 생성 | ❌ 사라짐 (볼륨 제외) | 변경 시만 빌드 | 컨테이너 구조 변경, 초기화 필요 시 |
| docker compose up -d --build --force-recreate admin | 무조건 새 컨테이너 생성 + 항상 새 빌드 | ❌ 사라짐 (볼륨 제외) | 항상 새 빌드 | 코드+구조 변경 모두 반영, 완전 초기화 필요 시 |
| docker compose restart admin | 컨테이너 재시작만 수행 | 유지됨 | ❌ 빌드 없음 | 단순 재시작, 빌드 불필요 시 |
