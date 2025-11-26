#!/usr/bin/env bash
# ==========================================
# Ubuntu 交互式 PGP 管理器（增强版）
# 新增：分卷加密 & 自动合并分卷解密
# ==========================================
set -euo pipefail

########## 依赖检查 ##########
for cmd in gpg tar split pv; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装：sudo apt install gnupg tar coreutils pv"; exit 1; }
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

########## 1. 创建密钥 ##########
create_key(){ gpg --full-generate-key; }

########## 2. 导入密钥 ##########
import_key(){
  local asc=$(read_path "请输入密钥文件路径：")
  gpg --import "$asc"
  log "已导入"
}

########## 3. 导出公钥 ##########
export_pub_key(){
  local email out
  read -rp "要导出的邮箱： " email
  read -rp "保存为（默认 ${email}_pub.asc）： " out
  [[ -z "$out" ]] && out="${email}_pub.asc"
  gpg --armor --export "$email" > "$out"
  log "公钥已导出：$(realpath "$out")"
}

########## 4. 导出私钥 ##########
export_sec_key(){
  local email out
  read -rp "要导出的邮箱： " email
  read -rp "保存为（默认 ${email}_sec.asc）： " out
  [[ -z "$out" ]] && out="${email}_sec.asc"
  gpg --armor --export-secret-keys "$email" > "$out"
  log "⚠️ 私钥已导出：$(realpath "$out")"
}

########## 5. 删除密钥 ##########
delete_key(){
  local email
  read -rp "要删除的邮箱： " email
  gpg --delete-secret-and-public-keys "$email" && log "已删除" || warn "密钥不存在或已取消"
}

#############################################
# 6. 加密（含分卷功能）
#############################################
encrypt(){
  local target recipient target_dir basename idx n split_mb

  #---- 列出本地公钥 ----#
  echo -e "\n${BLUE}====== 本地公钥列表 ======${NC}"
  mapfile -t keys < <(gpg --list-keys --with-colons | awk -F: '$1=="uid"{print $10}' | sed 's/.*<\(.*\)>.*/\1/')
  n=${#keys[@]}
  (( n==0 )) && { warn "没有公钥，请先导入或创建。"; return 1; }

  for i in "${!keys[@]}"; do printf "  %2d) %s\n" $((i+1)) "${keys[i]}"; done

  #---- 选择接收者 ----#
  while true; do
    read -rp "请选择接收者编号（1-$n）：" idx
    [[ "$idx" =~ ^[0-9]+$ ]] && (( idx>=1 && idx<=n )) && break
    err "无效编号"
  done
  recipient="${keys[$((idx-1))]}"

  #---- 读取目标路径 ----#
  target=$(read_path "要加密的文件或文件夹：")
  target_dir=$(dirname "$target")
  basename=$(basename "$target")
  cd "$target_dir"

  #---- 分卷选项 ----#
  read -rp "是否分卷？输入 MB 大小（例如 100），留空则不分卷：" split_mb

  #---- 打包目录 ----#
  local src_file="${basename}"
  if [[ -d "$basename" ]]; then
    log "检测到目录，正在打包..."
    src_file="${basename}.tar.gz"
    tar czf "$src_file" "$basename"
  fi

  #---- 不分卷 ----#
  if [[ -z "$split_mb" ]]; then
    pv "$src_file" | gpg -e -r "$recipient" -o "${src_file}.gpg"
    log "加密完成：${src_file}.gpg"
    return
  fi

  #---- 分卷加密 ----#
  local split_size="${split_mb}M"
  log "开始分卷：每卷 $split_size"
  
  split --bytes="$split_size" -d -a 3 "$src_file" "${src_file}.part"
  for part in ${src_file}.part*; do
    pv "$part" | gpg -e -r "$recipient" -o "${part}.gpg"
    rm "$part"
  done

  log "分卷加密完成：${src_file}.partXXX.gpg"
}

#############################################
# 7. 自动识别分卷 + 解密
#############################################
decrypt(){
  local gpg_file dir basename prefix

  gpg_file=$(read_path "输入任意 .gpg 文件路径（如果是分卷，会自动识别）：")
  dir=$(dirname "$gpg_file")
  basename=$(basename "$gpg_file")
  cd "$dir"

  #---- 判断是否为分卷 ----#
  if [[ "$basename" =~ ^(.+)\.part([0-9]+)\.gpg$ ]]; then
    prefix="${BASH_REMATCH[1]}"
    log "检测到分卷格式。开始自动合并..."

    # 合并为一个大文件
    local merged="${prefix}.merged"
    : > "$merged"

    for part in $(ls "${prefix}".part*.gpg | sort); do
      log "解密：$part"
      gpg -d "$part" >> "$merged"
    done

    # 如果是tar包则自动解压
    if [[ "$merged" == *.tar.gz.merged || "$merged" == *.tar.gz ]]; then
      mv "$merged" "${prefix}.tar.gz"
      log "正在解压目录包..."
      tar xzf "${prefix}.tar.gz"
      log "目录已恢复"
    else
      log "已合并并解密：$merged"
    fi
    return
  fi

  #---- 普通单文件解密 ----#
  local out="${basename%.gpg}"
  gpg -d "$basename" > "$out"
  log "解密完成：$out"
}

########## 8. 列出已有密钥 ##########
list_keys(){
  echo -e "\n${BLUE}====== 公钥 ======${NC}"
  gpg --list-keys
  echo -e "\n${BLUE}====== 私钥 ======${NC}"
  gpg --list-secret-keys
}

########## 菜单循环 ##########
while true; do
  echo -e "\n${BLUE}======== PGP 中文管家 ========${NC}"
  echo "1) 创建新密钥"
  echo "2) 导入密钥"
  echo "3) 导出公钥"
  echo "4) 导出私钥"
  echo "5) 删除密钥"
  echo "6) 加密（支持分卷）"
  echo "7) 解密（自动识别分卷）"
  echo "8) 查看已有密钥"
  echo "9) 退出"
  read -rp "选择操作（1-9）：" c

  case $c in
    1) create_key ;;
    2) import_key ;;
    3) export_pub_key ;;
    4) export_sec_key ;;
    5) delete_key ;;
    6) encrypt ;;
    7) decrypt ;;
    8) list_keys ;;
    9) log "bye~"; exit 0 ;;
    *) err "请输入有效数字。" ;;
  esac
done
