#!/usr/bin/env bash
# ------------------------------------------------------------------
# backup.sh  ——  容器备份模块（零依赖，独立可运行）
# ------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# 环境变量可覆盖
BACKUP_DIR="${BACKUP_DIR:-/root/backup}"
LOG_FILE="${LOG_FILE:-/root/autoserver.log}"

log()  { printf '%s - %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE" >/dev/null; }
die()  { log "[ERROR] $*"; printf '[!] %s\n' "$*" >&2; exit 1; }

# -------------------------------------------------
# 主函数
# -------------------------------------------------
backup_system() {
    local running=($(docker ps --format '{{.Names}}'))
    (( ${#running[@]} )) || die "当前没有运行中的容器"

    echo "===== 运行中的容器 ====="
    select container in "${running[@]}"; do
        [[ -n $container ]] && break
    done

    # 仅处理 bind 挂载
    local mounts=($(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{end}}{{end}}' "$container"))
    (( ${#mounts[@]} )) || die "容器 $container 没有 bind 挂载，无需备份"

    local ts="${container}_$(date +%Y%m%d-%H%M%S)"
    local dest="$BACKUP_DIR/$ts"
    mkdir -p "$dest" || die "无法创建目录 $dest"

    log "开始备份 $container → $dest"

    local ok=0 fail=0
    for m in "${mounts[@]}"; do
        local src="${m%%:*}"
        local dst="${m##*:}"
        local arc="$dest/$(basename "$dst").tar.gz"

        printf '  [%2d/%d] %s ... ' $((++ok+fail)) ${#mounts[@]}
        if tar -czf "$arc" -C "$(dirname "$src")" "$(basename "$src")" 2>/dev/null; then
            echo -e '\e[32mOK\e[0m'
            ((ok++))
        else
            echo -e '\e[31mFAIL\e[0m'
            log "打包失败：$src"
            ((fail++))
        fi
    done

    log "备份完成：$dest （成功 $ok / 失败 $fail）"
    echo -e "\n[√] 结果保存在：$dest"
}

# -------------------------------------------------
# 入口
# -------------------------------------------------
[[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行"
command -v docker >/dev/null || die "Docker 未安装或未启动"
[[ -d "$BACKUP_DIR" ]] || mkdir -p "$BACKUP_DIR"

backup_system
