#!/usr/bin/env bash
# ------------------------------------------------------------------
# delete.sh  ——  安全删除容器 + 自动清理 bind/volume 挂载
# 与 backup.sh / restore.sh 配套使用
# ------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# ----------- 可外部覆盖的环境变量 -------------------------------
AUTO_BIND_PREFIX="${AUTO_BIND_PREFIX:-/var/lib/docker:/data/docker:/srv/docker}"
KEEP_IMAGE="${KEEP_IMAGE:-yes}"          # 删除容器后是否保留镜像

# ----------- 工具函数 -------------------------------------------
log()  { printf '[%(%F %T)T] %s\n' -1 "$*"; }
warn() { printf '%b[WARNING]%b %s\n' '\033[33m' '\033[0m' "$*" >&2; }
die()  { printf '%b[ERROR]%b %s\n' '\033[31m' '\033[0m' "$*" >&2; exit 1; }

color_print() {
    local color=$1; shift
    printf "%b%s%b\n" "$color" "$*" '\033[0m'
}
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[0;33m'

# ----------- Docker 通用 ----------------------------------------
graceful_stop() {
    local cid=$1
    log "停止容器: $cid"
    docker stop "$cid" >/dev/null 2>&1 || docker kill "$cid" >/dev/null 2>&1 || \
        die "无法停止容器 $cid"
}

container_exists() {
    docker inspect "$1" &>/dev/null
}

# ----------- bind 挂载处理 --------------------------------------
# 判断路径是否在「可信任自动目录」内
is_auto_bind() {
    local path=$1
    local IFS=:
    for prefix in $AUTO_BIND_PREFIX; do
        [[ $path == "$prefix"* ]] && return 0
    done
    return 1
}

# 判断 bind 是否只读
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
        docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{end}}{{end}}' "$cid"
    )
    [[ ${#mounts[@]} -eq 0 ]] && { log "容器 $cid 无 bind-mount"; return 0; }

    for m in "${mounts[@]}"; do
        [[ -d $m ]] || { warn "目录不存在，跳过: $m"; continue; }

        # 只读挂载跳过
        if is_bind_readonly "$cid" "$m"; then
            warn "跳过只读挂载: $m"; continue
        fi

        # 非自动目录跳过
        if ! is_auto_bind "$m"; then
            warn "跳过非自动目录（请手动处理）: $m"; continue
        fi

        color_print "$YELLOW" "准备卸载并删除目录: $m"
        if mountpoint -q "$m"; then
            umount "$m" 2>/dev/null || warn "无法卸载 $m"
        fi
        rm -rf "$m" && log "已清理目录: $m" || warn "删除失败: $m"
    done
}

# ----------- volume 挂载处理 ------------------------------------
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
            warn "卷 $v 仍被占用或不存在，跳过"
        fi
    done
}

# ----------- 主流程 ---------------------------------------------
delete_system() {
    local -a containers
    readarray -t containers < <(docker ps -a --format '{{.Names}}')
    ((${#containers[@]})) || die "没有可删除的容器"

    color_print "$GREEN" "=== 选择要删除的容器 ==="
    for i in "${!containers[@]}"; do
        printf '%3d) %s\n' "$((i+1))" "${containers[i]}"
    done

    local choice target
    read -rp "请输入编号 [1-${#containers[@]}]: " choice
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#containers[@]} )) || \
        die "无效编号"

    target=${containers[$((choice-1))]}
    container_exists "$target" || die "容器不存在: $target"

    # 预扫描挂载，给用户二次确认
    local -a bind_mounts volumes
    readarray -t bind_mounts < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}{{end}}{{end}}' "$target")
    readarray -t volumes < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{end}}{{end}}' "$target")

    color_print "$YELLOW" "\n即将删除容器: $target"
    [[ ${#bind_mounts[@]} -gt 0 ]] && {
        echo "关联的 bind 挂载目录（仅自动目录会被删除）:"
        for m in "${bind_mounts[@]}"; do
            is_auto_bind "$m" && echo "  - $m ✔" || echo "  - $m (手动)"
        done
    }
    [[ ${#volumes[@]} -gt 0 ]] && {
        echo "关联的命名卷:"
        printf '  - %s\n' "${volumes[@]}"
    }
    read -rp $'\n确认删除容器及上述资源？[y/N] ' confirm
    [[ $confirm =~ ^[Yy]$ ]] || { echo "已取消"; return 0; }

    graceful_stop "$target"
    safe_clean_bind_mounts   "$target"
    delete_named_volumes     "$target"

    docker rm -f "$target" >/dev/null && log "已删除容器: $target"
    [[ $KEEP_IMAGE == "no" ]] && {
        docker image prune -f &>/dev/null && log "已清理无用镜像"
    }

    color_print "$GREEN" "\n[√] 删除成功"
}

# ------------------ 入口 ------------------------------------------
[[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行"
command -v docker >/dev/null || die "Docker 未安装或未启动"

delete_system "$@"
