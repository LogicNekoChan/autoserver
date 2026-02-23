#!/usr/bin/env bash
# ==========================================
# Ubuntu PGP 中文管家 v4.5（完全对齐 Win Gpg4win）
# 目录加密：文件夹.tar → 文件夹.tar.gpg
# 文件加密：文件 → 文件.gpg
# ==========================================
set -euo pipefail

########## 依赖检查 + 自动安装 ##########
DEPS=(gpg tar pv realpath file)
declare -A CMD2PKG=(
    [gpg]=gnupg
    [tar]=tar
    [pv]=pv
    [realpath]=coreutils
    [file]=file
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

########## 加密（完全对齐 Win Gpg4win）##########
encrypt(){
    local target recipient idx basename out_dir final_path
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

    if [[ -d "$target" ]]; then
        # Win Gpg4win 目录加密：文件夹.tar.gpg
        final_path="${out_dir}/${basename}.tar.gpg"
        local total_size=$(du -sb "$target" | awk '{print $1}')
        
        log "📦 正在打包加密目录：${basename}.tar.gpg"
        log "🔐 流程：tar → ZIP压缩 → AES256"
        
        # tar 打包 → gpg 加密（ZIP压缩算法）
        tar -cf - -C "$(dirname "$target")" "$(basename "$target")" \
          | pv -s "$total_size" \
          | gpg --cipher-algo AES256 \
                --compress-algo 1 \
                --compress-level 6 \
                --digest-algo SHA256 \
                -e -r "$recipient" -o "$final_path"
    else
        # Win Gpg4win 文件加密：文件.gpg
        final_path="${out_dir}/${basename}.gpg"
        
        log "🔄 正在加密文件：${basename}.gpg"
        log "🔐 算法：AES256（无压缩）"
        
        pv "$target" \
          | gpg --cipher-algo AES256 \
                --digest-algo SHA256 \
                -e -r "$recipient" -o "$final_path"
    fi

    log "✅ 加密完成：$(realpath "$final_path")"
    log "💡 与 Windows Gpg4win / Kleopatra 完全兼容"
}

########## 解密（完全对齐 Win Gpg4win）##########
decrypt_core(){
    local input_file="$1" output_action="$2" pass
    log "🔑 请输入您的私钥密码："
    read -rs pass; echo
    
    if ! echo "$pass" | gpg --batch --yes \
            --pinentry-mode loopback \
            --passphrase-fd 0 \
            --allow-multiple-messages \
            --ignore-mdc-error \
            -d "$input_file" 2>/tmp/gpg_err | eval "$output_action"; then
        
        err "解密失败"
        [[ -s /tmp/gpg_err ]] && warn "GPG 错误：$(cat /tmp/gpg_err)"
        rm -f /tmp/gpg_err
        return 1
    fi
    rm -f /tmp/gpg_err
}

decrypt_single(){
    local file="$1" out_dir temp_dir output_file basename_full
    basename_full=$(basename "$file")
    out_dir=$(dirname "$file")
    temp_dir=$(mktemp -d)
    output_file="$temp_dir/output"
    
    log "🔓 正在解密：$basename_full"
    if ! decrypt_core "$file" "cat > \"$output_file\""; then
        rm -rf "$temp_dir"
        return 1
    fi
    
    # 根据文件名判断类型
    if [[ "$basename_full" == *.tar.gpg ]]; then
        # Win Gpg4win 目录加密格式
        log "💡 检测到目录加密格式（.tar.gpg），正在解压..."
        tar -xf "$output_file" -C "$out_dir"
        log "✅ 目录已解密到：$out_dir"
    else
        # 普通文件
        local out_name="${basename_full%.gpg}"
        [[ -e "$out_dir/$out_name" ]] && out_name="${out_name}.decrypted"
        mv "$output_file" "$out_dir/$out_name"
        log "✅ 文件已解密：$out_dir/$out_name"
    fi
    
    rm -rf "$temp_dir"
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
    echo -e "\n${BLUE}======== PGP 中文管家 v4.5（Win Gpg4win 对齐版）========${NC}"
    echo "1) 创建新密钥"
    echo "2) 导入密钥"
    echo "3) 导出公钥"
    echo "4) 导出私钥"
    echo "5) 删除密钥"
    echo "6) 加密（目录→.tar.gpg，文件→.gpg）"
    echo "7) 解密（自动识别 .tar.gpg / .gpg）"
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
        7) f=$(read_path "请输入要解密的 .gpg 或 .tar.gpg 文件：") || continue
           decrypt_auto "$f" ;;
        8) list_keys ;;
        9) log "bye~"; exit 0 ;;
        *) err "请输入有效数字 1-9" ;;
    esac
done
