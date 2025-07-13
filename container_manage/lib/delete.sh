#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${LOG_FILE:-/root/autoserver.log}"

log() {
    echo "$(date '+%F %T') - $1" | tee -a "$LOG_FILE" >/dev/null
}
die() { log "[ERROR] $1"; echo "[!] $1" >&2; exit 1; }

# 停止并删除容器
graceful_stop() {
    local cid=$1
    log "停止容器: $cid"
    docker stop "$cid" >/dev/null 2>&1 || docker kill "$cid" >/dev/null || die "无法停止 $cid"
}

# 清理 bind mount 目录
safe_clean_mounts() {
    local cid=$1
    local mounts
    mapfile -t mounts < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{end}}{{end}}' "$cid")
    for m in "${mounts[@]}"; do
        [[ -d $m ]] || continue
        if mountpoint -q "$m"; then umount "$m" 2>/dev/null || log "无法卸载: $m"; fi
        rm -rf "$m" && log "已清理目录: $m" || log "警告: 无法删除 $m"
    done
}

# 主流程
delete_system() {
    local containers=($(docker ps -a --format '{{.Names}}'))
    [[ ${#containers[@]} -eq 0 ]] && die "没有可删除的容器"

    echo "选择要删除的容器："
    for i in "${!containers[@]}"; do
        printf "%3d) %s\n" $((i+1)) "${containers[i]}"
    done

    local choice
    read -rp "请输入编号 [1-${#containers[@]}]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#containers[@]} )) || die "无效编号"
    local target="${containers[$((choice-1))]}"

    read -rp "确认删除 $target 及其所有数据？[y/N] " confirm
    [[ $confirm =~ ^[Yy]$ ]] || { echo "已取消"; return; }

    graceful_stop "$target"
    safe_clean_mounts "$target"
    docker rm -f "$target" >/dev/null && log "已删除容器: $target" && echo -e "\n[√] 删除成功"
}

# 直接执行入口
[[ "${BASH_SOURCE[0]}" == "${0}" ]] && {
    [[ $(id -u) -eq 0 ]] || die "请使用 root 运行"
    command -v docker &>/dev/null || die "请先安装并启动 Docker"
    delete_system
}
