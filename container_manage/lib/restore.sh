#!/usr/bin/env bash
# ------------------------------------------------------------------
# restore.sh  ——  容器数据恢复模块（bind / volume 自动识别 & 多挂载一次恢复）
# ------------------------------------------------------------------
set -euo pipefail
IFS=$'\n\t'

BACKUP_DIR="${BACKUP_DIR:-/root/backup}"
LOG_FILE="${LOG_FILE:-/root/autoserver.log}"
TMP_TAR_DIR="${TMP_TAR_DIR:-/tmp/docker_restore}"

log() { printf '%s - %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE" >/dev/null; }
die() { log "[ERROR] $*"; printf '[!] %s\n' "$*" >&2; exit 1; }

readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# ------------------ 主恢复流程 ------------------------------------
restore_system() {
    # ---------- 选择备份集 ----------
    mapfile -t backups < <(find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d | sort -r)
    ((${#backups[@]})) || die "在 $BACKUP_DIR 中未找到备份集"

    echo "选择要恢复的备份集："
    local idx
    for idx in "${!backups[@]}"; do
        printf '%3d) %s\n' $((idx+1)) "$(basename "${backups[idx]}")"
    done
    local choice
    read -rp "请输入编号 [1-${#backups[@]}]: " choice
    [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#backups[@]} )) || die "无效编号"
    local backup_path="${backups[$((choice-1))]}"

    # ---------- 解析容器名 ----------
    local container_name
    container_name="$(basename "$backup_path" | cut -d_ -f1)"
    [[ -n $container_name ]] || die "无法从备份目录名解析容器名"

    # ---------- 选择目标容器 ----------
    mapfile -t candidates < <(docker ps -a --filter "name=^${container_name}$" --format '{{.Names}}')
    ((${#candidates[@]})) || die "找不到名为 $container_name 的容器"

    local target
    if ((${#candidates[@]} == 1)); then
        target="${candidates[0]}"
    else
        echo "找到多个同名容器："
        for idx in "${!candidates[@]}"; do
            printf '%3d) %s\n' $((idx+1)) "${candidates[idx]}"
        done
        read -rp "请选择要恢复的容器 [1-${#candidates[@]}]: " choice
        [[ $choice =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )) || die "无效编号"
        target="${candidates[$((choice-1))]}"
    fi

    # ---------- 收集挂载信息 ----------
    local -A bind_map vol_map   # Destination -> Source
    local line
    while IFS=: read -r src dst; do
        [[ -n $src && -n $dst ]] && bind_map["$dst"]="$src"
    done < <(docker inspect "$target" --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}:{{.Destination}}{{printf "\n"}}{{end}}{{end}}')

    while IFS=: read -r vol_name dst; do
        [[ -n $vol_name && -n $dst ]] && vol_map["$dst"]="$vol_name"
    done < <(docker inspect "$target" --format '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}:{{.Destination}}{{printf "\n"}}{{end}}{{end}}')

    ((${#bind_map[@]} + ${#vol_map[@]})) || die "容器 $target 既无 bind 挂载也无 volume，无需恢复"

    # ---------- 停止容器 ----------
    log "停止容器 $target"
    docker stop "$target" >/dev/null || die "无法停止容器 $target"

    # ---------- 准备临时目录 ----------
    mkdir -p "$TMP_TAR_DIR"
    local ok=0 fail=0

    # ---------- 1. 恢复 bind 挂载 ----------
    for dst in "${!bind_map[@]}"; do
        local host_path="${bind_map[$dst]}"
        local arc="$backup_path/bind_$(basename "$dst").tar.gz"
        [[ -f $arc ]] || { log "跳过：未找到 bind 备份包 $(basename "$arc")"; ((fail++)); continue; }

        printf '  [%2d/%d] bind %s ... ' $((ok+fail+1)) $((${#bind_map[@]} + ${#vol_map[@]}))
        rm -rf "$host_path" && mkdir -p "$host_path"
        if tar -xzf "$arc" -C "$host_path" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"; ((ok++))
        else
            echo -e "${RED}FAIL${NC}"; log "解压失败：$arc"; ((fail++))
        fi
    done

    # ---------- 2. 恢复 volume 挂载 ----------
    for dst in "${!vol_map[@]}"; do
        local vol_name="${vol_map[$dst]}"
        local arc="$backup_path/volume_${vol_name}.tar.gz"
        [[ -f $arc ]] || { log "跳过：未找到 volume 备份包 $(basename "$arc")"; ((fail++)); continue; }

        printf '  [%2d/%d] volume %s ... ' $((ok+fail+1)) $((${#bind_map[@]} + ${#vol_map[@]}))
        # 先把 tar 包拷进临时目录，再启动临时容器写卷
        cp -f "$arc" "$TMP_TAR_DIR/${vol_name}.tar.gz"
        if docker run --rm \
               -v "${vol_name}:/to_vol:rw" \
               -v "$TMP_TAR_DIR:/from_host:ro" \
               alpine:latest \
               sh -c "rm -rf /to_vol/* && tar -xzf /from_host/${vol_name}.tar.gz -C /to_vol" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"; ((ok++))
        else
            echo -e "${RED}FAIL${NC}"; log "恢复失败：volume $vol_name"; ((fail++))
        fi
    done

    # ---------- 清理临时目录 ----------
    rm -rf "$TMP_TAR_DIR"

    # ---------- 启动容器 ----------
    log "启动容器 $target"
    docker start "$target" >/dev/null || die "启动失败"

    log "恢复完成（成功 $ok / 失败 $fail）"
    echo -e "\n[${GREEN}√${NC}] 容器 $target 数据已恢复"
}

# ------------------ 入口检查 ---------------------------------------
[[ "$(id -u)" -eq 0 ]] || die "请使用 root 运行"
command -v docker >/dev/null || die "Docker 未安装或未启动"
[[ -d "$BACKUP_DIR" ]] || die "备份目录 $BACKUP_DIR 不存在"

restore_system
