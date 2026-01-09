#!/usr/bin/env bash
# ==========================================
# Ubuntu PGP 中文管家 v4.1（不分卷 / 自动装依赖 / 支持目录空格）
# ==========================================
set -euo pipefail

########## 依赖检查 + 自动安装 ##########
DEPS=(gpg tar pv realpath)
declare -A CMD2PKG=(
    [gpg]=gnupg
    [tar]=tar
    [pv]=pv
    [realpath]=coreutils
)
MISS=()
for c in "${DEPS[@]}"; do
    command -v "$c" &>/dev/null || MISS+=("${CMD2PKG[$c]}")
done
if ((${#MISS[@]})); then
    read -rp "🚀 检测到缺失依赖：${MISS[*]} ，是否立即安装？(yes/no) " ok
    [[ "$ok" == "yes" ]] || { echo "❌ 已取消，请手动安装后重试"; exit 1; }
    sudo apt update -qq && sudo apt install -y "${MISS[@]}" || {
        echo "❌ 自动安装失败，请检查网络或手动执行：sudo apt install ${MISS[*]}" >&2
        exit 1
    }
    echo "✅ 依赖已补装完成，继续运行脚本"
fi

########## 彩色输出 ##########
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }

########## 路径 / 邮箱读取 ##########
read_path(){
    local _p
    read -rp "$1" _p
    _p="${_p%\"}"; _p="${_p#\"}"
    [[ -e "$_p" ]] || { err "路径不存在：$_p"; return 1; }
    realpath "$_p"
}
read_email(){
    local email
    while true; do
        read -rp "$1" email
        [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && echo "$email" && return
        err "请输入有效邮箱，例如 user@example.com"
    done
}

########## 密钥管理 ##########
create_key(){ gpg --full-generate-key; }
import_key(){
    local asc=$(read_path "请输入密钥文件路径：") || return 1
    gpg --import "$asc" && log "✅ 已导入"
}
export_pub_key(){
    local email=$(read_email "请输入要导出的邮箱：")
    local out
    read -rp "保存为（默认 ${email}_pub.asc）： " out
    [[ -z "$out" ]] && out="${email}_pub.asc"
    gpg --armor --export "$email" > "$out"
    log "✅ 公钥已导出：$(realpath "$out")"
}
export_sec_key(){
    local email=$(read_email "请输入要导出的邮箱：")
    warn "⚠️ 私钥导出非常危险，请妥善保管！"
    read -rp "确认继续？(yes/no)：" c
    [[ "$c" != "yes" ]] && { warn "已取消"; return; }
    local out
    read -rp "保存为（默认 ${email}_sec.asc）： " out
    [[ -z "$out" ]] && out="${email}_sec.asc"
    gpg --armor --export-secret-keys "$email" > "$out"
    log "⚠️ 私钥已导出：$(realpath "$out")"
}
delete_key(){
    local email=$(read_email "请输入要删除的邮箱：")
    warn "⚠️ 将删除公钥+私钥，不可恢复！"
    read -rp "确认执行？(yes/no)：" c
    [[ "$c" != "yes" ]] && { warn "已取消"; return; }
    gpg --batch --yes --delete-secret-and-public-keys "$email" \
        && log "✅ 已删除" || warn "密钥不存在或已取消"
}
get_all_uids(){
    gpg --list-keys --with-colons | awk -F: '$1=="uid"{print $10}' | sed 's/.*<\(.*\)>.*/\1/'
}
list_keys(){
    echo -e "\n${BLUE}====== 公钥 ======${NC}"
    gpg --list-keys
    echo -e "\n${BLUE}====== 私钥 ======${NC}"
    gpg --list-secret-keys
}

########## 加密（不分卷 / 自动压缩目录） ##########
encrypt(){
    local target recipient idx basename out_dir temp_file final_path
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

    target=$(read_path "请输入要加密的文件或目录：")
    basename=$(basename "$target")

    read -rp "加密输出目录（直接回车使用源目录）： " out_dir
    [[ -z "$out_dir" ]] && out_dir="$(dirname "$target")"
    mkdir -p "$out_dir"

    temp_file="$(mktemp -u)"

    # 目录打包 | 单文件复用
    if [[ -d "$target" ]]; then
        temp_file+=".tar.gz"
        log "📦 正在打包目录 (Gzip 压缩)..."
        tar -czf "$temp_file" -C "$(dirname "$target")" "$(basename "$target")"
    else
        log "🔄 复制文件到临时位置..."
        cp -a "$target" "$temp_file"
    fi

    # 一次性加密
    final_path="${out_dir}/${basename}$([[ -d "$target" ]] && echo ".tar.gz").gpg"
    log "🔐 正在加密..."
    pv "$temp_file" | gpg --no-sign -e -r "$recipient" -o "$final_path"

    rm -f "$temp_file"
    log "✅ 加密完成：$(realpath "$final_path")"
    [[ -d "$target" ]] && \
        log "📢 提醒：对方解密后会得到 .tar.gz 文件，需手动解压一次。"
}

########## 解密 ##########
decrypt_core(){
    local input_file="$1" output_action="$2" pass
    log "🔑 请输入您的私钥密码（一次授权）："
    read -rs pass; echo
    echo "$pass" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 -d "$input_file" | eval "$output_action"
    [[ $? -ne 0 ]] && { err "解密失败，密码错误或文件已损坏。"; return 1; }
}
decrypt_single(){
    local file="$1" out basename_no_gpg
    basename_no_gpg=$(basename "$file" .gpg)
    if [[ "$basename_no_gpg" =~ \.tar\.gz$ ]]; then
        log "💡 检测到 .tar.gz 格式 (压缩目录)，正在解包到 $(dirname "$file")..."
        decrypt_core "$file" 'pv | tar xzf - -C "$(dirname "$file")"' || return 1
        log "✅ 文件已解密并解包"
    else
        out="$(dirname "$file")/${basename_no_gpg}.decrypted"
        decrypt_core "$file" 'pv > "$out"' || return 1
        log "✅ 文件已解密：$(realpath "$out")"
    fi
}
decrypt_auto(){
    local file="$1"
    if [[ "$file" =~ \.part[a-z][a-z]$ ]]; then
        log "检测到分卷文件，将合并解密..."
        local dir=$(dirname "$file") base_no_part=$(basename "$file" | sed 's/\.part.*$//') merged=$(mktemp --suffix=.gpg)
        cat "$dir/$base_no_part".part* > "$merged"
        decrypt_single "$merged"
        rm -f "$merged"
        log "✅ 分卷合并和解密完成"
    else
        decrypt_single "$file"
    fi
}

########## 菜单 ##########
while true; do
    echo -e "\n${BLUE}======== PGP 中文管家 v4.1 ========${NC}"
    echo "1) 创建新密钥"
    echo "2) 导入密钥"
    echo "3) 导出公钥"
    echo "4) 导出私钥"
    echo "5) 删除密钥"
    echo "6) 加密（文件/目录，自动压缩，不分卷）"
    echo "7) 解密（自动识别分卷/单文件）"
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
        7) f=$(read_path "请输入要解密的 .gpg 文件（或第一个分卷 *.partaa）：") || continue
           decrypt_auto "$f" ;;
        8) list_keys ;;
        9) log "bye~"; exit 0 ;;
        *) err "请输入有效数字 1-9" ;;
    esac
done
