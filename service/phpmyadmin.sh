#!/usr/bin/env bash
set -e

##############################################################################
# 变量
##############################################################################
NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
IP="172.21.10.11"
CT_NAME="phpmyadmin"
IMG="phpmyadmin:latest"

##############################################################################
# 1) 创建网络（如不存在）
##############################################################################
docker network ls | grep -q "$NET_NAME" || \
  docker network create \
    --driver bridge \
    --subnet="$SUBNET" \
    "$NET_NAME"

##############################################################################
# 2) 清理旧容器（如存在）并启动新容器
##############################################################################
docker rm -f "$CT_NAME" >/dev/null 2>&1 || true

docker run -d \
  --name "$CT_NAME" \
  --restart unless-stopped \
  --network "$NET_NAME" \
  --ip "$IP" \
  -e PMA_HOST=mysql \
  -e PMA_PORT=3306 \
  -e UPLOAD_LIMIT=1G \
  -p 8080:80 \
  "$IMG"

##############################################################################
# 3) 等待 phpMyAdmin 启动完成（HTTP 判定）
##############################################################################
echo "[INFO] 等待 phpMyAdmin 启动 ..."
for i in {1..30}; do
  if docker exec "$CT_NAME" sh -c 'curl -s -o /dev/null -w "%{http_code}" http://localhost | grep -q "200\|302\|303"'; then
    echo "[√] phpMyAdmin 已就绪！"
    echo "请访问：http://${IP}:80  或  http://<宿主机IP>:8080"
    exit 0
  fi
  sleep 3
done

echo "[!] phpMyAdmin 启动超时"
exit 1
