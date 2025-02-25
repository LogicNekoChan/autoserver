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

# 基于服务选择来部署
deploy_service() {
    case "$1" in
        "watchtower"|"xui"|"nginx"|"vaultwarden")
            docker compose -f "$(dirname "$0")/../docker-compose.yml" up -d "$1" || { echo "[ERROR] 部署 $1 失败！"; exit 1; }
            ;;
        "portainer_agent")
            docker run -d \
                -p 9001:9001 \
                --name portainer_agent \
                --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v /var/lib/docker/volumes:/var/lib/docker/volumes \
                -v /:/host \
                portainer/agent:2.21.5 || { echo "[ERROR] 部署 Portainer Agent 失败！"; exit 1; }
            ;;
        "portainer_ce")
            docker run -d \
                -p 8000:8000 \
                -p 9443:9443 \
                -p 9000:9000 \
                --name portainer_ce \
                --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                portainer/portainer-ce:lts || { echo "[ERROR] 部署 Portainer CE 失败！"; exit 1; }
            ;;
        *)
            echo "[ERROR] 无效服务选择！"
            exit 1
            ;;
    esac
}

# 确保网络和卷已创建
create_network_and_volumes() {
    # 创建 mintcat 网络（如果不存在）
    if ! docker network inspect mintcat >/dev/null 2>&1; then
        echo "虚拟网络 mintcat 不存在，正在创建..."
        docker network create --driver bridge mintcat || { echo "[ERROR] 创建网络 mintcat 失败！"; exit 1; }
    else
        echo "虚拟网络 mintcat 已存在。"
    fi

    # 创建卷
    declare -a volumes=("xui_db" "xui_cert" "nginx_data" "letsencrypt" "vaultwarden_data" "portainer_data")
    for volume in "${volumes[@]}"; do
        if ! docker volume inspect "$volume" >/dev/null 2>&1; then
            echo "卷 $volume 不存在，正在创建..."
            docker volume create "$volume" || { echo "[ERROR] 创建卷 $volume 失败！"; exit 1; }
        else
            echo "卷 $volume 已存在。"
        fi
    done
}

# 更新并生成 docker-compose.yml 配置
generate_docker_compose() {
    cat <<EOF > "$(dirname "$0")/../docker-compose.yml"
version: "3.8"

services:
  watchtower:
    image: containrrr/watchtower
    container_name: watchtower
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
    command: --cleanup
    networks:
      - mintcat

  xui:
    image: enwaiax/x-ui:alpha-zh
    container_name: xui
    volumes:
      - xui_db:/etc/x-ui/
      - xui_cert:/root/cert/
    restart: unless-stopped
    networks:
      - mintcat

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
}

# 执行部署
create_network_and_volumes
generate_docker_compose
deploy_service "$selected_service"
