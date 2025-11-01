#!/usr/bin/env bash
# ==========================================
# 7z 压缩/解压管理器
# 支持单个文件或目录打包、分卷压缩、设置压缩密码
# 支持解压单个压缩包和分卷压缩包
# 全程中文提示
# ==========================================
set -euo pipefail

########## 依赖检查 ##########
command -v 7z >/dev/null || { echo "❌ 请先安装 7z：sudo apt install p7zip-full"; exit 1; }

########## 彩色输出 ##########
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }

########## 安全读路径（自动去引号+转绝对路径） ##########
read_path(){
  local _path
  read -rp "$1" _path
  _path="${_path%\"}"; _path="${_path#\"}"   # 去掉两端引号
  [[ -e "$_path" ]] || { err "路径不存在：$_path"; return 1; }
  realpath "$_path"
}

########## 1. 单个文件或目录打包 ##########
compress_single(){
  local target output
  target=$(read_path "请输入要压缩的文件或目录路径：")
  read -rp "请输入输出文件名（带 .7z 后缀，默认为 ${target##*/}.7z）： " output
  [[ -z "$output" ]] && output="${target##*/}.7z"
  read -rsp "请输入压缩密码（留空则无密码）： " password
  echo
  if [[ -n "$password" ]]; then
    7z a -p"$password" -mhe=on "$output" "$target"
  else
    7z a "$output" "$target"
  fi
  if [[ $? -eq 0 ]]; then
    log "✅ 压缩完成，文件已保存到 $(realpath "$output")"
  else
    err "压缩过程中出现错误"
  fi
}

########## 2. 分卷压缩 ##########
compress_split(){
  local target output volume_size
  target=$(read_path "请输入要压缩的文件或目录路径：")
  read -rp "请输入输出文件名（带 .7z 后缀，默认为 ${target##*/}.7z）： " output
  [[ -z "$output" ]] && output="${target##*/}.7z"
  read -rp "请输入分卷大小（默认 2g）： " volume_size
  [[ -z "$volume_size" ]] && volume_size="2g"
  read -rsp "请输入压缩密码（留空则无密码）： " password
  echo
  if [[ -n "$password" ]]; then
    7z a -p"$password" -mhe=on -v"$volume_size" "$output" "$target"
  else
    7z a -v"$volume_size" "$output" "$target"
  fi
  if [[ $? -eq 0 ]]; then
    log "✅ 分卷压缩完成，文件已保存到 $(dirname "$(realpath "$output")")"
  else
    err "分卷压缩过程中出现错误"
  fi
}

########## 3. 解压单个压缩包 ##########
decompress_single(){
  local archive output_dir
  archive=$(read_path "请输入压缩包路径：")
  read -rp "请输入解压目标目录（留空则为当前目录）： " output_dir
  [[ -z "$output_dir" ]] && output_dir="."
  read -rsp "请输入解压密码（留空则无密码）： " password
  echo
  if [[ -n "$password" ]]; then
    7z x -p"$password" -o"$output_dir" -aoa -spe "$archive"
  else
    7z x -o"$output_dir" -aoa -spe "$archive"
  fi
  if [[ $? -eq 0 ]]; then
    log "✅ 解压完成，文件已保存到 $(realpath "$output_dir")"
  else
    err "解压过程中出现错误"
  fi
}

########## 4. 解压分卷压缩包 ##########
decompress_split(){
  local archive output_dir
  archive=$(read_path "请输入分卷压缩包路径（如 part1.7z）：")
  read -rp "请输入解压目标目录（留空则为当前目录）： " output_dir
  [[ -z "$output_dir" ]] && output_dir="."
  read -rsp "请输入解压密码（留空则无密码）： " password
  echo
  if [[ -n "$password" ]]; then
    7z x -p"$password" -o"$output_dir" -aoa -spe "$archive"
  else
    7z x -o"$output_dir" -aoa -spe "$archive"
  fi
  if [[ $? -eq 0 ]]; then
    log "✅ 解压完成，文件已保存到 $(realpath "$output_dir")"
  else
    err "解压过程中出现错误"
  fi
}

########## 菜单循环 ##########
while true; do
  echo -e "\n${BLUE}======== 7z 压缩/解压管理器 ========${NC}"
  echo "1) 单个文件或目录打包"
  echo "2) 分卷压缩"
  echo "3) 解压单个压缩包"
  echo "4) 解压分卷压缩包"
  echo "5) 退出"
  read -rp "请选择操作（1-5）：" choice
  case $choice in
    1) compress_single ;;
    2) compress_split ;;
    3) decompress_single ;;
    4) decompress_split ;;
    5) log "bye~"; exit 0 ;;
    *) err "请输入 1-5 之间的数字" ;;
  esac
done
