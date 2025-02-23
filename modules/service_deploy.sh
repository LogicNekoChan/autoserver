#!/bin/bash
# 服务选择部署模块 - 优化后版本 (修复 YAML 错误)

# 服务列表及其对应的容器名称
services=("watchtower" "xui" "nginx" "vaultwarden" "portainer")
compose_file="$(dirname "$0")/../docker-compose.yml" # 定义 docker-compose.yml 文件路径

# 定义卷列表
declare -a volumes=("xui_db" "xui_cert" "nginx_data" "letsencrypt" "vaultwarden_data" "portainer_data")

# 函数：检查 Docker 命令是否执行成功
check_docker_command() {
  if [ $? -ne 0 ]; then
    echo "[ERROR] Docker 命令执行失败！"
    exit 1
  fi
}

# 函数：创建 Docker 网络
create_docker_network() {
  docker network inspect "$1" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "虚拟网络 $1 不存在，正在创建..."
    docker network create --driver bridge "$1"
    check_docker_command
    echo "虚拟网络 $1 创建成功。"
  else
    echo "虚拟网络 $1 已存在。"
  fi
}

# 函数：创建 Docker 卷
create_docker_volume() {
  docker volume inspect "$1" >/dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "卷 $1 不存在，正在创建..."
    docker volume create "$1"
    check_docker_command
    echo "卷 $1 创建成功。"
  else
    echo "卷 $1 已存在。"
  fi
}

echo "检测到以下服务："
for i in "${!services[@]}"; do
  echo "$((i+1)). ${services[$i]}"
done

read -p "请选择需要部署的服务编号: " idx
if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#services[@]}" ]; then
  echo "[ERROR] 无效选择！请输入 1-${#services[@]} 之间的数字。"
  exit 1
fi

selected_service=${services[$((idx-1))]}
echo "正在部署服务：$selected_service"

# 根据选择部署指定的服务
case "$selected_service" in
  "watchtower")
    echo "部署 Watchtower - 自动更新容器"
    docker compose -f "$compose_file" up -d watchtower
    check_docker_command
    ;;
  "xui")
    echo "部署 XUI - 管理面板"
    docker compose -f "$compose_file" up -d xui
    check_docker_command
    ;;
  "nginx")
    echo "部署 Nginx Proxy Manager"
    docker compose -f "$compose_file" up -d nginx
    check_docker_command
    ;;
  "vaultwarden")
    echo "部署 Vaultwarden - 密码管理"
    docker compose -f "$compose_file" up -d vaultwarden
    check_docker_command
    ;;
  "portainer")
    echo "部署 Portainer - Docker 管理面板"
    docker compose -f "$compose_file" up -d portainer
    check_docker_command
    ;;
  *)
    echo "[ERROR] 无效服务选择！"
    exit 1
    ;;
esac

# 额外步骤：确保虚拟网络和卷已经创建
echo "确保虚拟网络和卷已经创建..."

# 检查并删除冲突的网络 (mintcat)
existing_networks=$(docker network ls --filter "name=mintcat" -q)
if [ -n "$existing_networks" ]; then
  echo "检测到冲突网络 mintcat，正在删除..."
  # 停止并断开所有与该网络相关的容器
  containers=$(docker network inspect mintcat -f '{{range .Containers}}{{.Name}} {{end}}')
  for container in $containers; do
    docker network disconnect mintcat $container
    check_docker_command
  done
  # 尝试删除该网络，忽略错误
  docker network rm mintcat >/dev/null 2>&1
  check_docker_command || true # 删除网络失败不影响主流程，忽略错误
  echo "冲突网络 mintcat 已删除。"
fi

# 创建 mintcat 网络
create_docker_network "mintcat"

# 创建卷
echo "确保 Docker 卷已创建..."
for volume in "${volumes[@]}"; do
  create_docker_volume "$volume"
done

echo "服务部署完成！"

# 更新 docker-compose.yml 配置文件
cat <<EOF > "$compose_file"
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

  # Portainer - Docker 管理面板
  portainer:
    image: portainer/portainer-ce
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"
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
  xui_db: {}
  xui_cert: {}
  nginx_data: {}
  letsencrypt: {}
  vaultwarden_data: {}
  portainer_data: {}
EOF

echo "docker-compose.yml 配置文件已生成并更新！"
echo "请使用 'docker compose -f $(dirname "$0")/../docker-compose.yml up -d' 命令启动所有服务。"
