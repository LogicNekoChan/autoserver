#!/bin/bash
# 交互式选择部署容器脚本
# 根据编号选择服务，下载远程 docker-compose 配置文件，并部署选定容器，
# 同时确保容器加入外部网络 mintcat

# 定义服务列表（对应 docker-compose.yml 中的服务名称与 container_name）
services=("watchtower" "xui" "nginx" "vaultwarden" "portainer_agent" "portainer_ce" "tor")

# 远程 docker-compose 配置文件 URL
COMPOSE_URL="https://raw.githubusercontent.com/LogicNekoChan/autoserver/refs/heads/main/modules/docker-compose.yml"
# 本地存储 docker-compose 配置文件路径（脚本所在目录下）
COMPOSE_FILE="$(dirname "$0")/docker-compose.yml"

# ----------------------------
# 下载 docker-compose 文件
# ----------------------------
fetch_compose_file() {
    echo "正在从 ${COMPOSE_URL} 下载 docker-compose 配置文件..."
    if command -v curl >/dev/null 2>&1; then
        curl -sSL -o "$COMPOSE_FILE" "$COMPOSE_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$COMPOSE_FILE" "$COMPOSE_URL"
    else
        echo "[ERROR] curl 与 wget 均不可用，请安装其中之一。"
        exit 1
    fi
    if [ $? -ne 0 ]; then
        echo "[ERROR] 下载 docker-compose 配置文件失败。"
        exit 1
    fi
    echo "docker-compose 配置文件已保存到 $COMPOSE_FILE"
}

# ----------------------------
# 打印服务列表
# ----------------------------
print_services() {
    echo "请选择要部署的服务编号："
    for i in "${!services[@]}"; do
        echo "$((i+1)). ${services[$i]}"
    done
}

# ----------------------------
# 交互式选择服务
# ----------------------------
select_service() {
    print_services
    read -p "请输入服务编号: " num
    if ! [[ "$num" =~ ^[0-9]+$ ]] || [ "$num" -lt 1 ] || [ "$num" -gt "${#services[@]}" ]; then
        echo "[ERROR] 无效的编号！"
        exit 1
    fi
    selected_service="${services[$((num-1))]}"
    echo "您选择的服务是：$selected_service"
}

# ----------------------------
# 创建外部网络 mintcat 与必要的数据卷（如果不存在）
# ----------------------------
create_network_and_volumes() {
    # 检查并创建外部网络 mintcat
    if ! docker network inspect mintcat >/dev/null 2>&1; then
        echo "外部网络 mintcat 不存在，正在创建..."
        docker network create --driver bridge mintcat || { echo "[ERROR] 创建网络 mintcat 失败！"; exit 1; }
    else
        echo "外部网络 mintcat 已存在。"
    fi

    # 定义需要创建的数据卷列表
    volumes=("xui_db" "xui_cert" "nginx_data" "letsencrypt" "vaultwarden_data" "portainer_data" "tor_config" "tor_data")
    for volume in "${volumes[@]}"; do
        if ! docker volume inspect "$volume" >/dev/null 2>&1; then
            echo "数据卷 $volume 不存在，正在创建..."
            docker volume create "$volume" || { echo "[ERROR] 创建数据卷 $volume 失败！"; exit 1; }
        else
            echo "数据卷 $volume 已存在。"
        fi
    done
}

# ----------------------------
# 部署选定的服务，并确保容器加入 mintcat 网络
# ----------------------------
deploy_service() {
    local service="$1"
    # 使用 docker-compose 部署指定服务
    docker compose -f "$COMPOSE_FILE" up -d "$service" || { echo "[ERROR] 部署 $service 失败！"; exit 1; }
    
    # 假设 docker-compose 文件中 container_name 与服务名称一致
    container_name="$service"
    
    # 检查容器是否已经加入 mintcat 网络
    if ! docker network inspect mintcat --format '{{json .Containers}}' | grep -q "\"Name\":\"/$container_name\""; then
        echo "正在将容器 $container_name 连接到 mintcat 网络..."
        docker network connect mintcat "$container_name" || { echo "[ERROR] 连接容器 $container_name 到 mintcat 网络失败！"; exit 1; }
    fi
    echo "服务 $service 已成功部署，并已连接到 mintcat 网络。"
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    fetch_compose_file
    select_service
    create_network_and_volumes
    deploy_service "$selected_service"
}

# 执行主函数
main

