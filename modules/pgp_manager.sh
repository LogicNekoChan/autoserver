#!/usr/bin/env bash
# ==========================================
# Ubuntu 交互式 PGP 密钥/文件管理器
# 新增：导出公钥 & 导出私钥 分离
# 全程中文、自动引号、目录级相对路径
# ==========================================
set -euo pipefail

########## 依赖检查 ##########
for cmd in gpg tar; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装：sudo apt install gnupg tar"; exit 1; }
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

########## 1. 创建密钥 ##########
create_key(){
  log "启动 GPG 全量密钥生成向导..."
  gpg --full-generate-key
}

########## 2. 导入密钥 ##########
import_key(){
  local asc
  asc=$(read_path "请输入密钥文件路径（.asc/.gpg）：")
  gpg --import "$asc"
  log "✅ 已导入"
}

########## 3. 导出公钥 ##########
export_pub_key(){
  local email out
  read -rp "要导出的邮箱： " email
  read -rp "保存到哪个文件（直接回车默认 ${email}_pub.asc）： " out
  [[ -z "$out" ]] && out="${email}_pub.asc"
  gpg --armor --export "$email" > "$out"
  log "✅ 公钥已导出到 $(realpath "$out")"
}

########## 4. 导出私钥 ##########
export_sec_key(){
  local email out
  read -rp "要导出的邮箱： " email
  read -rp "保存到哪个文件（直接回车默认 ${email}_sec.asc）： " out
  [[ -z "$out" ]] && out="${email}_sec.asc"
  gpg --armor --export-secret-keys "$email" > "$out"
  log "⚠️  私钥已导出到 $(realpath "$out")，请妥善保管！"
}

########## 5. 删除密钥 ##########
delete_key(){
  local email
  read -rp "要删除的邮箱： " email
  gpg --delete-secret-and-public-keys "$email" 2>/dev/null && log "✅ 已删除" || warn "可能已取消或密钥不存在"
}
########## 6. 加密（带编号选择） ##########
encrypt(){
  local target recipient target_dir basename idx n

  #---- 1. 先列出本地公钥，带编号 ----#
  echo -e "\n${BLUE}====== 本地公钥列表 ======${NC}"
  mapfile -t keys < <(gpg --list-keys --with-colons \
      | awk -F: '$1=="uid"{print $10}' | sed 's/.*<\(.*\)>.*/\1/')
  n=${#keys[@]}
  if (( n==0 )); then
    warn "本地没有任何公钥，请先创建或导入公钥！"
    return 1
  fi
  for i in "${!keys[@]}"; do
    printf "  %2d) %s\n" $((i+1)) "${keys[i]}"
  done

  #---- 2. 让用户选编号 ----#
  while true; do
    read -rp "请选择接收者编号（1-$n）：" idx
    [[ "$idx" =~ ^[0-9]+$ ]] && (( idx>=1 && idx<=n )) && break
    err "请输入 1-$n 之间的有效编号！"
  done
  recipient="${keys[$((idx-1))]}"

  #---- 3. 读文件/目录路径 ----#
  target=$(read_path "要加密的文件或文件夹：")
  target_dir=$(dirname "$target")
  basename=$(basename "$target")
  cd "$target_dir"

  #---- 4. 加密逻辑（同原来） ----#
  if [[ -d "$basename" ]]; then
    log "检测到目录，正在打包并加密..."
    tar czf - "$basename" | gpg --progress -e -r "$recipient" > "${basename}.tar.gz.gpg"
    log "✅ 已生成 ${basename}.tar.gz.gpg"
  else
    gpg --progress -e -r "$recipient" -o "${basename}.gpg" "$basename"
    log "✅ 已生成 ${basename}.gpg"
  fi
}
########## 7. 解密 ##########
decrypt(){
  local gpg_file dir basename
  gpg_file=$(read_path "要解密的 .gpg 文件：")
  dir=$(dirname "$gpg_file")
  basename=$(basename "$gpg_file")
  cd "$dir"

  if [[ "$basename" == *.tar.gz.gpg ]]; then
    log "检测到目录包，正在解密并解压..."
    gpg --progress -d "$basename" | tar xzf -
    log "✅ 目录已恢复"
  else
    local out="${basename%.gpg}"
    gpg --progress -d "$basename" > "$out"
    log "✅ 文件已解密为 $out"
  fi
}

########## 8. 列出密钥 ##########
list_keys(){
  echo -e "\n${BLUE}====== 公钥列表 ======${NC}"
  gpg --list-keys
  echo -e "\n${BLUE}====== 私钥列表 ======${NC}"
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
  echo "6) 加密文件/文件夹"
  echo "7) 解密文件/文件夹"
  echo "8) 查看已有密钥"
  echo "9) 退出"
  read -rp "请选择操作（1-9）：" choice
  case $choice in
    1) create_key ;;
    2) import_key ;;
    3) export_pub_key ;;
    4) export_sec_key ;;
    5) delete_key ;;
    6) encrypt ;;
    7) decrypt ;;
    8) list_keys ;;
    9) log "bye~"; exit 0 ;;
    *) err "请输入 1-9 之间的数字" ;;
  esac
done
