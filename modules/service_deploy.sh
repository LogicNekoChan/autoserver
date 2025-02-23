#!/bin/bash
# 服务选择部署模块

# 服务列表及其对应的容器名称
services=("watchtower" "xui" "nginx" "vaultwarden" "portainer_agent" "portainer_ce")

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
    "portainer_agent")
        echo "部署 Portainer Agent - 用于管理 Docker 主机"
        docker run -d \
          -p 9001:9001 \
          --name portainer_agent \
          --restart=always \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v /var/lib/docker/volumes:/var/lib/docker/volumes \
          -v /:/host \
          portainer/agent:2.21.5
        ;;
    "portainer_ce")
        echo "部署 Portainer CE - Docker 管理面板"
        docker run -d \
          -p 8000:8000 \
          -p 9443:9443 \
          --name portainer \
          --restart=always \
          -v /var/run/docker.sock:/var/run/docker.sock \
          -v portainer_data:/data \
          portainer/portainer-ce:lts
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
    # 停止并断开所有与该网络相关的容器
    containers=$(docker network inspect root_mintcat -f '{{range .Containers}}{{.Name}} {{end}}')
    for container in $containers; do
        docker network disconnect root_mintcat $container
    done
    # 尝试删除该网络，忽略错误
    docker network rm root_mintcat >/dev/null 2>&1
    echo "冲突网络 root_mintcat 已删除。"
fi

# 创建 mintcat 网络（如果不存在）
docker network inspect mintcat >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "虚拟网络 mintcat 不存在，正在创建..."
    docker network create --driver bridge mintcat
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

# 更新的 docker-compose.yml 配置（不输出到屏幕）
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

  # Portainer Agent - 用于管理 Docker 主机
  portainer_agent:
    image: portainer/agent:2.21.5
    container_name: portainer_agent
    restart: unless-stopped
    networks:
      - mintcat
    ports:
      - "9001:9001"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
      - /:/host

  # Portainer CE - Docker 管理面板
  portainer_ce:
    image: portainer/portainer-ce:lts
    container_name: portainer_ce
    restart: unless-stopped
    ports:
      - "8000:8000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - mintcat

networks:
  mintcat:
    driver: bridge

volumes:
  xui_db:
  xui_cert:
  nginx_data:
  letsencrypt:
  vaultwarden_data:
  portainer_data:
EOF

echo "docker-compose.yml 配置文件已生成！"
