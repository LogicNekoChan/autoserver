#!/usr/bin/env bash
# -------------------------------------------------
# deploy.sh  ——  本地服务安装器
# 功能：列出 /root/autoserver/service/*.sh → 交互选择 → 执行脚本
# -------------------------------------------------
set -euo pipefail

readonly SERVICE_DIR="/root/autoserver/service"
readonly LOG_FILE="/root/autoserver.log"

# 颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly NC='\033[0m'

log() { echo "$(date '+%F %T') - $*" | tee -a "$LOG_FILE" >/dev/null; }
die() { log "[ERROR] $*"; echo -e "${RED}[!] $*${NC}" >&2; exit 1; }

# -------------------------------------------------
# 1. 前置检测
# -------------------------------------------------
check_deps() {
    command -v docker >/dev/null 2>&1 || die "Docker 未安装或未启动"
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        die "未检测到 docker compose / docker-compose"
    fi
    log "检测通过，使用 compose 命令: $COMPOSE_CMD"
}

# -------------------------------------------------
# 2. 读取本地服务脚本
# -------------------------------------------------
mapfile -t SCRIPTS < <(find "$SERVICE_DIR" -maxdepth 1 -type f -name '*.sh' | sort)
[[ ${#SCRIPTS[@]} -eq 0 ]] && die "在 $SERVICE_DIR 下未找到任何 .sh 服务脚本"

# -------------------------------------------------
# 3. 交互选择
# -------------------------------------------------
select_service() {
    echo -e "\n${GREEN}===== 可安装的服务 =====${NC}"
    local i
    for i in "${!SCRIPTS[@]}"; do
        printf "%2d) %s\n" $((i+1)) "$(basename "${SCRIPTS[i]}" .sh)"
    done
    echo " q) 退出"
    read -rp "请输入编号: " choice
    [[ "$choice" == "q" ]] && { echo "已取消"; exit 0; }
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#SCRIPTS[@]} )) \
        || { echo -e "${RED}无效输入${NC}"; sleep 1; return 1; }
    SCRIPT="${SCRIPTS[$((choice-1))]}"
}

# -------------------------------------------------
# 4. 主循环
# -------------------------------------------------
main() {
    [[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行"
    check_deps

    while true; do
        select_service || continue
        log "开始执行脚本: $SCRIPT"
        bash "$SCRIPT"
        log "脚本执行结束: $SCRIPT"
        read -rp $'\n按回车返回主菜单...'
    done
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
