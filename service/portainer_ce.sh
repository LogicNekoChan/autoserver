#!/usr/bin/env bash
set -e

##############################################################################
# 变量
##############################################################################
NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
IP="172.21.10.3"
CT_NAME="portainer_ce"
IMG="portainer/portainer-ce:2.21.5"
VOL="portainer_data"

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
  -p 9000:9000 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$VOL":/data \
  "$IMG"

##############################################################################
# 3) 等待 Portainer Web UI 就绪（HTTPS 判定）
##############################################################################
echo "[INFO] 等待 Portainer 启动 ..."
for i in {1..30}; do
  if docker exec "$CT_NAME" sh -c 'curl -s -k -o /dev/null -w "%{http_code}" https://localhost:9443 | grep -q "200\|307"'; then
    echo "[√] Portainer 已就绪！"
    echo "请访问：https://${IP}:9443"
    exit 0
  fi
  sleep 3
done

echo "[!] Portainer 启动超时"
exit 1
