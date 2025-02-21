#!/bin/bash
# 容器管理模块（备份、恢复、删除）

BACKUP_DIR="/root/backup"
mkdir -p "$BACKUP_DIR"

function backup_container() {
    echo "请选择需要备份的容器："
    containers=($(docker ps --format "{{.Names}}"))
    if [ ${#containers[@]} -eq 0 ]; then
        echo "[ERROR] 当前无运行中的容器！"
        return
    fi
    for i in "${!containers[@]}"; do
        echo "$((i+1)). ${containers[$i]}"
    done
    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#containers[@]}" ]; then
        echo "[ERROR] 无效选择！"
        return
    fi
    selected_container=${containers[$((idx-1))]}
    echo "开始备份容器 $selected_container 的映射卷..."
    # 获取映射卷路径（示例：使用 docker inspect 获取 Mounts 信息）
    volume=$(docker inspect "$selected_container" | grep -Po '(?<="Source": ")[^"]+')
    if [ -z "$volume" ]; then
        echo "[ERROR] 未找到映射卷！"
        return
    fi
    backup_file="$BACKUP_DIR/${selected_container}_$(date +%F_%H%M%S).tar.gz"
    tar -czvf "$backup_file" "$volume"
    echo "备份完成，文件保存在：$backup_file"
}

function restore_container() {
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
    # 此处示例为解压到同一目录，实际恢复操作视情况而定
    tar -xzvf "$selected_backup" -C /
}

function delete_container() {
    echo "请选择需要删除的容器："
    containers=($(docker ps -a --format "{{.Names}}"))
    if [ ${#containers[@]} -eq 0 ]; then
        echo "[ERROR] 当前无容器！"
        return
    fi
    for i in "${!containers[@]}"; do
        echo "$((i+1)). ${containers[$i]}"
    done
    read -p "请输入容器序号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#containers[@]}" ]; then
        echo "[ERROR] 无效选择！"
        return
    fi
    selected_container=${containers[$((idx-1))]}
    echo "删除容器：$selected_container"
    docker rm -f "$selected_container"
}

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
