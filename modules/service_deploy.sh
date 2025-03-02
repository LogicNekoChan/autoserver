#!/bin/bash
# 全栈服务部署模块，确保所有服务在同一网络 mintcat 下

# 定义服务列表（仅供参考，实际全部服务会同时部署）
services=("watchtower" "xui" "nginx" "vaultwarden" "portainer_agent" "portainer_ce" "tor")

# 定义 docker-compose 配置文件路径（相对于当前脚本所在目录）
COMPOSE_FILE="$(dirname "$0")/../docker-compose.yml"

# ----------------------------
# 创建网络和卷（如果不存在则创建）
# ----------------------------
create_network_and_volumes() {
    # 检查并创建 mintcat 网络
    if ! docker network inspect mintcat >/dev/null 2>&1; then
        echo "虚拟网络 mintcat 不存在，正在创建..."
        docker network create --driver bridge mintcat || { echo "[ERROR] 创建网络 mintcat 失败！"; exit 1; }
    else
        echo "虚拟网络 mintcat 已存在。"
    fi

    # 定义需要创建的卷列表
    local volumes=("xui_db" "xui_cert" "nginx_data" "letsencrypt" "vaultwarden_data" "portainer_data" "tor_config" "tor_data")
    for volume in "${volumes[@]}"; do
        if ! docker volume inspect "$volume" >/dev/null 2>&1; then
            echo "卷 $volume 不存在，正在创建..."
            docker volume create "$volume" || { echo "[ERROR] 创建卷 $volume 失败！"; exit 1; }
        else
            echo "卷 $volume 已存在。"
        fi
    done
}

# ----------------------------
# 生成 docker-compose.yml 配置文件
# ----------------------------
generate_docker_compose() {
    cat <<EOF > "$COMPOSE_FILE"
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
      - "9000:9000"
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - mintcat

  tor:
    image: dockurr/tor
    container_name: tor
    restart: always
    volumes:
      - tor_config:/etc/tor
      - tor_data:/var/lib/tor
    networks:
      - mintcat
    stop_grace_period: 1m

networks:
  mintcat:
    external: true

volumes:
  xui_db:
  xui_cert:
  nginx_data:
  letsencrypt:
  vaultwarden_data:
  portainer_data:
  tor_config:
  tor_data:
EOF
    echo "docker-compose.yml 配置文件已生成：$COMPOSE_FILE"
}

# ----------------------------
# 部署全部服务（全栈部署确保所有容器均加入 mintcat 网络）
# ----------------------------
deploy_all_services() {
    echo "正在部署全部服务..."
    docker compose -f "$COMPOSE_FILE" up -d || { echo "[ERROR] 部署服务失败！"; exit 1; }
}

# ----------------------------
# 主函数
# ----------------------------
main() {
    create_network_and_volumes
    generate_docker_compose
    deploy_all_services
}

# 执行主函数
main
