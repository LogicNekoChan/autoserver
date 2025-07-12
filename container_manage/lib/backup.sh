#!/usr/bin/env bash
# ------------------------------------------------------------------
# backup.sh  ——  容器备份模块（零依赖，独立可运行）
# ------------------------------------------------------------------
set -euo pipefail

# 若尚未定义，则给出默认值（独立运行时也能工作）
BACKUP_DIR="${BACKUP_DIR:-/root/backup}"
LOG_FILE="${LOG_FILE:-/root/autoserver.log}"

# 简单的日志函数（避免依赖外部 logger）
log() {
    local msg="$1"
    echo "$(date '+%F %T') - $msg" | tee -a "$LOG_FILE" >/dev/null
}

# 通用错误处理
die() { log "[ERROR] $*"; echo "[!] $*" >&2; exit 1; }

# ----------------------------------------------
# 备份指定容器
# ----------------------------------------------
backup_system() {
    local running_containers=($(docker ps --format '{{.Names}}'))
    [[ ${#running_containers[@]} -eq 0 ]] && die "当前没有运行中的容器"

    # ---------- 选择容器 ----------
    echo "选择要备份的容器："
    local idx
    for idx in "${!running_containers[@]}"; do
        printf "%3d) %s\n" $((idx+1)) "${running_containers[idx]}"
    done

    local choice
    read -rp "请输入编号 [1-${#running_containers[@]}]: " choice
    [[ "$choice" =~ ^[0-9]+$ ]] \
        && (( choice >= 1 && choice <= ${#running_containers[@]} )) \
        || die "无效编号"
    local container="${running_containers[$((choice-1))]}"

    # ---------- 获取挂载卷 ----------
    # 格式：每行一个 源路径:容器内路径
    mapfile -t mounts < <(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{printf "\n"}}{{end}}{{end}}' "$container")
    [[ ${#mounts[@]} -eq 0 ]] && die "容器 $container 没有绑定挂载卷，无需备份"

    # ---------- 创建备份目录 ----------
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    local backup_path="${BACKUP_DIR}/${container}_${ts}"
    mkdir -p "$backup_path" || die "无法创建备份目录 $backup_path"
    log "开始备份容器 $container → $backup_path"

    # ---------- 开始打包 ----------
    local total=${#mounts[@]} count=0
    for m in "${mounts[@]}"; do
        local src="${m%%:*}"          # 宿主机路径
        local dst="${m##*:}"          # 容器内路径
        local archive="${backup_path}/$(basename "$dst").tar.gz"

        log "[$((++count))/$total] 打包 $src → ${archive##*/}"
        tar -czf "$archive" -C "$(dirname "$src")" "$(basename "$src")" \
            || die "打包失败：$src"
    done

    log "备份完成：$backup_path"
    echo -e "\n[√] 备份成功，路径：$backup_path"
}

# -------------------------------------------------
# 如果直接执行本脚本（而非被 source），则自动调用
# -------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    [[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行"
    command -v docker &>/dev/null || die "请先安装并启动 Docker"
    [[ -d "$BACKUP_DIR" ]] || mkdir -p "$BACKUP_DIR"
    backup_system
fi
