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
        docker compose -f "$(dirname "$0")/../docker-compose.yml" up -d watchtower
        ;;
    "xui")
        echo "部署 XUI - 管理面板"
        docker compose -f "$(dirname "$0")/../docker-compose.yml" up -d xui
        ;;
    "nginx")
        echo "部署 Nginx Proxy Manager"
        docker compose -f "$(dirname "$0")/../docker-compose.yml" up -d nginx
        ;;
    "vaultwarden")
        echo "部署 Vaultwarden - 密码管理"
        docker compose -f "$(dirname "$0")/../docker-compose.yml" up -d vaultwarden
        ;;
    *)
        echo "[ERROR] 无效服务选择！"
        exit 1
        ;;
esac

# 额外步骤：确保虚拟网络和卷已经创建
echo "确保虚拟网络和卷已经创建..."

# 检查并删除冲突的网络（例如 root_mintcat）
existing_networks=$(docker network ls --filter "name=root_mintcat" -q)
if [ -n "$existing_networks" ]; then
    echo "检测到冲突网络 root_mintcat，正在删除..."
    docker network rm root_mintcat
    echo "冲突网络 root_mintcat 已删除。"
fi

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

# 更新的 docker-compose.yml 配置
cat <<EOF > "$(dirname "$0")/../docker-compose.yml"
version: "3.8"

services:
  # Watchtower - 自动更新容器
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
    command: --cleanup
    networks:
      - mintcat

  # XUI - 管理面板
  xui:
    image: enwaiax/x-ui:alpha-zh
    container_name: xui
    volumes:
      - xui_db:/etc/x-ui/
      - xui_cert:/root/cert/
    restart: unless-stopped
    networks:
      - mintcat

  # Nginx Proxy Manager
  nginx:
    image: jc21/nginx-proxy-manager
    container_name: nginx
    restart: unless-stopped
    networks:
      - mintcat
    ports:
      - "80:80"
      - "81:81"
      - "443:443"
    volumes:
      - nginx_data:/data
      - letsencrypt:/etc/letsencrypt

  # Vaultwarden - 密码管理
  vaultwarden:
    image: vaultwarden/server:latest
    container_name: vaultwarden
    restart: unless-stopped
    volumes:
      - vaultwarden_data:/data
    environment:
      - PUID=0
      - PGID=0
    networks:
      - mintcat

networks:
  mintcat:
    driver: bridge
    ipam:
      config:
        - subnet: "172.21.0.0/16"  # 修改为不冲突的子网
        - gateway: "172.21.0.1"    # 设置网关

volumes:
  xui_db:
  xui_cert:
  nginx_data:
  letsencrypt:
  vaultwarden_data:
EOF

echo "docker-compose.yml 配置文件已生成！"
