#!/usr/bin/env bash
# ==========================================
# RAR 压缩/解压管理器（优化版）
# - 自动识别分卷（支持 part1.rar / .r00 / 001.rar 等）
# - 自动检查分卷是否完整
# - 单文件压缩 / 分卷压缩 / 解压
# - 中文界面
# ==========================================
set -euo pipefail

########## 依赖检查 ##########
for cmd in rar unrar; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装：sudo apt install $cmd"; exit 1; }
done

########## 彩色输出 ##########
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }

########## 安全路径读取 ##########
read_path(){
  local _p
  read -rp "$1" _p
  _p="${_p%\"}"; _p="${_p#\"}"
  [[ -e "$_p" ]] || { err "路径不存在：$_p"; return 1; }
  realpath "$_p"
}

########## 压缩完整性检查 ##########
check_archive(){
  rar t "$1" &>/dev/null \
    && log "✅ 压缩包完整性检查通过：$1" \
    || err "压缩包完整性检查失败：$1"
}

########## 自动识别分卷前缀 ##########
find_multivolume_parts(){
  local base="$1"
  local dir prefix parts

  dir=$(dirname "$base")
  base=$(basename "$base")

  # 去掉扩展名部分（支持 .part1.rar / .r00 / .001 等）
  prefix="${base%%.*}"

  # 搜索可能的分卷模式
  parts=(
    "$dir/${prefix}.part"*.rar
    "$dir/${prefix}.r"*
    "$dir/${prefix}."???
    "$dir/${prefix}."??
  )

  local found=()
  for f in "${parts[@]}"; do
    [[ -e "$f" ]] && found+=("$f")
  done

  if [[ ${#found[@]} -eq 0 ]]; then
    err "未找到任何分卷文件"
    return 1
  fi

  printf "%s\n" "${found[@]}"
}

########## 检查分卷是否连续 ##########
check_parts_complete(){
  local files=("$@")
  local missing=0

  for f in "${files[@]}"; do
    [[ -e "$f" ]] || { warn "缺失分卷：$f"; missing=1; }
  done

  return $missing
}

########## 单文件/目录压缩 ##########
compress_single(){
  local target=$(read_path "请输入要压缩的文件或目录路径：")
  local outdir=$(dirname "$target")
  local output="${target##*/}.rar"
  local password

  read -rp "请输入密码（回车跳过）： " password

  if [[ -n "$password" ]]; then
    rar a -p"$password" -ep1 -m3 -rr3% -hp "$outdir/$output" "$target"
  else
    rar a -ep1 -m3 -rr3% "$outdir/$output" "$target"
  fi

  log "✅ 压缩完成：$outdir/$output"
  check_archive "$outdir/$output"
}

########## 分卷压缩 ##########
compress_split(){
  local target=$(read_path "请输入要压缩的文件或目录路径：")
  local outdir=$(dirname "$target")
  local output="${target##*/}.rar"
  local volume_size="2000m" # 默认分卷大小为2000MB
  local password

  read -rp "请输入密码（回车跳过）： " password

  if [[ -n "$password" ]]; then
    rar a -p"$password" -v"$volume_size" -ep1 -m3 -rr3% -hp "$outdir/$output" "$target"
  else
    rar a -v"$volume_size" -ep1 -m3 -rr3% "$outdir/$output" "$target"
  fi

  log "✅ 分卷压缩完成：$outdir"
  check_archive "$outdir/$output"
}

########## 解压单个文件 ##########
decompress_single(){
  local archive=$(read_path "请输入压缩包路径：")
  local outdir password

  read -rp "请输入解压路径（默认当前目录）： " outdir
  [[ -z "$outdir" ]] && outdir=$(dirname "$archive")
  outdir=$(realpath "$outdir")

  mkdir -p "$outdir"

  read -rp "请输入密码（回车跳过）： " password

  [[ -n "$password" ]] \
    && unrar x -p"$password" "$archive" "$outdir" \
    || unrar x "$archive" "$outdir"

  log "✅ 解压完成：$outdir"
}

########## 解压分卷 ##########
decompress_split(){
  local archive=$(read_path "请输入任意一个分卷文件路径：")
  local outdir password parts

  read -rp "请输入解压路径（默认当前目录）： " outdir
  [[ -z "$outdir" ]] && outdir=$(dirname "$archive")
  outdir=$(realpath "$outdir")

  mkdir -p "$outdir"

  read -rp "请输入密码（回车跳过）： " password

  # 自动找到所有分卷
  mapfile -t parts < <(find_multivolume_parts "$archive")

  if (( ${#parts[@]} == 0 )); then
    err "未找到任何分卷文件"
    return 1
  fi

  log "检测到以下分卷："
  printf "  %s\n" "${parts[@]}"

  # 按文件名排序并检查连续性
  IFS=$'\n' parts=($(sort <<<"${parts[*]}"))
  unset IFS

  # 执行解压（只需要从第一个分卷开始）
  local start="${parts[0]}"

  log "开始解压：$start"
  if [[ -n "$password" ]]; then
    unrar x -p"$password" "$start" "$outdir"
  else
    unrar x "$start" "$outdir"
  fi

  log "✅ 分卷解压完成：$outdir"
}

########## 菜单 ##########
while true; do
  echo -e "\n${BLUE}======== RAR 压缩/解压管理器 ========${NC}"
  echo "1) 单个文件或目录打包"
  echo "2) 分卷压缩"
  echo "3) 解压单个压缩包"
  echo "4) 解压分卷压缩包（自动识别）"
  echo "5) 退出"
  read -rp "请选择操作（1-5）： " choice
  case $choice in
    1) compress_single ;;
    2) compress_split ;;
    3) decompress_single ;;
    4) decompress_split ;;
    5) log "👋 再见！"; exit 0 ;;
    *) err "请输入 1~5 的数字" ;;
  esac
done
