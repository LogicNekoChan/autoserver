#!/usr/bin/env bash
# ------------------------------------------------------------------
# backup.sh  ——  容器备份模块（bind / volume 自动识别，多挂载统一打包）
# ------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# -------------- 可外部覆盖的环境变量 ------------------------------
BACKUP_DIR="${BACKUP_DIR:-/root/backup}"
LOG_FILE="${LOG_FILE:-/root/autoserver.log}"
TMP_TAR_DIR="${TMP_TAR_DIR:-/tmp/docker_backup}"   # 临时放 volume tar 文件

# -------------- 工具函数 ------------------------------------------
log()  { printf '%s - %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE" >/dev/null; }
die()  { log "[ERROR] $*"; printf '[!] %s\n' "$*" >&2; exit 1; }

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# -------------- 主逻辑 -------------------------------------------
backup_container() {
    local running
    mapfile -t running < <(docker ps --format '{{.Names}}')
    ((${#running[@]})) || die "当前没有运行中的容器"

    echo "===== 运行中的容器 ====="
    local container
    select container in "${running[@]}"; do
        [[ -n $container ]] && break
    done

    # 时间戳 & 备份目录
    local ts="${container}_$(date +%Y%m%d-%H%M%S)"
    local dest="$BACKUP_DIR/$ts"
    mkdir -p "$dest" "$TMP_TAR_DIR" || die "无法创建目录 $dest 或 $TMP_TAR_DIR"
    log "开始备份容器 $container → $dest"

    # 收集挂载信息
    local bind_mounts volumes
    mapfile -t bind_mounts < <(docker inspect "$container" --format \
        '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{end}}{{end}}')
    mapfile -t volumes < <(docker inspect "$container" --format \
        '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}:{{.Destination}}{{end}}{{end}}')

    ((${#bind_mounts[@]} + ${#volumes[@]})) || die "容器 $container 既无 bind 挂载也无 volume，无需备份"

    local ok=0 fail=0 total=$(( ${#bind_mounts[@]} + ${#volumes[@]} ))

    # ---------- 1. 处理 bind 挂载（直接 tar 宿主目录） --------------
    for m in "${bind_mounts[@]}"; do
        local src="${m%%:*}" dst="${m##*:}"
        [[ -d $src ]] || { log "跳过不存在的 bind 目录：$src"; ((fail++)); continue; }

        local arc="$dest/bind_$(basename "$dst").tar.gz"
        printf '  [%2d/%d] bind %s ... ' $((ok+fail+1)) "$total"
        if tar -czf "$arc" -C "$src" . 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"; ((ok++))
        else
            echo -e "${RED}FAIL${NC}"; log "打包失败：$src"; ((fail++))
        fi
    done

    # ---------- 2. 处理 volume 挂载（用临时容器读卷） --------------
    for v in "${volumes[@]}"; do
        local vol_name="${v%%:*}" vol_dst="${v##*:}"
        local arc="$dest/volume_${vol_name}.tar.gz"
        printf '  [%2d/%d] volume %s ... ' $((ok+fail+1)) "$total"
        if docker run --rm \
               -v "$vol_name:/from_vol:ro" \
               -v "$TMP_TAR_DIR:/to_host" \
               alpine:latest \
               tar -czf "/to_host/${vol_name}.tar.gz" -C /from_vol . 2>/dev/null; then
            mv "$TMP_TAR_DIR/${vol_name}.tar.gz" "$arc"
            echo -e "${GREEN}OK${NC}"; ((ok++))
        else
            echo -e "${RED}FAIL${NC}"; log "打包失败：volume $vol_name"; ((fail++))
        fi
    done

    # 清理临时目录
    rm -rf "$TMP_TAR_DIR" >/dev/null 2>&1 || true

    log "备份完成：$dest （成功 $ok / 失败 $fail）"
    echo -e "\n[${GREEN}√${NC}] 结果保存在：$dest"
}

# ------------------ 入口检查 -------------------------------------
[[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行"
command -v docker >/dev/null || die "Docker 未安装或未启动"
[[ -d "$BACKUP_DIR" ]] || mkdir -p "$BACKUP_DIR"

backup_container
