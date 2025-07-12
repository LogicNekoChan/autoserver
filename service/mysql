#!/bin/bash
set -e

NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
IP="172.21.10.6"
VOL="mysql_data"
CT_NAME="mysql"

# 1) 创建自定义网络（若已存在会忽略）
docker network ls | grep -q "$NET_NAME" || \
  docker network create \
    --driver bridge \
    --subnet="$SUBNET" \
    "$NET_NAME"

# 2) 启动 mysql 容器
docker run d \
  --name "$CT_NAME" \
  --restart unless-stopped \
  --network "$NET_NAME" \
  --ip "$IP" \
  -e MYSQL_ROOT_PASSWORD=admin123 \
  -e MYSQL_INITDB_SKIP_TZINFO=true \
  -v "$VOL":/var/lib/mysql \
  mysql:8.0

# 3) 等待健康检查通过
echo "[INFO] 等待 mysql 健康检查通过 ..."
for i in {1..30}; do
  if docker exec "$CT_NAME" mysqladmin ping -h localhost --silent; then
    echo "[√] mysql 已就绪！"
    exit 0
  fi
  sleep 2
done

echo "[!] mysql 健康检查超时"
exit 1
