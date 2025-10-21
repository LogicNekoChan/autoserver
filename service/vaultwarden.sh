#!/usr/bin/env bash
set -euo pipefail

#----------- 可配置区 --------------
CT_NAME="vaultwarden"
VOL_NAME="vw_data"          # 命名卷名称
BIND_SRC=""                 # 想改用 bind 挂载时填宿主机路径，例如 /mnt/disk/vw
MOUNT_POINT="/data"         # 容器内挂载点
#-----------------------------------

# 删除容器（如有）
docker rm -f "$CT_NAME" &>/dev/null || true

# 如果本次想用「命名卷」
if [[ -z "${BIND_SRC:-}" ]]; then
    # 如果之前有人用 bind 占过位，Docker 不会允许同名挂载点；
    # 这里先把同名卷删掉（数据会丢！如需保留请提前备份）
    docker volume ls -q | grep -qx "$VOL_NAME" && {
        echo "[WARN] 命名卷 $VOL_NAME 已存在，将先删除再重建"
        docker volume rm "$VOL_NAME" || true
    }
    docker volume create "$VOL_NAME" >/dev/null
    MOUNT_SPEC="$VOL_NAME:$MOUNT_POINT"
else
    # 想用 bind 挂载
    # 如果之前是命名卷，Docker 不允许同名挂载点，所以上面已把容器删了
    # 这里再确保宿主机目录存在
    mkdir -p "$BIND_SRC"
    MOUNT_SPEC="$BIND_SRC:$MOUNT_POINT"
fi

# 现在可以安全启动容器
docker run -d \
  --name "$CT_NAME" \
  --restart unless-stopped \
  -v "$MOUNT_SPEC" \
  vaultwarden/server:latest

echo "[√] 容器已启动，挂载方式：$MOUNT_SPEC"
