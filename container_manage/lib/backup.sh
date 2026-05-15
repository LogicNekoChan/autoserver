#!/usr/bin/env bash
# ------------------------------------------------------------------
# backup.sh —— 企业级 Docker 容器备份工具 (v2.0)
# ------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

# ===================== 配置项 =====================
readonly BACKUP_ROOT="${BACKUP_DIR:-/root/backup}"
readonly LOG_FILE="${LOG_FILE:-/root/autoserver.log}"
readonly ALPINE_IMAGE="alpine:3.18"
readonly RETENTION_DAYS=7  # 默认保留7天内的备份

# ===================== 颜色与日志 =====================
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() {
    local level="$1"; shift
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf "%s [%s] %s\n" "$timestamp" "$level" "$*" | tee -a "$LOG_FILE"
}

info() { log "INFO" "$*"; echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { log "WARN" "$*"; echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { log "ERROR" "$*"; echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

# ===================== 基础检查 =====================
check_env() {
    [[ $EUID -ne 0 ]] && die "必须以 root 权限运行"
    for cmd in docker tar date; do
        command -v "$cmd" &>/dev/null || die "缺少必要依赖: $cmd"
    done
    mkdir -p "$BACKUP_ROOT"
}

# ===================== 核心逻辑 =====================

# 获取容器挂载点详情 (JSON 处理比字符串截断更可靠)
get_mounts_json() {
    docker inspect "$1" --format '{{json .Mounts}}'
}

# 执行备份
backup_container() {
    local container="$1"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local dest_dir="${BACKUP_ROOT}/${container}_${timestamp}"
    local tmp_workdir
    tmp_workdir=$(mktemp -d -t docker_bak.XXXXXX)

    trap 'rm -rf "$tmp_workdir"; info "临时文件已清理"' EXIT

    info ">>> 开始备份容器: [$container] <<<"
    mkdir -p "$dest_dir"

    # 1. 导出容器元数据 (极其重要，用于恢复)
    info "正在导出容器配置元数据..."
    docker inspect "$container" > "${dest_dir}/metadata.json"

    # 2. 暂停容器以保证数据一致性 (可选)
    info "正在暂停容器以保证一致性..."
    docker pause "$container" >/dev/null

    # 3. 处理挂载点
    local mounts
    mounts=$(get_mounts_json "$container")
    
    # 使用 Python 或 jq 解析 JSON (这里假设环境简单，使用 native 循环)
    local count=0
    
    # 提取 Bind 挂载
    while read -r src dst; do
        [[ -z "$src" ]] && continue
        ((count++))
        printf "  [%d] 正在备份 Bind: %s -> %s\n" "$count" "$src" "$dst"
        tar -czf "${dest_dir}/bind_${count}.tar.gz" -C "$src" . 2>/dev/null || warn "部分文件读取受限: $src"
    done < <(echo "$mounts" | docker run --rm -i alpine sh -c "cat | tr ']' '\n' | grep '\"Type\":\"bind\"' | sed -n 's/.*\"Source\":\"\([^\"]*\)\".*\"Destination\":\"\([^\"]*\)\".*/\1 \2/p'")

    # 提取 Volume 挂载
    while read -r vol_name; do
        [[ -z "$vol_name" ]] && continue
        ((count++))
        printf "  [%s] 正在备份 Volume: %s\n" "$count" "$vol_name"
        docker run --rm \
            -v "${vol_name}:/data:ro" \
            -v "${dest_dir}:/backup" \
            "$ALPINE_IMAGE" \
            tar -czf "/backup/volume_${vol_name}.tar.gz" -C /data .
    done < <(echo "$mounts" | docker run --rm -i alpine sh -c "cat | tr ']' '\n' | grep '\"Type\":\"volume\"' | sed -n 's/.*\"Name\":\"\([^\"]*\)\".*/\1/p'")

    # 4. 恢复容器运行
    docker unpause "$container" >/dev/null
    info "容器已恢复运行"

    # 5. 最终打包归档并清理
    info "正在创建最终归档文件..."
    cd "$BACKUP_ROOT"
    tar -cf "${container}_${timestamp}.tar" "${container}_${timestamp}"
    rm -rf "${dest_dir}"
    
    info "✅ 备份成功: ${BACKUP_ROOT}/${container}_${timestamp}.tar"
}

# ===================== 清理旧备份 =====================
cleanup_old_backups() {
    info "正在清理 ${RETENTION_DAYS} 天前的旧备份..."
    find "$BACKUP_ROOT" -name "*.tar" -mtime +"$RETENTION_DAYS" -exec rm -f {} \;
}

# ===================== 主入口 =====================
main() {
    check_env
    
    mapfile -t containers < <(docker ps --format '{{.Names}}')
    
    if [[ ${#containers[@]} -eq 0 ]]; then
        die "当前没有正在运行的容器"
    fi

    echo -e "\n${BLUE}==== 可用容器列表 ====${NC}"
    select opt in "${containers[@]}" "退出备份"; do
        case "$opt" in
            "退出备份") exit 0 ;;
            "") warn "无效选择，请重新输入数字" ;;
            *) backup_container "$opt"; break ;;
        esac
    done

    cleanup_old_backups
}

main "$@"
