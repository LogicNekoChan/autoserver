#!/bin/bash
# 容器管理模块（备份、恢复、删除）

BACKUP_DIR="/root/backup"
mkdir -p "$BACKUP_DIR"

# 日志记录
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> /root/autoserver.log
}

# 选择容器
select_container() {
    local containers=("$@")
    if [ ${#containers[@]} -eq 0 ]; then
        echo "[ERROR] 当前无容器！"
        return 1
    fi
    for i in "${!containers[@]}"; do
        echo "$((i+1)). ${containers[$i]}"
    done
    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#containers[@]}" ]; then
        echo "[ERROR] 无效选择！"
        return 1
    fi
    echo "${containers[$((idx-1))]}"
    return 0
}

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

    # 获取容器的所有卷信息
    volumes=$(docker inspect -f '{{json .Mounts}}' "$selected_container" | jq -r '.[] | select(.Type=="volume") | .Source')

    if [ -z "$volumes" ]; then
        echo "[ERROR] 容器没有映射的卷！"
        return
    fi

    # 备份每个映射卷
    for volume in $volumes; do
        echo "备份卷：$volume"
        
        # 生成备份文件名
        backup_file="$BACKUP_DIR/$(basename $volume)_$(date +%F_%H%M%S).tar.gz"
        
        # 进行备份操作
        if ! tar -czvf "$backup_file" -C "$volume" . 2>/dev/null; then
            echo "[ERROR] 备份失败！"
            return
        fi

        echo "备份完成，文件保存在：$backup_file"
        log_message "容器 $selected_container 的卷 $volume 备份完成，备份文件：$backup_file"
    done
}

# 恢复容器备份
restore_container() {
    echo "请选择需要恢复的备份："
    backups=($(ls "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
    if [ ${#backups[@]} -eq 0 ]; then
        echo "[ERROR] 未检测到备份文件！"
        return
    fi
    for i in "${!backups[@]}"; do
        echo "$((i+1)). $(basename "${backups[$i]}")"
    done
    read -p "请输入备份文件序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#backups[@]}" ]; then
        echo "[ERROR] 无效选择！"
        return
    fi
    selected_backup=${backups[$((idx-1))]}
    echo "恢复备份文件：$selected_backup 到原路径（请确保目标目录可写）"

    # 确保恢复目录存在并且可以写入
    if ! tar -xzvf "$selected_backup" -C / 2>/dev/null; then
        echo "[ERROR] 恢复失败！"
        return
    fi

    log_message "恢复备份：$selected_backup"
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

# 主菜单
echo "======== 容器管理 ========"
echo "1. 备份容器映射卷"
echo "2. 恢复备份"
echo "3. 删除容器"
read -p "请选择操作: " option
case "$option" in
    1) backup_container ;;
    2) restore_container ;;
    3) delete_container ;;
    *) echo "[ERROR] 无效选择！" ;;
esac
