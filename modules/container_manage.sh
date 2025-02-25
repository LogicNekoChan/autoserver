#!/bin/bash
# 容器管理模块（备份、恢复、删除）

BACKUP_DIR="/root/backup"  # 备份路径

# 日志记录
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /root/autoserver.log
}

# 错误处理函数
handle_error() {
    echo "[ERROR] $1"
    log_message "[ERROR] $1"
    exit 1
}

# 恢复容器数据
restore_container_from_backup() {
    echo "正在列出备份文件..."
    
    # 列出备份文件
    backups=($(ls $BACKUP_DIR/*.tar.gz 2>/dev/null))
    if [ ${#backups[@]} -eq 0 ]; then
        handle_error "没有找到备份文件。"
    fi

    # 显示备份文件供选择
    select_backup

    # 获取并显示正在运行的容器
    running_containers=($(docker ps -q))
    if [ ${#running_containers[@]} -eq 0 ]; then
        handle_error "没有正在运行的容器。"
    fi
    select_container

    # 停止并清理容器
    stop_and_clean_container

    # 恢复数据
    restore_data

    # 启动容器
    start_container
}

# 选择备份文件
select_backup() {
    for i in "${!backups[@]}"; do
        echo "$((i + 1)). ${backups[i]}"
    done

    read -p "请输入备份文件序号: " backup_index
    if ! [[ "$backup_index" =~ ^[0-9]+$ ]] || [ "$backup_index" -le 0 ] || [ "$backup_index" -gt ${#backups[@]} ]; then
        handle_error "无效的选择，请重试。"
    fi

    selected_backup="${backups[$((backup_index - 1))]}"
    echo "您选择的备份文件是：$selected_backup"
}

# 选择容器
select_container() {
    for i in "${!running_containers[@]}"; do
        container_id="${running_containers[i]}"
        container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
        echo "$((i + 1)). $container_name (ID: $container_id)"
    done

    read -p "请输入要恢复的容器序号: " container_index
    if ! [[ "$container_index" =~ ^[0-9]+$ ]] || [ "$container_index" -le 0 ] || [ "$container_index" -gt ${#running_containers[@]} ]; then
        handle_error "无效的选择，请重试。"
    fi

    container_id="${running_containers[$((container_index - 1))]}"
    container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
    echo "您选择的容器是：$container_name (ID: $container_id)"
}

# 停止并清理容器
stop_and_clean_container() {
    echo "正在停止容器 $container_name..."
    docker stop "$container_id" || docker kill "$container_id" || handle_error "停止容器失败，尝试强制停止容器失败。"

    # 获取挂载的目录和卷
    mounts=$(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Type=="bind") | .Source')
    volumes=$(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Type=="volume") | .Name')

    # 卷和目录手动卸载
    for mount in $mounts; do
        if mountpoint -q "$mount"; then
            echo "卸载挂载目录：$mount"
            sudo umount "$mount" || echo "无法卸载目录 $mount"
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
}

# 恢复数据
restore_data() {
    volume_index=1
    for volume in $volumes; do
        volume_path="/var/lib/docker/volumes/$volume/_data"
        echo "恢复卷 $volume ($volume_index)..."
        if [ -d "$volume_path" ]; then
            echo "恢复卷 $volume 数据到目录 $volume_path"
            # 备份原有数据
            if [ -d "$volume_path" ]; then
                tar -czf "$volume_path-$(date +%Y%m%d%H%M%S).tar.gz" "$volume_path"
            fi
            # 恢复数据
            tar -xvzf "$selected_backup" -C "$volume_path" || handle_error "恢复卷 $volume 数据失败，退出。"
        else
            echo "卷 $volume 的路径不存在，跳过恢复该卷。"
        fi
        ((volume_index++))
    done

    mount_index=1
    for mount in $mounts; do
        if [ -d "$mount" ]; then
            echo "恢复挂载目录 $mount ($mount_index)..."
            tar -xvzf "$selected_backup" -C "$mount" || handle_error "恢复挂载目录 $mount 数据失败，退出。"
        fi
        ((mount_index++))
    done
}

# 启动容器
start_container() {
    echo "正在启动容器 $container_name..."
    docker start "$container_id" || handle_error "启动容器失败。"

    echo "恢复完成，容器已启动并恢复。"
    log_message "容器 $container_name 数据恢复完成，容器已启动。"
}

# 备份容器
backup_container() {
    echo "请选择需要备份的容器："
    containers=($(docker ps --format "{{.Names}}"))
    if [ ${#containers[@]} -eq 0 ]; then
        handle_error "当前没有任何容器！"
    fi

    for i in "${!containers[@]}"; do
        echo "$((i+1)). ${containers[$i]}"
    done

    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#containers[@]}" ]; then
        handle_error "无效选择！"
    fi

    selected_container=${containers[$((idx-1))]}
    echo "开始备份容器 $selected_container 的映射卷..."

    mounts=$(docker inspect -f '{{json .Mounts}}' "$selected_container" | jq -r '.[] | select(.Type=="volume" or .Type=="bind") | .Source')

    if [ -z "$mounts" ]; then
        handle_error "容器没有映射的卷或目录！"
    fi

    backup_path="$BACKUP_DIR"
    mkdir -p "$backup_path"

    for mount in $mounts; do
        mount_name=$(basename "$mount")
        backup_file="$backup_path/${selected_container}_$(date +%Y%m%d%H%M%S)_${mount_name}.tar.gz"
        echo "备份卷或目录：$mount"
        tar -czf "$backup_file" -C "$mount" . 2>/dev/null || handle_error "备份失败：$mount"
        echo "备份完成，文件保存在：$backup_file"
        log_message "容器 $selected_container 的挂载点 $mount 备份完成，备份文件：$backup_file"
    done
}

# 删除容器
delete_container() {
    echo "请选择需要删除的容器："
    containers=($(docker ps -a --format "{{.Names}}"))
    containers_sorted=($(for c in "${containers[@]}"; do echo "$c"; done | sort))

    if [ ${#containers_sorted[@]} -eq 0 ]; then
        handle_error "当前没有任何容器！"
    fi

    for i in "${!containers_sorted[@]}"; do
        echo "$((i+1)). ${containers_sorted[$i]}"
    done

    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#containers_sorted[@]}" ]; then
        handle_error "无效选择！"
    fi

    selected_container=${containers_sorted[$((idx-1))]}
    echo "删除容器：$selected_container"
    docker rm -f "$selected_container" 2>/dev/null || handle_error "删除容器失败！"
    echo "容器 $selected_container 已成功删除"
    log_message "容器 $selected_container 已删除"
}

# 主菜单
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
