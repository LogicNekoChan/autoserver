#!/bin/bash
# 容器管理模块（备份、恢复、删除、部署） - 优化版

# ----------------------------
# 初始化配置
# ----------------------------
BACKUP_DIR="/root/backup"
LOG_FILE="/root/autoserver.log"
DOCKER_DATA_DIR="/var/lib/docker"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/LogicNekoChan/autoserver/refs/heads/main/modules/docker-compose.yml"
DEPENDENCIES=("docker" "jq" "tar" "curl" "docker-compose")

# ----------------------------
# 预检模块
# ----------------------------
preflight_check() {
    # 必须使用 root 用户运行
    if [ "$(id -u)" != "0" ]; then
        handle_error "必须使用 root 用户运行"
    fi

    # 检查依赖项
    local missing=()
    for cmd in "${DEPENDENCIES[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        handle_error "缺少依赖: ${missing[*]}"$'\n'"请执行：apt install ${missing[*]}"
    fi
}

# ----------------------------
# 日志记录 (带日志轮转)
# ----------------------------
log_message() {
    local message="$1"
    local log_size=$(wc -c <"$LOG_FILE" 2>/dev/null)
    [ -z "$log_size" ] && log_size=0

    # 日志轮转 (10MB)
    if [ "$log_size" -gt 10485760 ]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# ----------------------------
# 错误处理增强版
# ----------------------------
handle_error() {
    local error_msg="$1"
    log_message "[ERROR] $error_msg"
    echo -e "\n[!] 错误: $error_msg" >&2
    exit 1
}

# ----------------------------
# 通用选择器 (支持自动序号)
# ----------------------------
universal_selector() {
    local -n items=$1
    local prompt=$2
    local max_retry=${3:-3}
    
    if [ ${#items[@]} -eq 0 ]; then
        handle_error "没有可选项"
    fi

    for ((attempt=1; attempt<=max_retry; attempt++)); do
        # 显示带序号的选项
        for i in "${!items[@]}"; do
            printf "%3d) %s\n" $((i+1)) "${items[i]}"
        done

        read -rp "${prompt} [1-${#items[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#items[@]}" ]; then
            return $((selection-1))
        fi
        echo "输入无效，请重试 (剩余尝试次数: $((max_retry-attempt)))"
    done

    handle_error "超过最大重试次数"
}

# ----------------------------
# 智能容器停止
# ----------------------------
graceful_stop() {
    local container_id=$1
    log_message "正在停止容器: $container_id"
    
    # 先尝试正常停止
    if ! docker stop "$container_id" >/dev/null 2>&1; then
        log_message "正常停止失败，尝试强制停止"
        docker kill "$container_id" >/dev/null 2>&1 || handle_error "无法停止容器"
    fi
}

# ----------------------------
# 安全清理挂载点
# ----------------------------
safe_clean_mounts() {
    local container_id=$1
    log_message "清理容器挂载点: $container_id"

    # 获取挂载信息
    local mounts=($(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Type=="bind") | .Source'))

    # 逆序处理挂载点
    for ((i=${#mounts[@]}-1; i>=0; i--)); do
        local mnt="${mounts[i]}"
        if [ -d "$mnt" ]; then
            # 卸载挂载点
            if mountpoint -q "$mnt"; then
                umount "$mnt" 2>/dev/null || log_message "警告: 无法卸载 $mnt (可能仍有进程访问)"
            fi

            # 删除目录
            rm -rf "$mnt" 2>/dev/null && log_message "已清理目录: $mnt" || log_message "警告: 无法删除 $mnt"
        fi
    done
}

# ----------------------------
# 智能备份系统
# ----------------------------
backup_system() {
    # 获取运行中的容器列表
    local containers=($(docker ps --format "{{.Names}}"))
    if [ ${#containers[@]} -eq 0 ]; then
        handle_error "没有运行中的容器"
    fi

    # 容器选择
    echo "选择要备份的容器:"
    universal_selector containers "请输入容器序号" 3
    local selected_container="${containers[$?]}"

    # 获取挂载点信息
    local mount_points=($(docker inspect "$selected_container" | jq -r '.[].Mounts[] | select(.Type=="bind" or .Type=="volume") | .Source'))
    if [ ${#mount_points[@]} -eq 0 ]; then
        handle_error "没有找到挂载点"
    fi

    # 创建备份目录
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="${BACKUP_DIR}/${selected_container}_${timestamp}"
    mkdir -p "$backup_path" || handle_error "无法创建备份目录"

    # 执行备份
    local backup_count=0
    local total_mounts=${#mount_points[@]}
    for path in "${mount_points[@]}"; do
        backup_count=$((backup_count + 1))
        local safe_path=$(realpath "$path" 2>/dev/null)
        if [[ "$safe_path" != $DOCKER_DATA_DIR/* ]]; then
            handle_error "检测到非Docker路径: $path"
        fi

        local mount_type=$(docker inspect "$selected_container" | jq -r --arg path "$path" '.[].Mounts[] | select(.Source==$path) | .Type')

        local backup_file="${backup_path}/${mount_type}_$(basename "$path").tar.gz"
        log_message "正在备份: $path → $backup_file (进度: $backup_count/$total_mounts)"
        
        if tar -czf "$backup_file" -C "$(dirname "$path")" "$(basename "$path")" 2>/dev/null; then
            log_message "备份成功 (大小: $(du -h "$backup_file" | cut -f1))"
        else
            handle_error "备份失败: $path"
        fi
    done

    echo -e "\n[√] 备份完成于: $backup_path"
}

# ----------------------------
# 智能恢复系统
# ----------------------------
restore_system() {
    # 获取备份集列表
    local backup_sets=($(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d))
    if [ ${#backup_sets[@]} -eq 0 ]; then
        handle_error "没有找到备份集"
    fi

    # 备份集选择
    echo "选择要恢复的备份集:"
    universal_selector backup_sets "请输入备份序号" 3
    local selected_backup="${backup_sets[$?]}"

    # 解析备份信息
    local container_name=$(basename "$selected_backup" | cut -d_ -f1)
    local backup_files=("$selected_backup"/*.tar.gz)
    if [ ${#backup_files[@]} -eq 0 ]; then
        handle_error "备份集损坏"
    fi

    # 检查是否存在同名容器
    local containers=($(docker ps -a --filter "name=$container_name" --format "{{.Names}}"))
    if [ ${#containers[@]} -eq 0 ]; then
        handle_error "找不到同名容器"
    fi

    # 容器选择
    echo "选择要替换的容器:"
    universal_selector containers "请输入容器序号" 3
    local target_container="${containers[$?]}"

    # 停止并清理旧容器
    graceful_stop "$target_container"
    safe_clean_mounts "$target_container"
    docker rm -f "$target_container" >/dev/null || handle_error "无法删除旧容器"

    # 数据恢复
    for backup_file in "${backup_files[@]}"; do
        local path_name=$(basename "$backup_file" .tar.gz)
        local restore_path="${DOCKER_DATA_DIR}/volumes/$path_name"
        mkdir -p "$restore_path" || handle_error "无法创建恢复目录"
        log_message "正在恢复: $backup_file → $restore_path"
        
        if tar -xzf "$backup_file" -C "$restore_path"; then
            log_message "恢复成功 (内容: $(ls "$restore_path" | wc -l) 项)"
        else
            handle_error "恢复失败: $backup_file"
        fi
    done

    # 提示用户手动重新启动容器
    echo -e "\n[√] 数据恢复完成，请手动重新启动容器"
}


# ----------------------------
# 安全删除系统
# ----------------------------
delete_system() {
    # 获取所有容器列表
    local containers=($(docker ps -a --format "{{.Names}}"))
    if [ ${#containers[@]} -eq 0 ]; then
        handle_error "没有可删除的容器"
    fi

    # 容器选择
    echo "选择要删除的容器:"
    universal_selector containers "请输入容器序号" 3
    local selected_container="${containers[$?]}"

    # 确认流程
    read -rp "确认删除 $selected_container 及其所有数据？[y/N] " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 停止并删除
        graceful_stop "$selected_container"
        safe_clean_mounts "$selected_container"
        
        if docker rm -f "$selected_container" >/dev/null; then
            log_message "已删除容器: $selected_container"
            echo -e "\n[√] 删除成功"
        else
            handle_error "删除失败"
        fi
    else
        echo "操作已取消"
    fi
}

deploy_containers() {
    echo "[INFO] 正在从 URL 下载 docker-compose 文件: $DOCKER_COMPOSE_URL"
    local compose_file="/tmp/docker-compose.yml"
    
    if ! curl -fsSL "$DOCKER_COMPOSE_URL" -o "$compose_file"; then
        handle_error "下载 docker-compose 文件失败"
    fi

    echo "[INFO] 文件已安全保存到: $compose_file"
    
    # 解析 docker-compose 文件中的服务
    local services=($(docker-compose -f "$compose_file" config --services))
    if [ ${#services[@]} -eq 0 ]; then
        handle_error "未找到任何服务定义"
    fi

    # 显示服务列表并让用户选择
    echo "请选择要部署的服务编号："
    for i in "${!services[@]}"; do
        printf "%3d) %s\n" $((i+1)) "${services[i]}"
    done

    read -rp "请输入服务编号 (1-${#services[@]}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#services[@]}" ]; then
        selected_service="${services[$((choice-1))]}"
    else
        handle_error "无效的服务编号"
    fi

    echo "正在部署服务: $selected_service"
    if docker-compose -f "$compose_file" up -d "$selected_service"; then
        log_message "服务 $selected_service 部署成功"
        echo -e "\n[√] 服务 $selected_service 部署完成"
        echo "部署的服务状态："
        docker-compose -f "$compose_file" ps "$selected_service"
    else
        handle_error "服务 $selected_service 部署失败"
    fi
}


# ----------------------------
# 主界面
# ----------------------------
show_menu() {
    clear
    echo -e "\nDocker 容器管理套件"
    echo "--------------------------------"
    echo "1) 容器备份"
    echo "2) 数据恢复"
    echo "3) 容器删除"
    echo "4) 部署容器"
    echo "5) 退出"
    echo "--------------------------------"
    
    while true; do
        read -rp "请输入操作编号: " choice
        case "$choice" in
            1) backup_system ;;
            2) restore_system ;;
            3) delete_system ;;
            4) deploy_containers ;;
            5) exit 0 ;;
            *) echo "无效选择，请重新输入" ;;
        esac
        echo  # 保持空行分隔
    done
}

# ----------------------------
# 主程序入口
# ----------------------------
main() {
    preflight_check
    [ ! -d "$BACKUP_DIR" ] && mkdir -p "$BACKUP_DIR"
    log_message "=== 启动管理程序 ==="
    show_menu
}

# 启动主程序
main
            
