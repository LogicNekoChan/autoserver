#!/usr/bin/env bash
set -e

##############################################################################
# 变量
##############################################################################
NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
IP="172.21.10.9"
CT_NAME="watchtower"
IMG="containrrr/watchtower:latest"

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
  -v /var/run/docker.sock:/var/run/docker.sock \
  "$IMG" \
  --cleanup \
  --schedule "0 3 * * *"

##############################################################################
# 3) 等待启动完成（简单判定）
##############################################################################
echo "[INFO] 等待 watchtower 启动 ..."
for i in {1..10}; do
  if docker ps --filter "name=^${CT_NAME}$" --filter "status=running" --format '{{.Names}}' | grep -q "$CT_NAME"; then
    echo "[√] watchtower 已就绪！"
    exit 0
  fi
  sleep 2
done

echo "[!] watchtower 启动超时"
exit 1
