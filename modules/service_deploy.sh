#!/bin/bash
set -eo pipefail

# 初始化配置
readonly COMPOSE_URL="https://raw.githubusercontent.com/LogicNekoChan/autoserver/refs/heads/main/modules/docker-compose.yml"
readonly COMPOSE_FILE="$(cd "$(dirname "$0")"; pwd)/docker-compose.yml"
readonly LOG_FILE="$(cd "$(dirname "$0")"; pwd)/deploy.log"
readonly REQUIRED_CMDS=("docker" "curl" "wget")

# ----------------------------
# 日志记录函数
# ----------------------------
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

# ----------------------------
# 错误处理增强
# ----------------------------
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# ----------------------------
# 依赖检查
# ----------------------------
check_dependencies() {
    local missing=()
    for cmd in "${REQUIRED_CMDS[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    [ ${#missing[@]} -gt 0 ] && error_exit "缺少必要命令: ${missing[*]}"
    
    # 检查 Docker Compose V2 可用性
    if ! docker compose version &>/dev/null; then
        error_exit "需要 Docker Compose V2 支持，请参考官方文档安装"
    fi
}

# ----------------------------
# 安全下载文件
# ----------------------------
safe_download() {
    log "INFO" "开始下载 compose 文件: $COMPOSE_URL"
    
    local temp_file="${COMPOSE_FILE}.tmp"
    trap 'rm -f "$temp_file"' EXIT

    if command -v curl &>/dev/null; then
        curl -fsSL -o "$temp_file" "$COMPOSE_URL" || error_exit "下载失败 (CURL错误码: $?)"
    else
        wget -qO "$temp_file" "$COMPOSE_URL" || error_exit "下载失败 (WGET错误码: $?)"
    fi

    # 验证文件有效性
    if ! grep -q 'version:' "$temp_file"; then
        error_exit "下载文件格式异常，缺少 compose 版本声明"
    fi

    mv "$temp_file" "$COMPOSE_FILE"
    log "INFO" "文件已安全保存到: $COMPOSE_FILE"
}

# ----------------------------
# 动态解析服务列表
# ----------------------------
parse_services() {
    log "INFO" "开始解析 compose 文件服务列表"
    
    # 获取原始服务列表
    local raw_services
    if ! raw_services=$(docker compose -f "$COMPOSE_FILE" config --services 2>&1); then
        error_exit "解析服务失败: $raw_services"
    fi
    
    # 转换为排序后的数组
    mapfile -t services < <(echo "$raw_services" | sort -V)
    
    if [ ${#services[@]} -eq 0 ]; then
        error_exit "compose 文件中未定义任何服务"
    fi
    
    log "INFO" "发现 ${#services[@]} 个服务: ${services[*]}"
    echo "${services[@]}"
}

# ----------------------------
# 交互式服务选择
# ----------------------------
select_service() {
    local -n services_ref=$1
    
    echo "可用服务列表:"
    for i in "${!services_ref[@]}"; do
        printf "%2d) %s\n" "$((i+1))" "${services_ref[i]}"
    done

    while : ; do
        read -rp "请输入服务编号 (1-${#services_ref[@]}): " input
        [[ "$input" =~ ^[0-9]+$ ]] || continue
        (( input >= 1 && input <= ${#services_ref[@]} )) && break
    done

    selected="${services_ref[$((input-1))]}"
    log "INFO" "已选择服务: $selected"
    echo "$selected"
}

# ----------------------------
# 网络与存储管理
# ----------------------------
setup_infrastructure() {
    # 创建网络
    if ! docker network inspect mintcat &>/dev/null; then
        docker network create mintcat || error_exit "网络创建失败"
        log "INFO" "已创建网络: mintcat"
    fi

    # 批量创建存储卷（示例，可根据实际情况调整）
    local volumes=("xui_db" "xui_cert" "nginx_data" "letsencrypt" 
                   "vaultwarden_data" "portainer_data" "tor_config" "tor_data")
    
    for vol in "${volumes[@]}"; do
        if ! docker volume inspect "$vol" &>/dev/null; then
            docker volume create "$vol" || error_exit "存储卷创建失败: $vol"
            log "INFO" "已创建存储卷: $vol"
        fi
    done
}

# ----------------------------
# 服务部署
# ----------------------------
deploy_service() {
    local service="$1"
    log "INFO" "开始部署服务: $service"

    # 验证服务存在性
    if ! docker compose -f "$COMPOSE_FILE" config --services | grep -qx "$service"; then
        error_exit "服务未在 compose 文件中定义: $service"
    fi

    # 执行部署
    if ! docker compose -f "$COMPOSE_FILE" up -d "$service"; then
        error_exit "服务部署失败: $service"
    fi

    # 网络连接检查
    local container_id=$(docker compose -f "$COMPOSE_FILE" ps -q "$service")
    if [ -z "$container_id" ]; then
        error_exit "无法获取容器ID: $service"
    fi

    if ! docker network inspect mintcat --format '{{ .Containers }}' | grep -q "$container_id"; then
        docker network connect mintcat "$container_id" || error_exit "网络连接失败"
        log "INFO" "已连接容器到网络: $container_id -> mintcat"
    fi

    log "INFO" "部署完成: $service"
}

# ----------------------------
# 主流程
# ----------------------------
main() {
    check_dependencies
    safe_download
    local services=($(parse_services))
    local selected=$(select_service services)
    setup_infrastructure
    deploy_service "$selected"
}

main "$@"
