#!/usr/bin/env bash
set -e

##############################################################################
# 0. 通用变量
##############################################################################
NET_NAME="mintcat"
SUBNET="172.21.10.0/24"
MYSQL_IP="172.21.10.6"
VW_IP="172.21.10.5"

MYSQL_CT="mysql"
VW_CT="vaultwarden"
MYSQL_IMAGE="mysql:8.0"
VW_IMAGE="vaultwarden/server:latest"

MYSQL_ROOT_PW="admin123"
MYSQL_VOL="mysql_data"
VW_VOL="vaultwarden_data"

##############################################################################
# 1. 创建网络（如不存在）
##############################################################################
docker network ls | grep -q "$NET_NAME" || \
  docker network create --driver bridge --subnet="$SUBNET" "$NET_NAME"

##############################################################################
# 2. 先启动/复用 MySQL
##############################################################################
if ! docker ps -a --format '{{.Names}}' | grep -q "^${MYSQL_CT}$"; then
  echo "[INFO] 首次启动 MySQL ..."
  docker run -d \
    --name "$MYSQL_CT" \
    --restart unless-stopped \
    --network "$NET_NAME" \
    --ip "$MYSQL_IP" \
    -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PW" \
    -e MYSQL_INITDB_SKIP_TZINFO=true \
    -v "$MYSQL_VOL":/var/lib/mysql \
    "$MYSQL_IMAGE"
fi

# 等待 MySQL 就绪
echo "[INFO] 等待 MySQL 健康检查通过 ..."
for i in {1..30}; do
  if docker exec "$MYSQL_CT" mysqladmin ping -h localhost --silent; then
    echo "[√] MySQL 已就绪！"
    break
  fi
  sleep 2
done

##############################################################################
# 3. 交互式收集 vaultwarden 所需参数
##############################################################################
read -rp "MySQL 端口 [$MYSQL_IP:3306] : " MYSQL_PORT
MYSQL_PORT=${MYSQL_PORT:-3306}

read -rp "vaultwarden 数据库名 [vaultwarden] : " MYSQL_DB
MYSQL_DB=${MYSQL_DB:-vaultwarden}

read -rp "vaultwarden 数据库用户名 [vwuser] : " MYSQL_USER
MYSQL_USER=${MYSQL_USER:-vwuser}

# 隐藏输入
read -rsp "vaultwarden 数据库密码 : " MYSQL_PASS
echo
if [[ -z "$MYSQL_PASS" ]]; then
  echo "密码不能为空" >&2
  exit 1
fi

read -rsp "vaultwarden 管理员令牌 (ADMIN_TOKEN) : " VW_ADMIN_TOKEN
echo
VW_ADMIN_TOKEN=${VW_ADMIN_TOKEN:-changeme_admin_token}

##############################################################################
# 4. 在 MySQL 里创建库和用户（如果不存在）
##############################################################################
echo "[INFO] 配置 MySQL 用户/库 ..."
docker exec -i "$MYSQL_CT" mysql -uroot -p"$MYSQL_ROOT_PW" <<EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DB}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASS}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DB}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOF

##############################################################################
# 5. 启动/更新 vaultwarden 容器
##############################################################################
docker rm -f "$VW_CT" >/dev/null 2>&1 || true

docker run -d \
  --name "$VW_CT" \
  --restart unless-stopped \
  --network "$NET_NAME" \
  --ip "$VW_IP" \
  -e WEBSOCKET_ENABLED=true \
  -e SIGNUPS_ALLOWED=true \
  -e ADMIN_TOKEN="$VW_ADMIN_TOKEN" \
  -e DATABASE_URL="mysql://${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_IP}:${MYSQL_PORT}/${MYSQL_DB}" \
  -v "$VW_VOL":/data \
  --health-cmd 'curl -f http://localhost/ || exit 1' \
  "$VW_IMAGE"

##############################################################################
# 6. 等待 vaultwarden 健康检查
##############################################################################
echo "[INFO] 等待 vaultwarden 健康检查通过 ..."
for i in {1..30}; do
  status=$(docker inspect --format='{{.State.Health.Status}}' "$VW_CT" 2>/dev/null || true)
  [[ "$status" == "healthy" ]] && { echo "[√] vaultwarden 已就绪！"; exit 0; }
  sleep 2
done

echo "[!] vaultwarden 健康检查超时"
exit 1
