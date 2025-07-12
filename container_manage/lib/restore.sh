#!/usr/bin/env bash
# ------------------------------------------------------------------
# restore.sh  ——  容器数据恢复模块（独立可运行）
# ------------------------------------------------------------------
set -euo pipefail

# 若未定义则给默认值
BACKUP_DIR="${BACKUP_DIR:-/root/backup}"
LOG_FILE="${LOG_FILE:-/root/autoserver.log}"

log() {
    local msg="$1"
    echo "$(date '+%F %T') - $msg" | tee -a "$LOG_FILE" >/dev/null
}
die() { log "[ERROR] $*"; echo "[!] $*" >&2; exit 1; }

# ----------------------------------------------
# 主恢复流程
# ----------------------------------------------
restore_system() {
    # ---------- 选择备份集 ----------
    local backups=($(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r))
    [[ ${#backups[@]} -eq 0 ]] && die "在 $BACKUP_DIR 中未找到备份集"

    echo "选择要恢复的备份集："
    local idx
    for idx in "${!backups[@]}"; do
        printf "%3d) %s\n" $((idx+1)) "$(basename "${backups[idx]}")"
    done
    local choice
    read -rp "请输入编号 [1-${#backups[@]}]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#backups[@]} )) || die "无效编号"
    local backup_path="${backups[$((choice-1))]}"

    # ---------- 解析容器名 ----------
    local container_name
    container_name="$(basename "$backup_path" | cut -d_ -f1)"
    [[ -z $container_name ]] && die "无法从备份目录名解析容器名"

    # ---------- 选择目标容器 ----------
    local candidates=($(docker ps -a --filter "name=^${container_name}$" --format '{{.Names}}'))
    [[ ${#candidates[@]} -eq 0 ]] && die "找不到名为 $container_name 的容器"

    # 如果同名容器只有一个，自动选中；多个则让用户选
    local target
    if [[ ${#candidates[@]} -eq 1 ]]; then
        target="${candidates[0]}"
    else
        echo "找到多个同名容器："
        for idx in "${!candidates[@]}"; do
            printf "%3d) %s\n" $((idx+1)) "${candidates[idx]}"
        done
        read -rp "请选择要恢复的容器 [1-${#candidates[@]}]: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )) || die "无效编号"
        target="${candidates[$((choice-1))]}"
    fi

    # ---------- 检查备份文件 ----------
    local backup_files=("$backup_path"/*.tar.gz)
    [[ ${#backup_files[@]} -eq 0 ]] && die "备份集中未找到 .tar.gz 文件"

    # ---------- 停止容器 ----------
    log "停止容器 $target"
    docker stop "$target" >/dev/null || die "无法停止容器 $target"

    # ---------- 解压并覆盖挂载卷 ----------
    local mounts=($(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{printf "\n"}}{{end}}{{end}}' "$target"))
    for m in "${mounts[@]}"; do
        local host_path="${m%%:*}"
        local dst_path="${m##*:}"
        local archive="$backup_path/$(basename "$dst_path").tar.gz"
        [[ -f $archive ]] || { log "跳过：未找到备份文件 $(basename "$archive")"; continue; }

        log "恢复 $archive → $host_path"
        rm -rf "$host_path"   # 先清空旧数据，避免残留
        mkdir -p "$(dirname "$host_path")"
        tar -xzf "$archive" -C "$(dirname "$host_path")" || die "解压失败：$archive"
    done

    # ---------- 启动容器 ----------
    log "启动容器 $target"
    docker start "$target" >/dev/null || die "启动失败"

    log "恢复完成"
    echo -e "\n[√] 容器 $target 数据已恢复"
}

# -------------------------------------------------
# 直接执行时入口
# -------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行"
    command -v docker &>/dev/null || die "请先安装并启动 Docker"
    [[ -d "$BACKUP_DIR" ]] || die "备份目录 $BACKUP_DIR 不存在"
    restore_system
fi
