#!/usr/bin/env bash
set -euo pipefail

# ==============================
# 配置变量（集中管理）
# ==============================
CT_NAME="portainer_ce"
IMG="portainer/portainer-ce:2.21.5"
VOL="portainer_data"
WEB_PORT="9000"
SSL_PORT="9443"

# ==============================
# 颜色输出（更美观）
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${YELLOW}[INFO] $*${NC}"; }
success() { echo -e "${GREEN}[√] $*${NC}"; }
error() { echo -e "${RED}[!] $*${NC}"; exit 1; }

# ==============================
# 检查 Docker 是否运行
# ==============================
if ! docker info >/dev/null 2>&1; then
    error "Docker 未运行，请先启动 Docker"
fi

# ==============================
# 清理旧容器
# ==============================
info "清理旧容器..."
docker rm -f "$CT_NAME" >/dev/null 2>&1 || true

# ==============================
# 启动 Portainer（host 网络模式）
# ==============================
info "启动 Portainer 容器..."
docker run -d \
  --name "$CT_NAME" \
  --restart unless-stopped \
  --net=host \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$VOL":/data \
  "$IMG"

# ==============================
# 等待服务启动完成
# ==============================
info "等待 Portainer 启动..."
for ((i=1; i<=30; i++)); do
    if curl -s -k -o /dev/null -w "%{http_code}" "https://127.0.0.1:$SSL_PORT" | grep -qE "200|307"; then
        success "Portainer 启动完成！"
        echo -e "访问地址：${GREEN}https://本机IP:$SSL_PORT${NC}"
        echo -e "HTTP 地址：${GREEN}http://本机IP:$WEB_PORT${NC}"
        exit 0
    fi
    sleep 2
done

error "Portainer 启动超时，请检查容器日志：docker logs $CT_NAME"
