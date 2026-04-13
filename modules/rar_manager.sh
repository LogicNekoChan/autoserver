#!/usr/bin/env bash
# ==========================================
# 万能压缩/解压管理器（自动建目录版）
# 功能：
#   1. 压缩时自动创建同名文件夹，所有分卷统一存放
#   2. 鼠标滚轮不乱码
#   3. 解压支持全格式：rar zip 7z tar iso 等
#   4. 分卷大小 4000m（兼容FAT32/光盘/云盘）
# ==========================================
set -euo pipefail

# 修复鼠标滚轮乱码
printf '\e[?1000l'
trap 'printf "\e[?1000l"' INT TERM EXIT

########## 依赖检查 ##########
check_dep() {
  for cmd in "$@"; do
    if ! command -v "$cmd" &>/dev/null; then
      echo -e "\033[31m[错误]\033[0m 缺少工具：$cmd"
      echo -e "安装：sudo apt install rar unrar unzip p7zip-full"
      exit 1
    fi
  done
}
check_dep rar unrar unzip 7z tar

########## 颜色输出 ##########
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[提示] $*${NC}"; }
warn() { echo -e "${YELLOW}[警告] $*${NC}"; }
err()  { echo -e "${RED}[错误] $*${NC}" >&2; }

########## 安全路径读取 ##########
read_path() {
  local _p
  read -rep "$1" _p
  _p="${_p%\"}"
  _p="${_p#\"}"
  if [[ ! -e "$_p" ]]; then
    err "路径不存在：$_p"
    return 1
  fi
  realpath "$_p"
}

########## 压缩包校验 ##########
check_archive() {
  local arc="$1"
  if [[ -f "$arc" ]]; then
    if rar t "$arc" &>/dev/null; then
      log "✅ 压缩包正常：$arc"
    else
      warn "⚠️ 压缩包可能损坏：$arc"
    fi
  fi
}

###########################################################################
# 单个压缩：自动创建目录，包放里面
###########################################################################
compress_single() {
  local target
  target=$(read_path "请输入要压缩的文件/目录：")

  local base_name
  base_name=$(basename "$target")
  local out_dir
  out_dir="$(dirname "$target")/${base_name}_压缩包"

  mkdir -p "$out_dir"
  log "📂 输出目录：$out_dir"

  local output="${out_dir}/${base_name}.rar"
  local password=""
  read -rep "设置密码（回车无密码）：" password

  if [[ -n "$password" ]]; then
    rar a -p"$password" -hp -ep1 -m3 -rr5% -idq "$output" "$target"
  else
    rar a -ep1 -m3 -rr5% -idq "$output" "$target"
  fi

  log "✅ 单个压缩完成"
  check_archive "$output"
}

###########################################################################
# 分卷压缩：自动创建目录，所有分卷放里面
###########################################################################
compress_split() {
  local target
  target=$(read_path "请输入要压缩的文件/目录：")

  local base_name
  base_name=$(basename "$target")
  local out_dir
  out_dir="$(dirname "$target")/${base_name}_压缩包"

  mkdir -p "$out_dir"
  log "📂 所有分卷将存入：$out_dir"

  local output="${out_dir}/${base_name}.rar"
  local volume_size="4000m"
  local password=""
  read -rep "设置密码（回车无密码）：" password

  log "📦 开始分卷压缩，每卷 $volume_size"

  if [[ -n "$password" ]]; then
    rar a -v"$volume_size" -p"$password" -hp -ep1 -m3 -rr5% -idq "$output" "$target"
  else
    rar a -v"$volume_size" -ep1 -m3 -rr5% -idq "$output" "$target"
  fi

  log "✅ 分卷压缩完成"
  check_archive "${out_dir}/${base_name}.part1.rar" || check_archive "$output"
}

###########################################################################
# 万能解压（全格式自动识别）
###########################################################################
decompress_all() {
  local archive
  archive=$(read_path "请输入压缩包路径：")

  local outdir=""
  read -rep "解压到（默认当前目录）：" outdir
  [[ -z "$outdir" ]] && outdir=$(dirname "$archive")
  outdir=$(realpath -m "$outdir")
  mkdir -p "$outdir"

  log "🚀 自动识别格式解压..."

  case "$archive" in
    *.rar|*.RAR)
      unrar x -o+ -idq "$archive" "$outdir/"
      ;;
    *.zip|*.ZIP)
      unzip -o -q "$archive" -d "$outdir"
      ;;
    *.7z|*.7Z)
      7z x -y -bd "$archive" -o"$outdir"
      ;;
    *.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.txz)
      tar -xf "$archive" -C "$outdir"
      ;;
    *.iso|*.ISO)
      7z x -y -bd "$archive" -o"$outdir"
      ;;
    *)
      warn "未知格式，尝试用 7z 强制解压"
      7z x -y -bd "$archive" -o"$outdir"
      ;;
  esac

  log "✅ 解压完成：$outdir"
}

########## 主菜单 ##########
while true; do
  echo -e "\n${BLUE}==== 万能压缩/解压管理器 ====${NC}"
  echo "1) 单个压缩（自动建目录）"
  echo "2) 分卷压缩（4000m 自动建目录）"
  echo "3) 🔥 万能解压（全格式）"
  echo "4) 退出"
  read -rep "请选择 [1-4]：" choice

  case "$choice" in
    1) compress_single ;;
    2) compress_split ;;
    3) decompress_all ;;
    4) log "👋 再见"; exit 0 ;;
    *) err "请输入 1-4" ;;
  esac
done
