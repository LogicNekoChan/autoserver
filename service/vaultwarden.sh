#!/usr/bin/env bash
set -e

NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
VW_CT="vaultwarden"
VW_IMAGE="vaultwarden/server:latest"

read -rp "挂载卷本地目录 [$(pwd)/vaultwarden_data]: " MOUNT_DIR
MOUNT_DIR="${MOUNT_DIR:-$(pwd)/vaultwarden_data}"
mkdir -p "$MOUNT_DIR"

docker network ls | grep -q "$NET_NAME" || docker network create --driver bridge --subnet="$SUBNET" "$NET_NAME"

docker rm -f "$VW_CT" >/dev/null 2>&1 || true

docker run -d \
  --name "$VW_CT" \
  --restart unless-stopped \
  --network "$NET_NAME" \
  -v "$MOUNT_DIR":/data \
  "$VW_IMAGE"

echo "[INFO] 等待 vaultwarden 健康检查通过 ..."
for i in {1..30}; do
  status=$(docker inspect --format='{{.State.Health.Status}}' "$VW_CT" 2>/dev/null || true)
  [[ "$status" == "healthy" ]] && { echo "[√] vaultwarden 已就绪！"; exit 0; }
  sleep 2
done

echo "[!] vaultwarden 健康检查超时"
exit 1
