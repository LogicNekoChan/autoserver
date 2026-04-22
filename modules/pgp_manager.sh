#!/usr/bin/env bash
# ==========================================
# Ubuntu 交互式 PGP 密钥/文件管理器
# 终极版：加密 + 解密 + 签名 + 验签 + 批量处理
# 全程中文、自动处理引号、绝对路径、强容错
# ==========================================
set -euo pipefail
shopt -s nullglob

########## 依赖检查 ##########
for cmd in gpg tar; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装：sudo apt install gnupg tar"; exit 1; }
done

########## 彩色输出 ##########
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }
info() { echo -e "${BLUE}[信息]${NC} $*"; }

########## 安全读路径（自动去引号 + 绝对路径） ##########
read_path() {
  local _path
  read -rp "$1" _path
  _path="${_path%\"}"
  _path="${_path#\"}"
  [[ -e "$_path" ]] || { err "路径不存在：$_path"; return 1; }
  realpath "$_path"
}

########## 读取目录（批量专用） ##########
read_dir() {
  local _dir
  read -rp "$1" _dir
  _dir="${_dir%\"}"
  _dir="${_dir#\"}"
  [[ -d "$_dir" ]] || { err "不是有效目录：$_dir"; return 1; }
  realpath "$_dir"
}

########## 1. 创建密钥 ##########
create_key() {
  log "启动 GPG 完整密钥生成向导..."
  gpg --full-generate-key
}

########## 2. 导入密钥 ##########
import_key() {
  local asc
  asc=$(read_path "请输入密钥文件路径（.asc/.gpg）：")
  gpg --import "$asc"
  log "✅ 密钥导入完成"
}

########## 3. 导出公钥 ##########
export_pub_key() {
  local email out
  read -rp "请输入要导出的邮箱/ID：" email
  read -rp "保存文件名（默认 ${email}_pub.asc）：" out
  [[ -z "$out" ]] && out="${email}_pub.asc"
  gpg --armor --export "$email" > "$out"
  log "✅ 公钥已导出：$(realpath "$out")"
}

########## 4. 导出私钥 ##########
export_sec_key() {
  local email out
  read -rp "请输入要导出的邮箱/ID：" email
  read -rp "保存文件名（默认 ${email}_sec.asc）：" out
  [[ -z "$out" ]] && out="${email}_sec.asc"
  gpg --armor --export-secret-keys "$email" > "$out"
  warn "⚠️ 私钥已导出，请严格保密！路径：$(realpath "$out")"
}

########## 5. 删除密钥 ##########
delete_key() {
  local email
  read -rp "请输入要删除的邮箱/ID：" email
  gpg --delete-secret-and-public-keys "$email" 2>/dev/null \
    && log "✅ 密钥已删除" \
    || warn "删除失败（可能不存在或已取消）"
}

########## 6. 单个加密（文件/目录） ##########
encrypt_single() {
  local target recipient dir name
  target=$(read_path "请输入要加密的文件/目录：")
  read -rp "接收者邮箱：" recipient

  dir=$(dirname "$target")
  name=$(basename "$target")
  cd "$dir"

  if [[ -d "$name" ]]; then
    info "检测到目录，自动打包加密..."
    tar czf - "$name" | gpg -e -r "$recipient" -o "${name}.tar.gz.gpg"
    log "✅ 加密完成：${name}.tar.gz.gpg"
  else
    gpg -e -r "$recipient" -o "${name}.gpg" "$name"
    log "✅ 加密完成：${name}.gpg"
  fi
}

########## 7. 单个解密 ##########
decrypt_single() {
  local gpg_file dir name
  gpg_file=$(read_path "请输入 .gpg 加密文件路径：")
  dir=$(dirname "$gpg_file")
  name=$(basename "$gpg_file")
  cd "$dir"

  if [[ "$name" == *.tar.gz.gpg ]]; then
    info "检测为目录包，自动解压还原..."
    gpg -d "$name" | tar xzf -
    log "✅ 目录解密解压完成"
  else
    local out="${name%.gpg}"
    gpg -d "$name" > "$out"
    log "✅ 文件解密完成：$out"
  fi
}

