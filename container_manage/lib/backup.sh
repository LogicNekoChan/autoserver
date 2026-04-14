#!/usr/bin/env bash
# ------------------------------------------------------------------
# backup.sh  ——  Docker 容器备份工具（bind/volume 自动识别）
# ------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# ===================== 配置项 =====================
readonly BACKUP_DIR="${BACKUP_DIR:-/root/backup}"
readonly LOG_FILE="${LOG_FILE:-/root/autoserver.log}"
readonly TMP_TAR_DIR="${TMP_TAR_DIR:-/tmp/docker_backup}"
readonly ALPINE_IMAGE="alpine:latest"

# ===================== 颜色与日志 =====================
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log() {
    local timestamp
    timestamp=$(date '+%F %T')
    printf "%s - %s\n" "$timestamp" "$*" | tee -a "$LOG_FILE"
}

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()  { err "$*"; log "[FATAL] $*"; exit 1; }

# ===================== 检查依赖 =====================
check_requirements() {
    [[ $(id -u) -eq 0 ]] || die "请使用 root 权限运行"
    command -v docker &>/dev/null || die "Docker 未安装或未在 PATH 中"
    docker info &>/dev/null || die "Docker 服务未运行"
    mkdir -p "$BACKUP_DIR" || die "无法创建备份目录"
}

# ===================== 获取运行中容器 =====================
select_running_container() {
    mapfile -t running < <(docker ps --format '{{.Names}}' | sort)
    ((${#running[@]})) || die "没有运行中的容器"

    echo -e "\n===== ${GREEN}运行中的容器${NC} ====="
    select container in "${running[@]}"; do
        [[ -n $container ]] && break
        warn "请输入有效数字"
    done
}

# ===================== 获取容器挂载 =====================
get_container_mounts() {
    local container="$1"
    local type="$2"
    docker inspect "$container" --format \
        '{{range .Mounts}}{{if eq .Type "'"${type}"'"}}{{.Source}}:{{.Destination}}{{end}}{{end}}'
}

# ===================== 备份 bind 挂载 =====================
backup_bind() {
    local src="$1" dst="$2" dest_dir="$3" total="$4" curr="$5"
    [[ -d $src ]] || { warn "bind 目录不存在，跳过：$src"; return 1; }

    local arc="${dest_dir}/bind_$(basename "${dst}").tar.gz"
    printf "  [%2d/%d] bind: %s ... " "$curr" "$total" "$src"

    if tar -czf "$arc" -C "$src" . --warning=no-file-changed; then
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        log "bind 备份失败：$src"
        return 1
    fi
}

# ===================== 备份 volume 挂载 =====================
backup_volume() {
    local vol_name="$1" dest_dir="$2" total="$3" curr="$4"
    local tmp_tar="${TMP_TAR_DIR}/${vol_name}.tar.gz"
    local final_arc="${dest_dir}/volume_${vol_name}.tar.gz"

    printf "  [%2d/%d] volume: %s ... " "$curr" "$total" "$vol_name"

    if docker run --rm \
        -v "${vol_name}:/from_vol:ro" \
        -v "${TMP_TAR_DIR}:/to_host" \
        "$ALPINE_IMAGE" \
        tar -czf "/to_host/${vol_name}.tar.gz" -C /from_vol .; then
        mv "$tmp_tar" "$final_arc"
        echo -e "${GREEN}OK${NC}"
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        log "volume 备份失败：$vol_name"
        return 1
    fi
}

# ===================== 主备份流程 =====================
backup_container() {
    local container="$1"
    local ts="${container}_$(date +%Y%m%d-%H%M%S)"
    local dest="${BACKUP_DIR}/${ts}"

    mkdir -p "$dest" "$TMP_TAR_DIR"
    log "开始备份容器：$container → $dest"
    info "备份目标：$dest"

    # 获取挂载
    mapfile -t bind_mounts < <(get_container_mounts "$container" "bind")
    mapfile -t volumes < <(get_container_mounts "$container" "volume")

    local total=$(( ${#bind_mounts[@]} + ${#volumes[@]} ))
    [[ $total -eq 0 ]] && die "容器无任何挂载，无需备份"

    local ok=0 fail=0 curr=0

    # 备份 bind
    for m in "${bind_mounts[@]}"; do
        ((curr++))
        local src="${m%%:*}" dst="${m##*:}"
        if backup_bind "$src" "$dst" "$dest" "$total" "$curr"; then
            ((ok++))
        else
            ((fail++))
        fi
    done

    # 备份 volume
    for v in "${volumes[@]}"; do
        ((curr++))
        local vol_name="${v%%:*}"
        if backup_volume "$vol_name" "$dest" "$total" "$curr"; then
            ((ok++))
        else
            ((fail++))
        fi
    done

    # 清理
    rm -rf "$TMP_TAR_DIR" &>/dev/null || true

    log "备份完成：成功 $ok 个，失败 $fail 个"
    echo -e "\n${GREEN}✅ 备份完成！${NC}"
    echo -e "📂 路径：${GREEN}${dest}${NC}"
    echo -e "✅ 成功：${ok}  |  ❌ 失败：${fail}\n"
}

# ===================== 入口 =====================
main() {
    check_requirements
    select_running_container
    backup_container "$container"
}

main
