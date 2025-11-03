好的，我将为你完善代码，确保代码逻辑清晰、功能完整，并且符合你的需求。以下是完善后的代码：

```bash
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

########## 检测压缩包完整性 ##########
check_archive_integrity(){
  local archive=$1
  if rar t "$archive" &>/dev/null; then
    log "✅ 压缩包完整性检查通过：$archive"
  else
    err "压缩包完整性检查失败：$archive"
    return 1
  fi
}

########## 密码缓存文件 ##########
PASSWORD_CACHE_FILE="$HOME/.rar_password_cache"

########## 读取密码缓存 ##########
read_password_cache(){
  if [[ -f "$PASSWORD_CACHE_FILE" ]]; then
    local passwords=()
    while IFS= read -r line; do
      passwords+=("$line")
    done < "$PASSWORD_CACHE_FILE"
    echo "${passwords[@]}"
  else
    echo ""
  fi
}

########## 保存密码到缓存 ##########
save_password_to_cache(){
  local password=$1
  echo "$password" >> "$PASSWORD_CACHE_FILE"
  chmod 600 "$PASSWORD_CACHE_FILE"
}

########## 选择密码 ##########
choose_password(){
  local passwords=($1)
  local password=""
  if [[ ${#passwords[@]} -gt 0 ]]; then
    echo "已存储的密码："
    for i in "${!passwords[@]}"; do
      echo "$((i+1))) ${passwords[$i]}"
    done
    read -rp "请选择密码编号（留空则输入新密码）： " choice
    if [[ -n "$choice" && $choice -le ${#passwords[@]} ]]; then
      password="${passwords[$((choice-1))]}"
    fi
  fi
  if [[ -z "$password" ]]; then
    read -rp "请输入密码（留空则无密码）： " password
  fi
  echo "$password"
}

########## 1. 单个文件或目录打包 ##########
compress_single(){
  local target output output_dir password
  target=$(read_path "请输入要压缩的文件或目录路径：")
  output_dir=$(dirname "$target")
  output="${target##*/}.rar"
  local cached_passwords=$(read_password_cache)
  password=$(choose_password "$cached_passwords")
  echo
  if [[ -n "$password" ]]; then
    rar a -p"$password" -ep1 -m5 -rr5% -hp "$output_dir/$output" "$target"
    save_password_to_cache "$password"
  else
    rar a -ep1 -m5 -rr5% "$output_dir/$output" "$target"
  fi
  if [[ $? -eq 0 ]]; then
    log "✅ 压缩完成，文件已保存到 $output_dir/$output"
    check_archive_integrity "$output_dir/$output"
  else
    err "压缩过程中出现错误"
  fi
}

########## 2. 分卷压缩 ##########
compress_split(){
  local target output output_dir volume_size password
  target=$(read_path "请输入要压缩的文件或目录路径：")
  output_dir=$(dirname "$target")
  output="${target##*/}.rar"
  read -rp "请输入分卷大小（默认 2000MB）： " volume_size
  [[ -z "$volume_size" ]] && volume_size="2000m"
  local cached_passwords=$(read_password_cache)
  password=$(choose_password "$cached_passwords")
  echo
  if [[ -n "$password" ]]; then
    rar a -p"$password" -v"$volume_size" -ep1 -m5 -rr5% -hp "$output_dir/$output" "$target"
    save_password_to_cache "$password"
  else
    rar a -v"$volume_size" -ep1 -m5 -rr5% "$output_dir/$output" "$target"
  fi
  if [[ $? -eq 0 ]]; then
    log "✅ 分卷压缩完成，文件已保存到 $output_dir"
    check_archive_integrity "$output_dir/$output"
  else
    err "分卷压缩过程中出现错误"
  fi
}

########## 3. 解压单个压缩包 ##########
decompress_single(){
  local archive output_dir password
  archive=$(read_path "请输入压缩包路径：")
  output_dir=$(dirname "$archive")
  
  # 提示用户输入解压路径
  read -rp "请输入解压路径（留空则解压到压缩包所在目录）： " user_output_dir
  if [[ -n "$user_output_dir" ]]; then
    output_dir=$(realpath "$user_output_dir")
    mkdir -p "$output_dir" || { err "无法创建目标目录：$output_dir"; return 1; }
  fi

  local cached_passwords=$(read_password_cache)
  password=$(choose_password "$cached_passwords")
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

########## 4. 解压分卷压缩包 ##########
decompress_split(){
  local archive output_dir password
  archive=$(read_path "请输入分卷压缩包路径（如 part1.rar）：")
  output_dir=$(dirname "$archive")
  
  # 提示用户输入解压路径
  read -rp "请输入解压路径（留空则解压到压缩包所在目录）： " user_output_dir
  if [[ -n "$user_output_dir" ]]; then
    output_dir=$(realpath "$user_output_dir")
    mkdir -p "$output_dir" || { err "无法创建目标目录：$output_dir"; return 1; }
  fi

  local cached_passwords=$(read_password_cache)
  password=$(choose_password "$cached_passwords")
  echo

  # 检测所有分卷文件
  local part_files=($(ls "$(dirname "$archive")"/Fantia.part*.rar 2>/dev/null))
  if [[ ${#part_files[@]} -eq 0 ]]; then
    err "未找到分卷文件，请确保所有分卷文件位于同一目录中。"
    return 1
  fi

  # 解压分卷文件
  if [[ -n "$password" ]]; then
    unrar x -p"$password" "${part_files[@]}" "$output_dir"
  else
    unrar x "${part_files[@]}" "$output_dir"
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
  echo "3) 解压单个压缩包"
  echo "4) 解压分卷压缩包"
  echo "5) 退出"
  read -rp "请选择操作（1-5）： " choice
  case $choice in
    1) compress_single ;;
    2) compress_split ;;
    3) decompress_single ;;
    4) decompress_split ;;
    5) log "👋 再见！感谢使用 RAR 管理器。"; exit 0 ;;
    *)
      err "请输入 1 到 5 之间的数字！"
      ;;
  esac
done
