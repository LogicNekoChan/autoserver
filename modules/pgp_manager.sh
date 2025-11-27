#!/usr/bin/env bash
# ==========================================
# Ubuntu PGP 中文管家 v3.4（优化版 - 支持空格/不签名/一次授权解密）
# ==========================================
set -euo pipefail

########## 依赖检查 ##########
for cmd in gpg tar pv split realpath; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装：sudo apt install gnupg tar pv coreutils"; exit 1; }
done

########## 彩色输出 ##########
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }

########## 路径读取 ##########
# 注意：realpath "$_p" 的输出已正确处理了路径中的空格
read_path(){
    local _p
    read -rp "$1" _p
    _p="${_p%\"}"; _p="${_p#\"}"
    [[ -e "$_p" ]] || { err "路径不存在：$_p"; return 1; }
    realpath "$_p"
}

########## 邮箱读取 ##########
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
    # 优化点：引用 $asc
    gpg --import "$asc"
    log "✅ 已导入"
}

########## 3. 导出公钥 ##########
export_pub_key(){
    local email out
    email=$(read_email "请输入要导出的邮箱：")
    read -rp "保存为（默认 ${email}_pub.asc）： " out
    [[ -z "$out" ]] && out="${email}_pub.asc"
    # 优化点：引用 $out
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
    # 优化点：引用 $out
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
    local target recipient idx basename out_dir split_mb temp_file merged_file
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
    # 优化点：引用 $out_dir
    mkdir -p "$out_dir"

    read -rp "是否分卷？输入 MB 大小（留空使用默认 2000MB）： " split_mb
    [[ -z "$split_mb" ]] && split_mb=2000

    temp_file="$(mktemp -u --suffix=.tar.gz)"
    merged_file="$(mktemp -u --suffix=.gpg)"

    # 打包目录或文件 (优化点：引用 $temp_file 和 $target)
    if [[ -d "$target" ]]; then
        tar -czf "$temp_file" -C "$(dirname "$target")" "$(basename "$target")"
    else
        cp -a "$target" "$temp_file"
    fi

    # 一次性公钥加密 (优化点：引用 $merged_file 和 $temp_file)
    log "🔐 正在加密..."
    gpg --no-sign -e -r "$recipient" -o "$merged_file" "$temp_file"
    rm -f "$temp_file"

    # 分卷 (优化点：引用 $merged_file 和 $out_dir/${basename})
    log "✂️ 正在分卷..."
    split -b "${split_mb}M" "$merged_file" "${out_dir}/${basename}.part"
    rm -f "$merged_file"

    log "✅ 分卷加密完成，存放在：$out_dir"
}

########## 解密的核心函数 ##########
decrypt_core(){
    local input_file output_action
    input_file="$1"
    output_action="$2"
    local pass

    log "🔑 请输入您的私钥密码（一次授权）："
    read -rs pass
    echo # 换行

    # 优化点：引用 $input_file，并传递密码给 GPG
    echo "$pass" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 -d "$input_file" | eval "$output_action"

    [[ $? -ne 0 ]] && { err "解密失败，密码错误或文件已损坏。"; return 1; }
}

########## 7. 解密 - 分卷 ##########
decrypt_split(){
    local first="$1"
    local dir base merged_file
    dir=$(dirname "$first")
    base=$(basename "$first" | sed 's/\.part.*$//')
    merged_file="$(mktemp -u --suffix=.gpg)"

    # 优化点：在 glob 匹配中引用路径 (虽然 nullglob 已经提升了安全性，但双引号保险)
    shopt -s nullglob
    parts=( "$dir/$base".part* )
    [[ ${#parts[@]} -eq 0 ]] && { err "未找到分卷"; return 1; }

    log "🔐 正在合并分卷..."
    : > "$merged_file"
    # 优化点：在 cat 命令中引用 $f
    for f in "${parts[@]}"; do
        cat "$f" >> "$merged_file"
    done

    log "📦 正在解密并解包..."
    # 调用核心解密函数，并确保 tar 解包目录 $dir 被引用
    decrypt_core "$merged_file" 'pv | tar xzf - -C "$dir"' || return 1

    rm -f "$merged_file"
    log "✅ 分卷已解密并解包"
}

########## 7. 解密 - 单文件 ##########
decrypt_single(){
    local file="$1"
    # 优化点：构造输出文件名时引用 $file
    local out="$file.decrypted"

    log "📦 正在解密..."
    # 调用核心解密函数，并确保输出文件 $out 被引用
    decrypt_core "$file" 'pv > "$out"' || return 1

    log "✅ 文件已解密：$out"
}

########## 7. 解密 - 自动判断 ##########
decrypt_auto(){
    local file="$1"
    if [[ "$file" =~ \.part ]]; then
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

########## 菜单 ##########
while true; do
    echo -e "\n${BLUE}======== PGP 中文管家 v3.4 优化版 ========${NC}"
    echo "1) 创建新密钥"
    echo "2) 导入密钥"
    echo "3) 导出公钥"
    echo "4) 导出私钥"
    echo "5) 删除密钥"
    echo "6) 加密（分卷/目录，不签名）"
    echo "7) 解密（自动识别，一次授权）"
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
            # 优化点：在调用 decrypt_auto 时引用 $f，防止路径空格导致参数分裂
            f=$(read_path "请输入要解密的 .gpg 文件（支持分卷）：") || continue
            decrypt_auto "$f" 
            ;;
        8) list_keys ;;
        9) log "bye~"; exit 0 ;;
        *) err "请输入有效数字 1-9" ;;
    esac
done
