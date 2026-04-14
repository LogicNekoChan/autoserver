#!/usr/bin/env bash
# ------------------------------------------------------------------
# restore.sh  ——  容器数据恢复工具（与 backup.sh 完美配套）
# ------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# ===================== 配置项 =====================
readonly BACKUP_DIR="${BACKUP_DIR:-/root/backup}"
readonly LOG_FILE="${LOG_FILE:-/root/autoserver.log}"
readonly TMP_TAR_DIR="${TMP_TAR_DIR:-/tmp/docker_restore}"
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

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; log "[FATAL] $*"; exit 1; }

# ===================== 检查依赖 =====================
check_requirements() {
    [[ $(id -u) -eq 0 ]] || die "请使用 root 权限运行"
    command -v docker &>/dev/null || die "Docker 未安装"
    docker info &>/dev/null || die "Docker 未运行"
    [[ -d "$BACKUP_DIR" ]] || die "备份目录不存在：$BACKUP_DIR"
}

# ===================== 选择备份集 =====================
select_backup() {
    mapfile -t backups < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)
    ((${#backups[@]})) || die "无可用备份"

    echo -e "\n===== ${GREEN}可用备份集${NC} ====="
    local idx
    for idx in "${!backups[@]}"; do
        printf "%3d) %s\n" $((idx+1)) "$(basename "${backups[idx]}")"
    done

    local choice
    read -rp "请选择备份编号 [1-${#backups[@]}]: " choice
    [[ $choice =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#backups[@]} ]] || die "无效编号"

    echo "${backups[$((choice-1))]}"
}

# ===================== 获取容器挂载 =====================
get_container_mounts_dict() {
    local container="$1" type="$2"
    docker inspect "$container" --format \
        '{{range .Mounts}}{{if eq .Type "'"${type}"'"}}{{if eq .Type "volume"}}{{.Name}}{{else}}{{.Source}}{{end}}:{{.Destination}}{{end}}{{end}}'
}

# ===================== 恢复 bind 挂载 =====================
restore_bind() {
    local dst="$1" host_path="$2" arc="$3" total="$4" curr="$5"
    [[ -f "$arc" ]] || { warn "无备份文件，跳过：$arc"; return 1; }

    printf "  [%2d/%d] 恢复 bind → %s ... " "$curr" "$total" "$dst"
    rm -rf "$host_path" && mkdir -p "$host_path"

    if tar -xzf "$arc" -C "$host_path" &>/dev/null; then
        echo -e "${GREEN}OK${NC}"; return 0
    else
        echo -e "${RED}FAIL${NC}"; log "bind 恢复失败：$dst"; return 1
    fi
}

# ===================== 恢复 volume 挂载 =====================
restore_volume() {
    local vol_name="$1" arc="$2" total="$3" curr="$4"
    [[ -f "$arc" ]] || { warn "无备份文件，跳过：$arc"; return 1; }

    printf "  [%2d/%d] 恢复 volume → %s ... " "$curr" "$total" "$vol_name"
    cp -f "$arc" "$TMP_TAR_DIR/${vol_name}.tar.gz"

    if docker run --rm \
        -v "${vol_name}:/to_vol" \
        -v "${TMP_TAR_DIR}:/from_host:ro" \
        "$ALPINE_IMAGE" \
        sh -c "rm -rf /to_vol/* 2>/dev/null || true; tar -xzf /from_host/${vol_name}.tar.gz -C /to_vol"; then
        echo -e "${GREEN}OK${NC}"; return 0
    else
        echo -e "${RED}FAIL${NC}"; log "volume 恢复失败：$vol_name"; return 1
    fi
}

# ===================== 主恢复流程 =====================
restore_system() {
    local backup_path
    backup_path=$(select_backup)
    local backup_name
    backup_name=$(basename "$backup_path")
    local container_name="${backup_name%%_*}"

    info "选择备份：$backup_name"
    info "解析容器名：$container_name"

    # 查找目标容器
    mapfile -t candidates < <(docker ps -a --format '{{.Names}}' | grep -x "$container_name")
    ((${#candidates[@]})) || die "未找到容器：$container_name"
    local target="${candidates[0]}"

    # 获取挂载
    declare -A bind_map vol_map
    while IFS=: read -r src dst; do
        [[ -n $src && -n $dst ]] && bind_map["$dst"]="$src"
    done < <(get_container_mounts_dict "$target" "bind")

    while IFS=: read -r vol_name dst; do
        [[ -n $vol_name && -n $dst ]] && vol_map["$dst"]="$vol_name"
    done < <(get_container_mounts_dict "$target" "volume")

    local total=$(( ${#bind_map[@]} + ${#vol_map[@]} ))
    [[ $total -eq 0 ]] && die "容器无挂载，无需恢复"

    # 停止容器
    warn "停止容器：$target"
    docker stop "$target" &>/dev/null || die "无法停止容器"

    mkdir -p "$TMP_TAR_DIR"
    local ok=0 fail=0 curr=0

    # 恢复 bind
    for dst in "${!bind_map[@]}"; do
        ((curr++))
        local host_path="${bind_map[$dst]}"
        local arc="$backup_path/bind_$(basename "$dst").tar.gz"
        if restore_bind "$dst" "$host_path" "$arc" "$total" "$curr"; then
            ((ok++))
        else
            ((fail++))
        fi
    done

    # 恢复 volume
    for dst in "${!vol_map[@]}"; do
        ((curr++))
        local vol_name="${vol_map[$dst]}"
        local arc="$backup_path/volume_${vol_name}.tar.gz"
        if restore_volume "$vol_name" "$arc" "$total" "$curr"; then
            ((ok++))
        else
            ((fail++))
        fi
    done

    # 清理
    rm -rf "$TMP_TAR_DIR" &>/dev/null || true

    # 启动容器
    info "启动容器：$target"
    docker start "$target" &>/dev/null || die "启动失败"

    log "恢复完成：成功 $ok | 失败 $fail"
    echo -e "\n${GREEN}✅ 恢复完成！${NC}"
    echo -e "📦 容器：$target"
    echo -e "✅ 成功：$ok  |  ❌ 失败：$fail"
}

# ===================== 入口 =====================
main() {
    check_requirements
    restore_system
}

main
