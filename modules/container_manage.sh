#!/bin/bash
# 容器管理模块（备份、恢复、删除）

BACKUP_DIR="/root/backup"  # 备份路径

# 日志记录
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /root/autoserver.log
}

# 恢复容器备份并重建卷和挂载目录
restore_container_from_backup() {
    echo "正在列出备份文件..."
    
    # 列出备份文件
    backups=($(ls $BACKUP_DIR/*.tar.gz 2>/dev/null))
    if [ ${#backups[@]} -eq 0 ]; then
        echo "没有找到备份文件。"
        exit 1
    fi

    # 显示备份文件供选择
    for i in "${!backups[@]}"; do
        backup_file="${backups[i]}"
        echo "$((i + 1)). $backup_file"
    done

    read -p "请输入备份文件序号: " backup_index
    if ! [[ "$backup_index" =~ ^[0-9]+$ ]] || [ "$backup_index" -le 0 ] || [ "$backup_index" -gt ${#backups[@]} ]; then
        echo "无效的选择，请重试。"
        exit 1
    fi

    selected_backup="${backups[$((backup_index - 1))]}"
    echo "您选择的备份文件是：$selected_backup"

    # 获取正在运行的容器
    echo "正在列出正在运行的容器..."
    running_containers=($(docker ps -q))
    if [ ${#running_containers[@]} -eq 0 ]; then
        echo "没有正在运行的容器。"
        exit 1
    fi

    # 显示容器供选择
    for i in "${!running_containers[@]}"; do
        container_id="${running_containers[i]}"
        container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
        echo "$((i + 1)). $container_name (ID: $container_id)"
    done

    read -p "请输入要恢复的容器序号: " container_index
    if ! [[ "$container_index" =~ ^[0-9]+$ ]] || [ "$container_index" -le 0 ] || [ "$container_index" -gt ${#running_containers[@]} ]; then
        echo "无效的选择，请重试。"
        exit 1
    fi

    container_id="${running_containers[$((container_index - 1))]}"
    container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')
    echo "您选择的容器是：$container_name (ID: $container_id)"

    # 停止容器
    echo "正在停止容器 $container_name..."
    docker stop "$container_id" || exit 1

    # 获取挂载的目录和卷
    echo "正在列出容器的挂载目录和卷..."
    mounts=$(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Type=="bind") | .Source')
    volumes=$(docker inspect "$container_id" | jq -r '.[].Mounts[] | select(.Type=="volume") | .Name')

    # 删除挂载的目录
    for mount in $mounts; do
        if [ -d "$mount" ]; then
            rm -rf "$mount"
            echo "删除目录：$mount"
        fi
    done

    # 删除挂载的卷
    for volume in $volumes; do
        echo "删除卷：$volume"
        docker volume rm "$volume" || echo "删除卷 $volume 失败。"
    done

    # 恢复容器的卷和数据
    echo "正在恢复容器的数据卷..."

    # 恢复数据卷
    for volume in $volumes; do
        volume_path="/var/lib/docker/volumes/$volume/_data"
        if [ -d "$volume_path" ]; then
            echo "恢复卷 $volume 数据到目录 $volume_path"
            tar --strip-components=6 -xvzf "$selected_backup" -C "$volume_path" || {
                echo "恢复卷 $volume 数据失败，退出。"
                exit 1
            }
        else
            echo "卷 $volume 的路径不存在，跳过恢复该卷。"
        fi
    done

    # 恢复挂载目录数据
    for mount in $mounts; do
        if [ -d "$mount" ]; then
            echo "恢复挂载目录 $mount"
            tar --strip-components=6 -xvzf "$selected_backup" -C "$mount" || {
                echo "恢复挂载目录 $mount 数据失败，退出。"
                exit 1
            }
        fi
    done

    # 启动容器
    echo "正在启动容器 $container_name..."
    docker start "$container_id" || exit 1

    echo "恢复完成，容器已启动并恢复。"
    log_message "容器 $container_name 数据恢复完成，容器已启动。"
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

# 备份容器
backup_container() {
    echo "请选择需要备份的容器："
    
    # 获取所有正在运行的容器名称
    containers=($(docker ps --format "{{.Names}}"))
    
    # 如果没有容器
    if [ ${#containers[@]} -eq 0 ]; then
        echo "[ERROR] 当前没有任何容器！"
        return
    fi

    # 按编号列出容器
    for i in "${!containers[@]}"; do
        echo "$((i+1)). ${containers[$i]}"
    done

    # 用户选择容器
    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#containers[@]}" ]; then
        echo "[ERROR] 无效选择！"
        return
    fi

    # 获取用户选择的容器
    selected_container=${containers[$((idx-1))]}
    echo "开始备份容器 $selected_container 的映射卷..."

    # 获取容器的所有挂载卷信息
    mounts=$(docker inspect -f '{{json .Mounts}}' "$selected_container" | jq -r '.[] | select(.Type=="volume" or .Type=="bind") | .Source')

    if [ -z "$mounts" ]; then
        echo "[ERROR] 容器没有映射的卷或目录！"
        return
    fi

    # 设置备份文件保存路径
    backup_path="$BACKUP_DIR/$(date +%Y%m%d%H%M%S)"
    mkdir -p "$backup_path"

    # 备份每个映射卷或目录
    for mount in $mounts; do
        # 获取卷或目录的名称
        mount_name=$(basename "$mount")
        echo "备份卷或目录：$mount"
        
        # 生成备份文件名
        backup_file="$backup_path/${mount_name}_backup_$(date +%F_%H%M%S).tar.gz"
        
        # 进行备份操作
        if ! tar -czf "$backup_file" -C "$mount" . 2>/dev/null; then
            echo "[ERROR] 备份失败：$mount"
            return
        fi

        echo "备份完成，文件保存在：$backup_file"
        log_message "容器 $selected_container 的挂载点 $mount 备份完成，备份文件：$backup_file"
    done
}

# 删除容器
delete_container() {
    echo "请选择需要删除的容器："
    
    # 获取所有容器的名称，包括运行中的和已停止的
    containers=($(docker ps -a --format "{{.Names}}"))
    containers_sorted=($(for c in "${containers[@]}"; do echo "$c"; done | sort))  # 按字母顺序排序容器
    
    # 如果没有容器
    if [ ${#containers_sorted[@]} -eq 0 ]; then
        echo "[ERROR] 当前没有任何容器！"
        return
    fi

    # 列出容器供用户选择
    for i in "${!containers_sorted[@]}"; do
        echo "$((i+1)). ${containers_sorted[$i]}"
    done
    
    # 选择容器
    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#containers_sorted[@]}" ]; then
        echo "[ERROR] 无效选择！"
        return
    fi

    selected_container=${containers_sorted[$((idx-1))]}
    echo "删除容器：$selected_container"

    # 删除容器
    if ! docker rm -f "$selected_container" 2>/dev/null; then
        echo "[ERROR] 删除容器失败！"
        return
    fi

    echo "容器 $selected_container 已成功删除"
    log_message "容器 $selected_container 已删除"
}

