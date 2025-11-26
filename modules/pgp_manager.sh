#!/usr/bin/env bash
# ==========================================
# Ubuntu PGP 中文管家 v3.2（支持分卷+空格+边打包边加密+一次授权+公钥加密）
# 默认分卷 2000MB
# ==========================================
set -euo pipefail

########## 依赖检查 ##########
for cmd in gpg tar pv split realpath; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装：sudo apt install gnupg tar pv coreutils"; exit 1; }
done

########## 彩色输出 ##########
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }

########## 读取路径（去引号+转绝对路径） ##########
read_path(){
    local _p
    read -rp "$1" _p
    _p="${_p%\"}"; _p="${_p#\"}"
    [[ -e "$_p" ]] || { err "路径不存在：$_p"; return 1; }
    realpath "$_p"
}

########## 邮箱校验 ##########
read_email(){
    local email
    while true; do
        read -rp "$1" email
        [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && echo "$email" && return
        err "请输入有效邮箱，例如 user@example.com"
    done
}

########## 1. 创建密钥 ##########
create_key(){ gpg --full-generate-key; }

########## 2. 导入密钥 ##########
import_key(){
    local asc
    asc=$(read_path "请输入密钥文件路径：") || return 1
    gpg --import "$asc"
    log "✅ 已导入"
}

########## 3. 导出公钥 ##########
export_pub_key(){
    local email out
    email=$(read_email "请输入要导出的邮箱：")
    read -rp "保存为（默认 ${email}_pub.asc）： " out
    [[ -z "$out" ]] && out="${email}_pub.asc"
    gpg --armor --export "$email" > "$out"
    log "✅ 公钥已导出：$(realpath "$out")"
}

########## 4. 导出私钥 ##########
export_sec_key(){
    local email out
    email=$(read_email "请输入要导出的邮箱：")
    warn "⚠️ 私钥导出非常危险，请妥善保管！"
    read -rp "确认继续？(yes/no)：" c
    [[ "$c" != "yes" ]] && { warn "已取消"; return; }
    read -rp "保存为（默认 ${email}_sec.asc）： " out
    [[ -z "$out" ]] && out="${email}_sec.asc"
    gpg --armor --export-secret-keys "$email" > "$out"
    log "⚠️ 私钥已导出：$(realpath "$out")"
}

########## 5. 删除密钥 ##########
delete_key(){
    local email
    email=$(read_email "请输入要删除的邮箱：")
    warn "⚠️ 将删除公钥+私钥，不可恢复！"
    read -rp "确认执行？(yes/no)：" c
    [[ "$c" != "yes" ]] && { warn "已取消"; return; }
    gpg --batch --yes --delete-secret-and-public-keys "$email" \
        && log "✅ 已删除" || warn "密钥不存在或已取消"
}

########## 获取本地公钥列表 ##########
get_all_uids(){
    gpg --list-keys --with-colons | awk -F: '$1=="uid"{print $10}' | sed 's/.*<\(.*\)>.*/\1/'
}

########## 6. 加密 ##########
encrypt(){
    local target recipient idx basename out_dir split_mb split_bytes temp_file prefix parts

    # 列出接收者
    mapfile -t keys < <(get_all_uids)
    (( ${#keys[@]} == 0 )) && { warn "无可用公钥，请先导入或创建"; return 1; }
    echo -e "\n${BLUE}====== 本地公钥列表 ======${NC}"
    for i in "${!keys[@]}"; do printf " %2d) %s\n" $((i+1)) "${keys[i]}"; done

    while true; do
        read -rp "请选择接收者编号（1-${#keys[@]}）： " idx
        [[ "$idx" =~ ^[0-9]+$ ]] && (( idx>=1 && idx<=${#keys[@]} )) && break
        err "无效编号"
    done
    recipient="${keys[$((idx-1))]}"

    # 读取文件/目录
    target=$(read_path "请输入要加密的文件或目录：")
    basename=$(basename "$target")

    # 输出目录
    read -rp "加密输出目录（默认源目录）： " out_dir
    [[ -z "$out_dir" ]] && out_dir="$(dirname "$target")"
    mkdir -p "$out_dir"

    # 分卷大小（默认2000MB）
    read -rp "是否自定义分卷大小 MB（默认2000）： " split_mb
    [[ -z "$split_mb" ]] && split_mb=2000
    split_bytes="${split_mb}M"

    # 临时文件
    temp_file="$out_dir/${basename}.tar.gz.gpg"

    # ---- 打包并公钥加密 ----
    if [[ -d "$target" ]]; then
        tar -czf - -C "$(dirname "$target")" "$(basename "$target")" | pv \
            | gpg -e -r "$recipient" -o "$temp_file"
    else
        pv "$target" | gpg -e -r "$recipient" -o "$temp_file"
    fi

    # ---- 分卷 ----
    prefix="$out_dir/${basename}.part"
    split -b "$split_bytes" "$temp_file" "$prefix"
    rm -f "$temp_file"

    log "✅ 分卷加密完成，存放在：$out_dir"
}

########## 7. 解密 ##########
decrypt_single(){
    local file="$1" out="${file%.gpg}"
    pv "$file" | gpg --batch --yes -d > "$out"
    log "✅ 文件已解密：$out"
}

decrypt_split(){
    local first="$1"
    local dir base temp_file
    dir=$(dirname "$first")
    base=$(basename "$first" | sed 's/\.part.*\.gpg$//')
    temp_file="$dir/$base.tar.gz"

    shopt -s nullglob
    # 使用数组，避免空格问题
    local parts=( "$dir/$base".part*.gpg )
    [[ ${#parts[@]} -eq 0 ]] && { err "未找到分卷"; return 1; }

    : > "$temp_file"
    for f in "${parts[@]}"; do
        gpg --batch --yes -d "$f" | pv >> "$temp_file"
    done

    tar xzf "$temp_file" -C "$dir"
    rm -f "$temp_file"
    log "✅ 分卷已解密并解包"
}

decrypt_auto(){
    local file="$1"
    if [[ "$file" =~ \.part.*\.gpg$ ]]; then
        decrypt_split "$file"
    else
        decrypt_single "$file"
    fi
}

########## 8. 列出密钥 ##########
list_keys(){
    echo -e "\n${BLUE}====== 公钥 ======${NC}"
    gpg --list-keys
    echo -e "\n${BLUE}====== 私钥 ======${NC}"
    gpg --list-secret-keys
}

########## 菜单循环 ##########
while true; do
    echo -e "\n${BLUE}======== PGP 中文管家 v3.2 ========${NC}"
    echo "1) 创建新密钥"
    echo "2) 导入密钥"
    echo "3) 导出公钥"
    echo "4) 导出私钥"
    echo "5) 删除密钥"
    echo "6) 加密（支持目录/分卷，默认2000MB）"
    echo "7) 解密（自动识别分卷）"
    echo "8) 查看已有密钥"
    echo "9) 退出"
    read -rp "请选择操作（1-9）： " c

    case $c in
        1) create_key ;;
        2) import_key ;;
        3) export_pub_key ;;
        4) export_sec_key ;;
        5) delete_key ;;
        6) encrypt ;;
        7)
            f=$(read_path "请输入要解密的 .gpg 文件（支持分卷）：")
            decrypt_auto "$f"
            ;;
        8) list_keys ;;
        9) log "bye~"; exit 0 ;;
        *) err "请输入有效数字 1-9" ;;
    esac
done
