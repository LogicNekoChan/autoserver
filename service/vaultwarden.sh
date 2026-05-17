#!/usr/bin/env bash
set -euo pipefail

# ==============================
# 可配置区域（仅修改这里即可）
# ==============================
CT_NAME="vaultwarden"
VOL_NAME="vw_data"          # Docker 命名卷名称
BIND_SRC=""                 # 绑定挂载路径（留空则使用命名卷）
MOUNT_POINT="/data"         # 容器内数据目录
IMAGE="vaultwarden/server:latest"

# ==============================
# 颜色输出（美观易读）
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${YELLOW}[INFO] $*${NC}"; }
warn()  { echo -e "${RED}[WARN] $*${NC}"; }
success() { echo -e "${GREEN}[SUCCESS] $*${NC}"; }

# ==============================
# 检查 Docker 运行状态
# ==============================
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker 未运行，请先启动 Docker${NC}"
    exit 1
fi

# ==============================
# 停止并删除旧容器
# ==============================
info "清理旧容器: $CT_NAME"
docker rm -f "$CT_NAME" >/dev/null 2>&1 || true

# ==============================
# 确定挂载方式
# ==============================
if [[ -z "${BIND_SRC}" ]]; then
    # ==========================
    # 模式 1：使用 Docker 命名卷
    # ==========================
    info "使用【命名卷】模式: $VOL_NAME"

    # 安全重建卷（避免挂载类型冲突）
    if docker volume ls -q | grep -qx "$VOL_NAME"; then
        warn "检测到已有卷 $VOL_NAME，将重建以确保挂载类型一致"
        docker volume rm "$VOL_NAME" >/dev/null
    fi

    docker volume create "$VOL_NAME" >/dev/null
    MOUNT_SPEC="${VOL_NAME}:${MOUNT_POINT}"

else
    # ==========================
    # 模式 2：使用宿主机绑定挂载
    # ==========================
    info "使用【绑定挂载】模式: $BIND_SRC"
    mkdir -p "$BIND_SRC"
    MOUNT_SPEC="${BIND_SRC}:${MOUNT_POINT}"
fi

# ==============================
# 启动容器
# ==============================
info "启动容器 $CT_NAME..."
docker run -d \
  --name "$CT_NAME" \
  --restart unless-stopped \
  -v "$MOUNT_SPEC" \
  "$IMAGE"

# ==============================
# 完成输出
# ==============================
success "Vaultwarden 启动成功！"
echo -e "${GREEN}挂载方式: $MOUNT_SPEC${NC}"
