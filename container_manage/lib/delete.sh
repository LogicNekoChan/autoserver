#!/usr/bin/env bash
set -euo pipefail

# ---------- 基础工具 ----------
log() { printf '[%(%F %T)T] %s\n' -1 "$*"; }
die()  { log "ERROR: $*" >&2; exit 1; }

# ---------- Docker 通用 ----------
graceful_stop() {
    local cid=$1
    log "停止容器: $cid"
    docker stop "$cid" >/dev/null 2>&1 || docker kill "$cid" >/dev/null || \
        die "无法停止容器 $cid"
}

container_exists() {
    docker inspect "$1" &>/dev/null
}

# ---------- 清理 bind-mount ----------
is_bind_readonly() {
    local cid=$1 m=$2
    docker inspect --format \
        '{{range .Mounts}}{{if and (eq .Type "bind") (eq .Source "'"$m"'")}}{{.RW}}{{end}}{{end}}' \
        "$cid" | grep -q false
}

safe_clean_bind_mounts() {
    local cid=$1
    local -a mounts
    readarray -t mounts < <(
        docker inspect --format \
            '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{end}}{{end}}' "$cid"
    )

    [[ ${#mounts[@]} -eq 0 ]] && { log "容器 $cid 无 bind-mount"; return 0; }

    for m in "${mounts[@]}"; do
        [[ -d $m ]] || { log "跳过不存在目录: $m"; continue; }

        # 如果目录是只读挂载，直接跳过，防止误删
        if is_bind_readonly "$cid" "$m"; then
            log "跳过只读挂载: $m"
            continue
        fi

        log "准备卸载并删除目录: $m"
        if mountpoint -q "$m"; then
            umount "$m" 2>/dev/null || log "警告: 无法卸载 $m"
        fi
        rm -rf "$m" && log "已清理目录: $m" || log "警告: 无法删除 $m"
    done
}

# ---------- 清理命名卷 ----------
delete_named_volumes() {
    local cid=$1
    local -a volumes
    readarray -t volumes < <(
        docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$cid"
    )

    [[ ${#volumes[@]} -eq 0 ]] && { log "容器 $cid 无命名卷"; return 0; }

    for v in "${volumes[@]}"; do
        [[ -n $v ]] || continue
        if docker volume rm "$v" &>/dev/null; then
            log "已删除卷: $v"
        else
            log "卷 $v 仍被占用，跳过"
        fi
    done
}

# ---------- 主流程 ----------
delete_system() {
    local -a containers
    readarray -t containers < <(docker ps -a --format '{{.Names}}')
    [[ ${#containers[@]} -gt 0 ]] || die "没有可删除的容器"

    # 交互选择
    printf '选择要删除的容器：\n'
    for i in "${!containers[@]}"; do
        printf '%3d) %s\n' "$((i+1))" "${containers[i]}"
    done

    local choice target
    read -rp "请输入编号 [1-${#containers[@]}]: " choice
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#containers[@]} )) || \
        die "无效编号"

    target=${containers[$((choice-1))]}
    read -rp "确认删除容器 $target 及其所有 bind-mount 与命名卷？[y/N] " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { echo "已取消"; return 0; }

    container_exists "$target" || die "容器不存在: $target"

    graceful_stop "$target"
    safe_clean_bind_mounts "$target"
    delete_named_volumes "$target"
    docker rm -f "$target" >/dev/null && log "已删除容器: $target"
    echo -e "\n[√] 删除成功"
}

# ---------- 入口 ----------
delete_system "$@"
