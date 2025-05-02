#!/bin/bash
set -eo pipefail

# 初始化配置
readonly COMPOSE_URL="https://raw.githubusercontent.com/LogicNekoChan/autoserver/refs/heads/main/modules/docker-compose.yml"
readonly COMPOSE_FILE="$(cd "$(dirname "$0")"; pwd)/docker-compose.yml"
readonly LOG_FILE="$(cd "$(dirname "$0")"; pwd)/deploy.log"
readonly REQUIRED_CMDS=("docker" "curl" "wget" "jq")

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
    
    # 验证 Docker Compose 版本
    if ! docker compose version &>/dev/null; then
        error_exit "需要 Docker Compose V2.4+，请参考官方文档升级"
    fi

    # 验证 jq 版本
    if ! jq --version &>/dev/null; then
        error_exit "需要安装 jq 工具：sudo apt install jq 或 sudo yum install jq"
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

    # 验证 compose 文件有效性
    if ! docker compose -f "$temp_file" config >/dev/null; then
        error_exit "下载的 compose 文件格式异常或包含错误"
    fi

    mv "$temp_file" "$COMPOSE_FILE"
    log "INFO" "文件已安全保存到: $COMPOSE_FILE"
}

# ----------------------------
# 动态解析服务列表（保持原始顺序）
# ----------------------------
parse_services() {
    log "INFO" "开始解析 compose 文件服务列表"
    
    # 生成标准化配置并转换为 JSON
    local compose_json
    if ! compose_json=$(docker compose -f "$COMPOSE_FILE" config --format json); then
        error_exit "解析 compose 文件失败，请检查文件格式"
    fi
    
    # 使用 jq 提取原始顺序服务列表
    local services=()
    mapfile -t services < <(echo "$compose_json" | jq -r '.services | keys_unsorted[]')
    
    if [ ${#services[@]} -eq 0 ]; then
        error_exit "compose 文件中未定义任何服务"
    fi
    
    log "INFO" "发现 ${#services[@]} 个服务"
    echo "${services[@]}"
}

# ----------------------------
# 交互式服务选择（优化显示）
# ----------------------------
select_service() {
    local -n services_ref=$1
    
    echo ""
    echo "============= 可用服务列表 ============="
    for i in "${!services_ref[@]}"; do
        printf " %2d) %-25s\n" "$((i+1))" "${services_ref[i]}"
    done
    echo "========================================"
    echo ""

    while : ; do
        read -rp "请输入服务编号 (1-${#services_ref[@]}): " input
        [[ "$input" =~ ^[0-9]+$ ]] || {
            echo "错误：请输入数字"
            continue
        }
        (( input >= 1 && input <= ${#services_ref[@]} )) && break
        echo "错误：编号超出范围，有效范围 1-${#services_ref[@]}"
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
        log "INFO" "正在创建 mintcat 网络..."
        docker network create mintcat || error_exit "网络创建失败"
    fi

    # 自动创建 compose 文件中定义的所有 volumes
    log "INFO" "检查存储卷配置..."
    local compose_json
    compose_json=$(docker compose -f "$COMPOSE_FILE" config --format json)
    mapfile -t volumes < <(echo "$compose_json" | jq -r '.volumes | keys[]')
    
    for vol in "${volumes[@]}"; do
        if ! docker volume inspect "$vol" &>/dev/null; then
            log "INFO" "正在创建存储卷: $vol"
            docker volume create "$vol" || error_exit "存储卷创建失败: $vol"
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
    if ! jq -e ".services.\"${service}\"" <(docker compose -f "$COMPOSE_FILE" config --format json) &>/dev/null; then
        error_exit "服务未在 compose 文件中定义: $service"
    fi

    # 执行部署
    log "INFO" "启动服务容器..."
    if ! docker compose -f "$COMPOSE_FILE" up -d "$service"; then
        error_exit "服务部署失败: $service"
    fi

    # 网络连接检查
    log "INFO" "验证网络连接..."
    local container_id=$(docker compose -f "$COMPOSE_FILE" ps -q "$service")
    if [ -z "$container_id" ]; then
        error_exit "无法获取容器ID: $service"
    fi

    if ! docker network inspect mintcat --format '{{ .Containers }}' | grep -q "$container_id"; then
        docker network connect mintcat "$container_id" || error_exit "网络连接失败"
        log "INFO" "已连接容器到网络: $container_id -> mintcat"
    fi

    log "INFO" "部署完成: $service"
    echo ""
    echo "========================================"
    echo "  服务 [$service] 已成功部署并联网!"
    echo "========================================"
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
