#!/usr/bin/env bash
# ==========================================
# Ubuntu PGP 中文管家 v3.6（压缩优化版 - 支持文件/目录加密，目录使用 Gzip 压缩）
# ==========================================
set -euo pipefail

########## 依赖检查 ##########
for cmd in gpg tar pv realpath; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装：sudo apt install gnupg tar pv coreutils"; exit 1; }
done

########## 彩色输出 ##########
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }

########## 路径读取 ##########
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
    local target recipient idx basename out_dir out_file temp_file target_to_encrypt
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
    
    # 如果加密的是目录，先打包成 .tar.gz (带 Gzip 压缩，压缩效果好)
    if [[ -d "$target" ]]; then
        temp_file="$(mktemp -u --suffix=.tar.gz)" # 使用 .tar.gz 
        out_file="${out_dir}/${basename}.tar.gz.gpg" # 输出文件名带 .tar.gz 提示接收方
        log "📦 正在打包目录 (启用 Gzip 压缩)..."
        # 使用 tar -czf (带 z) 
        tar -czf "$temp_file" -C "$(dirname "$target")" "$(basename "$target")"
        target_to_encrypt="$temp_file"
    else
        # 加密文件
        out_file="${out_dir}/${basename}.gpg"
        target_to_encrypt="$target"
    fi

    # 公钥加密
    log "🔐 正在加密..."
    pv "$target_to_encrypt" | gpg --no-sign -e -r "$recipient" -o "$out_file"

    # 清理临时文件
    [[ -v temp_file ]] && rm -f "$temp_file"

    log "✅ 加密完成，文件存放在：$(realpath "$out_file")"
    [[ -d "$target" ]] && log "📢 提醒：您加密的是目录，接收方在 Windows 上解密后会得到一个 **.tar.gz** 文件，需要手动解压一次。"
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

    # 传递密码给 GPG，并通过 pipe 交给 output_action 处理
    echo "$pass" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 -d "$input_file" | eval "$output_action"

    [[ $? -ne 0 ]] && { err "解密失败，密码错误或文件已损坏。"; return 1; }
}

########## 7. 解密 ##########
decrypt(){
    local file="$1"
    local out dir basename
    dir=$(dirname "$file")
    basename=$(basename "$file" .gpg)

    log "📦 正在解密..."
    
    # 判断解密输出是否为 .tar.gz 包 (用于解密目录的情况)
    if [[ "$basename" =~ \.tar\.gz$ ]]; then
        # 解密并解包目录
        log "💡 检测到 .tar.gz 格式 (压缩目录)，正在解包到 $dir..."
        # 调用核心解密函数，并确保 tar 解包目录 $dir 被引用
        # 使用 tar xzf (带 z) 来解压压缩的 tar.gz 文件
        decrypt_core "$file" 'pv | tar xzf - -C "$dir"' || return 1
        log "✅ 文件已解密并解包"
    else
        # 解密单个文件
        out="${file%.gpg}.decrypted"
        # 调用核心解密函数，并确保输出文件 $out 被引用
        decrypt_core "$file" 'pv > "$out"' || return 1
        log "✅ 文件已解密：$(realpath "$out")"
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
    echo -e "\n${BLUE}======== PGP 中文管家 v3.6 压缩优化版 ========${NC}"
    echo "1) 创建新密钥"
    echo "2) 导入密钥"
    echo "3) 导出公钥"
    echo "4) 导出私钥"
    echo "5) 删除密钥"
    echo "6) 加密（文件/目录，高压缩率）"
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
            f=$(read_path "请输入要解密的 .gpg 文件：") || continue
            decrypt "$f" 
            ;;
        8) list_keys ;;
        9) log "bye~"; exit 0 ;;
        *) err "请输入有效数字 1-9" ;;
    esac
done
