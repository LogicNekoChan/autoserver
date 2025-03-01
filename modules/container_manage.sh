#!/bin/bash
# 容器管理模块（备份、恢复、删除）

# 设置备份路径及日志文件路径
BACKUP_DIR="/root/backup"
LOG_FILE="/root/autoserver.log"

# 检查备份目录是否存在，不存在则创建
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR" || { echo "[ERROR] 无法创建备份目录 $BACKUP_DIR"; exit 1; }
fi

# ----------------------------
# 日志记录函数
# ----------------------------
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# ----------------------------
# 错误处理函数
# ----------------------------
handle_error() {
    local error_msg="$1"
    echo "[ERROR] $error_msg"
    log_message "[ERROR] $error_msg"
    exit 1
}

# ----------------------------
# 恢复容器数据
# ----------------------------
restore_container_from_backup() {
    echo "正在列出备份文件..."
    local backups=()
    mapfile -t backups < <(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null)
    if [ ${#backups[@]} -eq 0 ]; then
        handle_error "没有找到备份文件。"
    fi

    select_backup backups

    # 获取正在运行的容器
    local running_containers=()
    mapfile -t running_containers < <(docker ps -q)
    if [ ${#running_containers[@]} -eq 0 ]; then
        handle_error "没有正在运行的容器。"
    fi
    select_container running_containers

    stop_and_clean_container
    restore_data
    start_container
}

# ----------------------------
# 选择备份文件
# 参数：备份文件数组名称（通过 nameref 传递）
# ----------------------------
select_backup() {
    local -n backups_arr=$1
    echo "可用的备份文件："
    for i in "${!backups_arr[@]}"; do
        echo "$((i+1)). ${backups_arr[i]}"
    done

    read -p "请输入备份文件序号: " backup_index
    if ! [[ "$backup_index" =~ ^[0-9]+$ ]] || [ "$backup_index" -le 0 ] || \
       [ "$backup_index" -gt "${#backups_arr[@]}" ]; then
        handle_error "无效的选择，请重试。"
    fi

    # 将用户选择的备份文件保存为全局变量
    selected_backup="${backups_arr[$((backup_index - 1))]}"
    echo "您选择的备份文件是：$selected_backup"
}

# ----------------------------
# 选择容器
# 参数：运行容器数组名称（通过 nameref 传递）
# ----------------------------
select_container() {
    local -n containers_arr=$1
    echo "可用的容器列表："
    local idx=0
    for container_id in "${containers_arr[@]}"; do
        local cname
        cname=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
        echo "$((idx+1)). $cname (ID: $container_id)"
        ((idx++))
    done

    read -p "请输入要恢复的容器序号: " container_index
    if ! [[ "$container_index" =~ ^[0-9]+$ ]] || [ "$container_index" -le 0 ] || \
       [ "$container_index" -gt "${#containers_arr[@]}" ]; then
        handle_error "无效的选择，请重试。"
    fi

    # 保存容器 ID 和名称为全局变量
    container_id="${containers_arr[$((container_index - 1))]}"
    container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
    echo "您选择的容器是：$container_name (ID: $container_id)"
}

# ----------------------------
# 停止并清理容器
# ----------------------------
stop_and_clean_container() {
    echo "正在停止容器 $container_name..."
    docker stop "$container_id" || docker kill "$container_id" || \
        handle_error "停止容器失败。"

    # 获取挂载的目录和卷
    local mounts volumes
    mounts=$(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Type=="bind") | .Source')
    volumes=$(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Type=="volume") | .Name')

    # 卸载挂载的目录
    for mount in $mounts; do
        if mountpoint -q "$mount"; then
            echo "卸载挂载目录：$mount"
            umount "$mount" || echo "无法卸载目录 $mount"
        fi
    done

    # 删除挂载的目录
    for mount in $mounts; do
        if [ -d "$mount" ]; then
            echo "删除目录：$mount"
            rm -rf "$mount"
        fi
    done

    # 删除挂载的卷
    for volume in $volumes; do
        echo "删除卷：$volume"
        docker volume rm "$volume" || echo "删除卷 $volume 失败。"
    done

    # 保存挂载和卷信息为全局变量，供数据恢复时使用
    global_mounts="$mounts"
    global_volumes="$volumes"
}

# ----------------------------
# 恢复数据
# ----------------------------
restore_data() {
    echo "开始恢复数据..."
    local volume_index=1
    for volume in $global_volumes; do
        local volume_path="/var/lib/docker/volumes/$volume/_data"
        echo "恢复卷 $volume ($volume_index)..."
        if [ -d "$volume_path" ]; then
            echo "备份当前卷数据：$volume_path"
            tar -czf "${volume_path}-$(date +%Y%m%d%H%M%S).tar.gz" "$volume_path" 2>/dev/null
            echo "将备份数据恢复到目录 $volume_path"
            tar -xvzf "$selected_backup" -C "$volume_path" || \
                handle_error "恢复卷 $volume 数据失败。"
        else
            echo "卷 $volume 的路径不存在，跳过恢复该卷。"
        fi
        ((volume_index++))
    done

    local mount_index=1
    for mount in $global_mounts; do
        if [ -d "$mount" ]; then
            echo "恢复挂载目录 $mount ($mount_index)..."
            tar -xvzf "$selected_backup" -C "$mount" || \
                handle_error "恢复挂载目录 $mount 数据失败。"
        fi
        ((mount_index++))
    done
}

# ----------------------------
# 启动容器
# ----------------------------
start_container() {
    echo "正在启动容器 $container_name..."
    docker start "$container_id" || handle_error "启动容器失败。"
    echo "恢复完成，容器已启动。"
    log_message "容器 $container_name 数据恢复完成，容器已启动。"
}

# ----------------------------
# 备份容器映射卷
# ----------------------------
backup_container() {
    echo "请选择需要备份的容器："
    local containers=()
    mapfile -t containers < <(docker ps --format "{{.Names}}")
    if [ ${#containers[@]} -eq 0 ]; then
        handle_error "当前没有任何容器！"
    fi

    for i in "${!containers[@]}"; do
        echo "$((i+1)). ${containers[i]}"
    done

    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || \
       [ "$idx" -gt "${#containers[@]}" ]; then
        handle_error "无效选择！"
    fi

    local selected_container="${containers[$((idx-1))]}"
    echo "开始备份容器 $selected_container 的映射卷..."

    local mounts
    mounts=$(docker inspect -f '{{json .Mounts}}' "$selected_container" | \
             jq -r '.[] | select(.Type=="volume" or .Type=="bind") | .Source')
    if [ -z "$mounts" ]; then
        handle_error "容器没有映射的卷或目录！"
    fi

    mkdir -p "$BACKUP_DIR"
    for mount in $mounts; do
        local mount_name
        mount_name=$(basename "$mount")
        local backup_file="$BACKUP_DIR/${selected_container}_$(date +%Y%m%d%H%M%S)_${mount_name}.tar.gz"
        echo "正在备份卷或目录：$mount"
        tar -czf "$backup_file" -C "$mount" . 2>/dev/null || \
            handle_error "备份失败：$mount"
        echo "备份完成，文件保存在：$backup_file"
        log_message "容器 $selected_container 的挂载点 $mount 备份完成，备份文件：$backup_file"
    done
}

# ----------------------------
# 删除容器
# ----------------------------
delete_container() {
    echo "请选择需要删除的容器："
    local containers=()
    mapfile -t containers < <(docker ps -a --format "{{.Names}}")
    if [ ${#containers[@]} -eq 0 ]; then
        handle_error "当前没有任何容器！"
    fi

    # 对容器名称排序
    local containers_sorted=($(printf "%s\n" "${containers[@]}" | sort))
    for i in "${!containers_sorted[@]}"; do
        echo "$((i+1)). ${containers_sorted[i]}"
    done

    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || \
       [ "$idx" -gt "${#containers_sorted[@]}" ]; then
        handle_error "无效选择！"
    fi

    local selected_container="${containers_sorted[$((idx-1))]}"
    echo "正在删除容器：$selected_container"
    docker rm -f "$selected_container" 2>/dev/null || \
        handle_error "删除容器失败！"
    echo "容器 $selected_container 已成功删除"
    log_message "容器 $selected_container 已删除"
}

# ----------------------------
# 主菜单
# ----------------------------
main_menu() {
    echo "======== 容器管理 ========"
    echo "1. 备份容器映射卷"
    echo "2. 恢复备份"
    echo "3. 删除容器"
    read -p "请选择操作: " option
    case "$option" in
        1) backup_container ;;
        2) restore_container_from_backup ;;
        3) delete_container ;;
        *) echo "[ERROR] 无效选择！" ;;
    esac
}

# ----------------------------
# 脚本入口
# ----------------------------
main_menu
