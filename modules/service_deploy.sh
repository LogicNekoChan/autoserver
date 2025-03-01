#!/bin/bash
# 服务选择部署模块

# 定义服务列表（对应容器名称）
services=("watchtower" "xui" "nginx" "vaultwarden" "portainer_agent" "portainer_ce")

# 定义 docker-compose 配置文件路径（相对于当前脚本所在目录）
COMPOSE_FILE="$(dirname "$0")/../docker-compose.yml"

# ----------------------------
# 打印服务列表
# ----------------------------
print_services() {
    echo "检测到以下服务："
    for i in "${!services[@]}"; do
        echo "$((i+1)). ${services[$i]}"
    done
}

# ----------------------------
# 选择服务
# ----------------------------
select_service() {
    print_services
    read -p "请选择需要部署的服务编号: " idx
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#services[@]}" ]; then
        echo "[ERROR] 无效选择！"
        exit 1
    fi
    selected_service="${services[$((idx-1))]}"
    echo "正在部署服务：$selected_service"
}

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
    local volumes=("xui_db" "xui_cert" "nginx_data" "letsencrypt" "vaultwarden_data" "portainer_data")
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
    echo "docker-compose.yml 配置文件已生成：$COMPOSE_FILE"
}

# ----------------------------
# 部署服务
# ----------------------------
deploy_service() {
    local service="$1"
    case "$service" in
        "watchtower"|"xui"|"nginx"|"vaultwarden")
            docker compose -f "$COMPOSE_FILE" up -d "$service" || { echo "[ERROR] 部署 $service 失败！"; exit 1; }
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

# ----------------------------
# 主函数
# ----------------------------
main() {
    select_service
    create_network_and_volumes
    generate_docker_compose
    deploy_service "$selected_service"
}

# 执行主函数
main
