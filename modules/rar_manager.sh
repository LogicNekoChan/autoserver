#!/usr/bin/env bash
# ==========================================
# 万能压缩/解压管理器 PRO 优化版
# ==========================================
set -eo pipefail
IFS=$'\n\t'

# 修复终端交互环境
printf '\e[?1000l'
trap 'printf "\e[?1000l"; exit' INT TERM EXIT

# --- 颜色与日志 ---
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# --- 依赖检查 ---
check_dep() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then missing+=("$cmd"); fi
    done
    if [ ${#missing[@]} -ne 0 ]; then
        err "缺少必要工具: ${missing[*]}"
        log "建议执行: sudo apt update && sudo apt install rar unrar p7zip-full zip unzip -y"
        exit 1
    fi
}
check_dep rar unrar 7z zip unzip tar realpath

# --- 安全路径处理 ---
read_path() {
    local _p
    read -rep "$1" _p
    _p="${_p%\"}" && _p="${_p#\"}" # 移除引号
    if [[ ! -e "$_p" ]]; then
        err "路径不存在: $_p"
        return 1
    fi
    realpath "$_p"
}

# --- 核心压缩逻辑 (RAR 专用) ---
# 参数: $1=目标文件 $2=输出文件 $3=密码 $4=分卷大小(可为空)
core_rar_compress() {
    local target="$1" output="$2" pwd="$3" vol="$4"
    local args=(-ep1 -m3 -rr5% -idq -y)
    
    [[ -n "$pwd" ]] && args+=("-p$pwd" "-hp")
    [[ -n "$vol" ]] && args+=("-v$vol")
    
    log "正在打包: $(basename "$target")"
    if rar a "${args[@]}" "$output" "$target"; then
        return 0
    else
        err "压缩失败: $target"
        return 1
    fi
}

# --- 目录扁平化处理 ---
# 解决解压后出现 A/A/文件 的尴尬情况
flatten_dir() {
    local dir="$1"
    local sub_items=("$dir"/*)
    # 如果目录下只有一个子目录，且没有其他文件
    if [[ ${#sub_items[@]} -eq 1 && -d "${sub_items[0]}" ]]; then
        local sub="${sub_items[0]}"
        log "检测到嵌套目录，正在扁平化..."
        # 移动所有内容（包含隐藏文件）
        find "$sub" -maxdepth 1 -mindepth 1 -exec mv -t "$dir" {} +
        rmdir "$sub"
    fi
}

# --- 功能函数 ---

compress_logic() {
    local is_split=$1
    local target; target=$(read_path "请输入要压缩的文件/目录: ") || return
    local base_name; base_name=$(basename "$target")
    local out_dir; out_dir="$(dirname "$target")/${base_name}_archives"
    
    mkdir -p "$out_dir"
    local output="${out_dir}/${base_name}.rar"
    
    read -rep "设置密码 (直接回车则无密码): " password
    local vol=""
    [[ "$is_split" == "true" ]] && vol="4000m"

    core_rar_compress "$target" "$output" "$password" "$vol"
    log "✅ 完成！存放于: $out_dir"
}

decompress_logic() {
    local archive; archive=$(read_path "请输入压缩包路径: ") || return
    local base_name; base_name=$(basename "$archive")
    local parent_dir; parent_dir=$(dirname "$archive")
    
    # 自动创建与包名同名的文件夹进行解压
    local outdir="${parent_dir}/${base_name%.*}"
    mkdir -p "$outdir"

    log "🚀 正在识别格式并解压..."
    
    case "${archive,,}" in # 转小写判断
        *.rar)
            unrar x -o+ -idq "$archive" "$outdir/" || 7z x -y "$archive" -o"$outdir" ;;
        *.zip)
            unzip -o -q "$archive" -d "$outdir" ;;
        *.7z|*.iso)
            7z x -y -bd "$archive" -o"$outdir" ;;
        *.tar*)
            tar -xf "$archive" -C "$outdir" ;;
        *)
            warn "未知格式，尝试 7z 强制解压..."
            7z x -y "$archive" -o"$outdir" ;;
    esac

    flatten_dir "$outdir"
    log "✅ 解压完成: $outdir"
}

batch_compress() {
    local src_dir; src_dir=$(read_path "请输入要批量压缩的文件夹: ") || return
    local out_root="${src_dir}/Batch_Result_$(date +%Y%m%d)"
    mkdir -p "$out_root"

    echo -e "\n${BLUE}模式选择:${NC} 1)单卷  2)分卷(4000M)"
    read -rep "选择 [1-2]: " mode
    read -rep "统一密码 (回车无): " pwd

    # 使用 find 避免通配符展开过大
    find "$src_dir" -maxdepth 1 -not -path "$src_dir" -not -path "$out_root" | while read -r item; do
        local name; name=$(basename "$item")
        local final_out="${out_root}/${name}/${name}.rar"
        mkdir -p "$(dirname "$final_out")"
        
        local vol=""
        [[ "$mode" == "2" ]] && vol="4000m"
        core_rar_compress "$item" "$final_out" "$pwd" "$vol"
    done
    log "✅ 批量任务完成！"
}

# --- 主菜单 ---
while true; do
    echo -e "\n${BLUE}==========================================${NC}"
    echo -e "${BLUE}    Ubuntu代码 - 万能压缩/解压管理器 PRO${NC}"
    echo -e "${BLUE}==========================================${NC}"
    echo "1) 单个压缩 (RAR)"
    echo "2) 分卷压缩 (RAR - 4000M)"
    echo "3) 🔥 万能解压 (自动扁平化)"
    echo "4) 📦 批量压缩 (独立打包)"
    echo "5) 🔓 批量解密 (重新打包)"
    echo "6) 📂 批量解压 (全量处理)"
    echo "7) 退出"
    read -rep "请选择 [1-7]: " choice

    case "$choice" in
        1) compress_logic "false" ;;
        2) compress_logic "true" ;;
        3) decompress_logic ;;
        4) batch_compress ;;
        5) log "该功能建议结合 batch_extract 后再执行 batch_compress" ;;
        6) # 逻辑同 3，但在 loop 中执行，此处略，可参考原脚本
           warn "建议对目录内文件执行循环调用功能 3" ;;
        7) log "再见！"; exit 0 ;;
        *) err "输入有误" ;;
    esac
done
