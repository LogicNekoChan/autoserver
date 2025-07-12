#!/usr/bin/env bash
# ------------------------------------------------------------------
# deploy.sh  ——  容器部署模块（独立可运行）
# 功能：下载 compose 文件 → 选择服务 → 一键 up -d
# ------------------------------------------------------------------
set -euo pipefail

# 默认下载源（可在环境变量覆盖）
COMPOSE_URL="${DEPLOY_COMPOSE_URL:-https://raw.githubusercontent.com/LogicNekoChan/autoserver/refs/heads/main/utils/docker-compose.yml}"
LOG_FILE="${LOG_FILE:-/root/autoserver.log}"

log() {
    local msg="$1"
    echo "$(date '+%F %T') - $msg" | tee -a "$LOG_FILE" >/dev/null
}
die() { log "[ERROR] $*"; echo "[!] $*" >&2; exit 1; }

# ----------------------------------------------
# 主部署流程
# ----------------------------------------------
deploy_system() {
    local tmp_compose="/tmp/autoserver-compose.yml"

    log "正在下载 docker-compose.yml ..."
    curl -fsSL "$COMPOSE_URL" -o "$tmp_compose" || die "下载 compose 文件失败"
    [[ -s $tmp_compose ]] || die "下载的文件为空"

    log "解析服务列表 ..."
    local services=($(docker-compose -f "$tmp_compose" config --services 2>/dev/null)) \
        || die "解析 compose 文件失败"
    [[ ${#services[@]} -eq 0 ]] && die "未找到任何服务定义"

    echo "请选择要部署的服务："
    local idx
    for idx in "${!services[@]}"; do
        printf "%3d) %s\n" $((idx+1)) "${services[idx]}"
    done

    local choice
    read -rp "请输入编号 [1-${#services[@]}]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#services[@]} )) || die "无效编号"
    local svc="${services[$((choice-1))]}"

    log "正在部署服务: $svc ..."
    docker-compose -f "$tmp_compose" pull "$svc" 2>/dev/null || true
    docker-compose -f "$tmp_compose" up -d "$svc" \
        && { log "服务 $svc 部署成功"; echo -e "\n[√] 部署完成"; } \
        || die "服务 $svc 部署失败"

    echo "服务状态："
    docker-compose -f "$tmp_compose" ps "$svc"
}

# -------------------------------------------------
# 直接执行时入口
# -------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行"
    command -v docker &>/dev/null || die "请先安装并启动 Docker"
    command -v docker-compose &>/dev/null || die "请先安装 docker-compose"
    deploy_system
fi
