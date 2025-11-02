#!/usr/bin/env bash
# ==========================================
# RAR 压缩/解压管理器
# 支持单个文件或目录打包、分卷压缩、设置压缩密码
# 支持解压单个压缩包和分卷压缩包
# 全程中文提示
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
  output_dir=$(dirname "$target")
  output="${target##*/}.rar"
  read -rsp "请输入压缩密码（留空则无密码）： " password
  echo
  if [[ -n "$password" ]]; then
    rar a -p"$password" -ep1 -m5 -rr5% "$output_dir/$output" "$target"
  else
    rar a -ep1 -m5 -rr5% "$output_dir/$output" "$target"
  fi
  if [[ $? -eq 0 ]]; then
    log "✅ 压缩完成，文件已保存到 $output_dir/$output"
  else
    err "压缩过程中出现错误"
  fi
}

########## 2. 分卷压缩 ##########
compress_split(){
  local target output volume_size
  target=$(read_path "请输入要压缩的文件或目录路径：")
  output_dir=$(dirname "$target")
  output="${target##*/}.rar"
  read -rp "请输入分卷大小（默认 2048MB）： " volume_size
  [[ -z "$volume_size" ]] && volume_size="2048m"
  read -rsp "请输入压缩密码（留空则无密码）： " password
  echo
  if [[ -n "$password" ]]; then
    rar a -p"$password" -v"$volume_size" -ep1 -m5 -rr5% "$output_dir/$output" "$target"
  else
    rar a -v"$volume_size" -ep1 -m5 -rr5% "$output_dir/$output" "$target"
  fi
  if [[ $? -eq 0 ]]; then
    log "✅ 分卷压缩完成，文件已保存到 $output_dir"
  else
    err "分卷压缩过程中出现错误"
  fi
}

########## 3. 解压 ##########
decompress(){
  local archive output_dir
  archive=$(read_path "请输入压缩包路径：")
  output_dir=$(dirname "$archive")
  
  # 提示用户输入解压路径
  read -rp "请输入解压路径（留空则解压到压缩包所在目录）： " user_output_dir
  if [[ -n "$user_output_dir" ]]; then
    output_dir=$(realpath "$user_output_dir")
    mkdir -p "$output_dir" || { err "无法创建目标目录：$output_dir"; return 1; }
  fi

  # 提示用户输入解压密码
  read -rsp "请输入解压密码（留空则无密码）： " password
  echo

  if [[ -n "$password" ]]; then
    unrar x -p"$password" "$archive" "$output_dir"
  else
    unrar x "$archive" "$output_dir"
  fi

  if [[ $? -eq 0 ]]; then
    log "✅ 解压完成，文件已保存到 $output_dir"
    ls -l "$output_dir"
  else
    err "解压过程中出现错误"
  fi
}

########## 菜单循环 ##########
while true; do
  echo -e "\n${BLUE}======== RAR 压缩/解压管理器 ========${NC}"
  echo "1) 单个文件或目录打包"
  echo "2) 分卷压缩"
  echo "3) 解压"
  echo "4) 退出"
  read -rp "请选择操作（1-4）：" choice
  case $choice in
    1) compress_single ;;
    2) compress_split ;;
    3) decompress ;;
    4) log "bye~"; exit 0 ;;
    *) err "请输入 1-4 之间的数字" ;;
  esac
done
