#!/bin/bash

## $1 으로 domain 인자를 받아
DOMAIN=$1

## certbot certificates 명령어 실행해서 해당 도메인이 있는지 grep
output=$(certbot certificates --domain "$DOMAIN" 2>&1)

if echo "$output" | grep -q "No matching certificates found"; then
    echo "none"
else
    echo "valid"
fi
