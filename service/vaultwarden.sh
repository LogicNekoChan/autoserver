#!/usr/bin/env bash
set -e

NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
VW_CT="vaultwarden"
VW_IMAGE="vaultwarden/server:latest"
VW_VOLUME="vw_data"          # ← 关键：使用 Docker 命名卷

# 1. 创建命名卷（如已存在会静默跳过）
docker volume create "$VW_VOLUME" >/dev/null 2>&1 || true

# 2. 创建自定义桥接网络（如已存在会静默跳过）
docker network ls | grep -q "$NET_NAME" \
  || docker network create --driver bridge --subnet="$SUBNET" "$NET_NAME"

# 3. 停掉/删除旧容器（如有）
docker rm -f "$VW_CT" >/dev/null 2>&1 || true

# 4. 启动新容器，把命名卷挂到 /data
docker run -d \
  --name "$VW_CT" \
  --restart unless-stopped \
  --network "$NET_NAME" \
  -v "$VW_VOLUME":/data \
  "$VW_IMAGE"

# 5. 等待健康检查通过
echo "[INFO] 等待 vaultwarden 健康检查通过 ..."
for i in {1..30}; do
  status=$(docker inspect --format='{{.State.Health.Status}}' "$VW_CT" 2>/dev/null || true)
  [[ "$status" == "healthy" ]] && { echo "[√] vaultwarden 已就绪！"; exit 0; }
  sleep 2
done

echo "[!] vaultwarden 健康检查超时"
exit 1
