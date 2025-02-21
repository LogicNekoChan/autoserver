#!/bin/bash
# 服务选择部署模块

# 假设 docker-compose.yml 文件位于项目根目录
COMPOSE_FILE="$(dirname "$0")/../docker-compose.yml"

if [ ! -f "$COMPOSE_FILE" ]; then
    echo "[ERROR] docker-compose.yml 文件不存在！"
    exit 1
fi

# 解析 docker-compose.yml 中的 services（简单处理，仅适用于标准格式）
services=($(grep "^[[:space:]]\{2,\}[a-zA-Z0-9_-]*:" "$COMPOSE_FILE" | sed 's/://g' | sed 's/^[ \t]*//'))
if [ ${#services[@]} -eq 0 ]; then
    echo "[ERROR] 未检测到服务配置，请检查 docker-compose.yml 格式！"
    exit 1
fi

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
docker-compose -f "$COMPOSE_FILE" up -d "$selected_service"
