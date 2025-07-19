#!/usr/bin/env bash
set -e

##############################################################################
# 变量
##############################################################################
NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
IP="172.21.10.7"
CT_NAME="nginx"
IMG="jc21/nginx-proxy-manager:latest"
VOL_DATA="nginx_data"
VOL_SSL="letsencrypt"

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
  -p 80:80 \
  -p 81:81 \
  -p 443:443 \
  -v "$VOL_DATA":/data \
  -v "$VOL_SSL":/etc/letsencrypt \
  "$IMG"

##############################################################################
# 3) 等待 Nginx Proxy Manager Web UI 就绪
##############################################################################
echo "[INFO] 等待 Nginx Proxy Manager 启动 ..."
for i in {1..30}; do
  if docker exec "$CT_NAME" sh -c 'curl -s -o /dev/null -w "%{http_code}" http://localhost:81 | grep -q "200\|302\|303"'; then
    echo "[√] Nginx Proxy Manager 已就绪！"
    echo "管理界面：https://${IP}:81  默认账号：admin@example.com / changeme"
    exit 0
  fi
  sleep 3
done

echo "[!] Nginx Proxy Manager 启动超时"
exit 1
