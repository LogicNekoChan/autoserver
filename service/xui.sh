#!/usr/bin/env bash
set -e

##############################################################################
# 变量
##############################################################################
NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
IP="172.21.10.8"
CT_NAME="xui"
IMG="bigbugcc/3x-ui:latest"
VOL_DB="xui_db"
VOL_CERT="xui_cert"

##############################################################################
# 1) 创建网络（如不存在）
##############################################################################
docker network ls | grep -q "$NET_NAME" || \
  docker network create \
    --driver bridge \
    --subnet="$SUBNET" \
    "$NET_NAME"

##############################################################################
# 2) 清理旧容器（如果存在）并启动新容器
##############################################################################
docker rm -f "$CT_NAME" >/dev/null 2>&1 || true

docker run -d \
  --name "$CT_NAME" \
  --restart unless-stopped \
  --network "$NET_NAME" \
  --ip "$IP" \
  -v "$VOL_DB":/etc/x-ui \
  -v "$VOL_CERT":/root/cert \
  "$IMG"

##############################################################################
# 3) 等待 x-ui Web UI 就绪
##############################################################################
echo "[INFO] 等待 x-ui 启动 ..."
for i in {1..30}; do
  if docker exec "$CT_NAME" sh -c 'curl -s -o /dev/null -w "%{http_code}" http://localhost:2053 | grep -q "200\|302\|303"'; then
    echo "[√] x-ui 已就绪！"
    echo "访问面板：http://${IP}:54321"
    exit 0
  fi
  sleep 3
done

echo "[!] x-ui 启动超时"
exit 1