########## 8. 批量加密（整个目录所有文件） ##########
encrypt_batch() {
  local src_dir recipient out_dir files count=0

  src_dir=$(read_dir "请输入**待加密文件所在目录**：")
  read -rp "接收者邮箱：" recipient
  read -rp "请输入加密后输出目录（默认：./encrypted）：" out_dir
  [[ -z "$out_dir" ]] && out_dir="./encrypted"
  mkdir -p "$out_dir"
  out_dir=$(realpath "$out_dir")

  info "开始批量加密，目录：$src_dir"
  files=("$src_dir"/*)

  for item in "${files[@]}"; do
    name=$(basename "$item")
    if [[ -f "$item" && ! "$name" =~ \.gpg$ && ! "$name" =~ \.sig$ ]]; then
      gpg -e -r "$recipient" -o "$out_dir/$name.gpg" "$item"
      ((count++))
      log "已加密：$name"
    fi
  done

  log "✅ 批量加密完成！总计：$count 个文件 | 输出目录：$out_dir"
}

########## 9. 批量解密（整个目录所有 .gpg） ##########
decrypt_batch() {
  local src_dir out_dir files count=0

  src_dir=$(read_dir "请输入**存放 .gpg 文件的目录**：")
  read -rp "请输入解密后输出目录（默认：./decrypted）：" out_dir
  [[ -z "$out_dir" ]] && out_dir="./decrypted"
  mkdir -p "$out_dir"
  out_dir=$(realpath "$out_dir")

  info "开始批量解密，目录：$src_dir"
  files=("$src_dir"/*.gpg)

  for gpg_file in "${files[@]}"; do
    [[ -f "$gpg_file" ]] || continue
    name=$(basename "$gpg_file" .gpg)
    gpg -d "$gpg_file" > "$out_dir/$name"
    ((count++))
    log "已解密：$name"
  done

  log "✅ 批量解密完成！总计：$count 个文件 | 输出目录：$out_dir"
}

########## 10. GPG 签名文件（单独签名） ##########
sign_file() {
  local file signer out
  file=$(read_path "请输入要签名的文件：")
  read -rp "请输入签名者邮箱（你的私钥邮箱）：" signer
  out="${file}.sig"
  gpg --detach-sign -u "$signer" -o "$out" "$file"
  log "✅ 签名完成：$out"
  warn "⚠️ 请把【原文件 + .sig 签名文件】一起发给对方验证"
}

########## 11. GPG 验证签名 ##########
verify_sign() {
  local file
  file=$(read_path "请输入原文件（会自动找 .sig）：")
  info "正在验证签名有效性..."
  if gpg --verify "${file}.sig" "$file"; then
    log "✅ 验证通过！文件未篡改，签名有效"
  else
    err "❌ 验证失败！文件被篡改或签名无效"
  fi
}

########## 12. 签名 + 加密（最安全） ##########
sign_encrypt() {
  local file recipient signer out
  file=$(read_path "请输入要签名加密的文件：")
  read -rp "签名者邮箱（你）：" signer
  read -rp "接收者邮箱（对方）：" recipient
  out="${file}.gpg"
  gpg -u "$signer" -e -r "$recipient" -s -o "$out" "$file"
  log "✅ 已签名并加密：$out"
}

########## 13. 解密 + 验签（完整验证） ##########
decrypt_verify() {
  local file out
  file=$(read_path "请输入 .gpg 加密签名文件：")
  out="${file%.gpg}"
  info "正在解密并验证签名..."
  if gpg -d -o "$out" "$file"; then
    log "✅ 解密成功 + 签名验证通过"
  else
    err "❌ 解密或验签失败"
  fi
}

########## 14. 查看密钥 ##########
list_keys() {
  echo -e "\n${BLUE}====== 公钥列表 ======${NC}"
  gpg --list-keys
  echo -e "\n${BLUE}====== 私钥列表 ======${NC}"
  gpg --list-secret-keys
}

########## 主菜单 ##########
while true; do
  echo -e "\n${BLUE}======== PGP 中文管家（终极签名版）========${NC}"
  echo "1) 创建新密钥"
  echo "2) 导入密钥"
  echo "3) 导出公钥"
  echo "4) 导出私钥"
  echo "5) 删除密钥"
  echo "6) 单个加密（文件/目录）"
  echo "7) 单个解密"
  echo "8) 批量加密"
  echo "9) 批量解密"
  echo "10) 单独签名文件（生成 .sig）"
  echo "11) 验证文件签名"
  echo "12) 签名+加密一体（最安全）"
  echo "13) 解密+验签一体"
  echo "14) 查看所有密钥"
  echo "15) 退出"
  read -rp "请选择操作（1-15）：" choice

  case $choice in
    1) create_key ;;
    2) import_key ;;
    3) export_pub_key ;;
    4) export_sec_key ;;
    5) delete_key ;;
    6) encrypt_single ;;
    7) decrypt_single ;;
    8) encrypt_batch ;;
    9) decrypt_batch ;;
    10) sign_file ;;
    11) verify_sign ;;
    12) sign_encrypt ;;
    13) decrypt_verify ;;
    14) list_keys ;;
    15) log "👋 再见！"; exit 0 ;;
    *) err "请输入 1-15 之间的数字" ;;
  esac
done
