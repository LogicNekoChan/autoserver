#!/bin/bash
# 服务选择部署模块

# 服务列表及其对应的容器名称
services=("watchtower" "xui" "nginx" "vaultwarden")

echo "检测到以下服务："
for i in "${!services[@]}"; do
    echo "$((i+1)). ${services[$i]}"
done

read -p "请选择需要部署的服务编号: " idx
if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#services[@]}" ]; then
    echo "[ERROR] 无效选择！"
    exit 1
fi

selected_service=${services[$((idx-1))]}
echo "正在部署服务：$selected_service"

# 根据选择部署指定的服务
case "$selected_service" in
    "watchtower")
        echo "部署 Watchtower - 自动更新容器"
        docker-compose -f "$(dirname "$0")/../docker-compose.yml" up -d watchtower
        ;;
    "xui")
        echo "部署 XUI - 管理面板"
        docker-compose -f "$(dirname "$0")/../docker-compose.yml" up -d xui
        ;;
    "nginx")
        echo "部署 Nginx Proxy Manager"
        docker-compose -f "$(dirname "$0")/../docker-compose.yml" up -d nginx
        ;;
    "vaultwarden")
        echo "部署 Vaultwarden - 密码管理"
        docker-compose -f "$(dirname "$0")/../docker-compose.yml" up -d vaultwarden
        ;;
    *)
        echo "[ERROR] 无效服务选择！"
        exit 1
        ;;
esac

# 额外步骤：确保虚拟网络和卷已经创建
echo "确保虚拟网络和卷已经创建..."

# 创建 mintcat 网络（如果不存在）
docker network inspect mintcat >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "虚拟网络 mintcat 不存在，正在创建..."
    docker network create \
        --driver bridge \
        --subnet 172.21.0.0/16 \
        --gateway 172.21.0.1 \
        mintcat
    echo "虚拟网络 mintcat 创建成功。"
else
    echo "虚拟网络 mintcat 已存在。"
fi

# 创建卷
declare -a volumes=("xui_db" "xui_cert" "nginx_data" "letsencrypt" "vaultwarden_data")
for volume in "${volumes[@]}"; do
    docker volume inspect "$volume" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "卷 $volume 不存在，正在创建..."
        docker volume create "$volume"
        echo "卷 $volume 创建成功。"
    else
        echo "卷 $volume 已存在。"
    fi
done

echo "服务部署完成！"
