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

    # 停止容器并确保其没有挂载卷
    echo "正在停止容器 $container_name..."
    docker stop "$container_id" || {
        echo "停止容器失败，尝试强制停止容器..."
        docker kill "$container_id" || exit 1
    }

    # 获取挂载的目录和卷
    echo "正在列出容器的挂载目录和卷..."
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

    # 恢复容器的数据卷
    echo "正在恢复容器的数据卷..."

    # 恢复数据卷
    for volume in $volumes; do
        volume_path="/var/lib/docker/volumes/$volume/_data"
        if [ -d "$volume_path" ]; then
            echo "恢复卷 $volume 数据到目录 $volume_path"
            # 备份原有数据
            if [ -d "$volume_path" ]; then
                tar -czf "$volume_path-$(date +%Y%m%d%H%M%S).tar.gz" "$volume_path"
            fi
            # 恢复数据
            tar -xvzf "$selected_backup" -C "$volume_path" || {
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
            # 恢复数据
            tar -xvzf "$selected_backup" -C "$mount" || {
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
