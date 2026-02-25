#!/usr/bin/env bash
# ==========================================
# Ubuntu PGP 中文管家 v4.8（修复解密报错）
# 支持密码中的 !@#$%^&*() 等特殊字符
# 修复：gpg-agent loopback 配置自动检测
# ==========================================
set -euo pipefail

########## 依赖检查 + 自动安装 ##########
DEPS=(gpg tar pv realpath file shred)
declare -A CMD2PKG=(
    [gpg]=gnupg
    [tar]=tar
    [pv]=pv
    [realpath]=coreutils
    [file]=file
    [shred]=coreutils
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

########## GPG 环境初始化 ##########
init_gpg_env(){
    # 关键：设置终端环境变量
    export GPG_TTY=$(tty 2>/dev/null || echo "/dev/tty")
    
    # 检查并自动配置 gpg-agent
    local gpg_agent_conf="$HOME/.gnupg/gpg-agent.conf"
    local need_reload=false
    
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.gnupg"
    
    # 检查是否已启用 loopback pinentry
    if [[ ! -f "$gpg_agent_conf" ]] || ! grep -q "^allow-loopback-pinentry" "$gpg_agent_conf" 2>/dev/null; then
        warn "首次运行：自动配置 gpg-agent 以支持自动密码输入..."
        echo "allow-loopback-pinentry" >> "$gpg_agent_conf"
        need_reload=true
    fi
    
    # 检查 pinentry 程序
    if ! grep -q "^pinentry-program" "$gpg_agent_conf" 2>/dev/null; then
        # 自动检测可用的 pinentry
        if command -v pinentry-curses &>/dev/null; then
            echo "pinentry-program /usr/bin/pinentry-curses" >> "$gpg_agent_conf"
            need_reload=true
        elif command -v pinentry-tty &>/dev/null; then
            echo "pinentry-program /usr/bin/pinentry-tty" >> "$gpg_agent_conf"
            need_reload=true
        fi
    fi
    
    # 重启 gpg-agent 以应用配置
    if [[ "$need_reload" == true ]]; then
        gpg-connect-agent killagent /bye 2>/dev/null || true
        gpg-connect-agent /bye 2>/dev/null || true
        log "✅ gpg-agent 已配置并重启"
    fi
}

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

########## 获取所有密钥 UID ##########
get_all_uids(){
    gpg --list-keys --with-colons 2>/dev/null | \
    awk -F: '
        $1 == "uid" {
            if (match($0, /<[^>]+>/)) {
                email = substr($0, RSTART+1, RLENGTH-2)
                print email
            }
        }
    '
}
get_all_uids_simple(){
    gpg --list-keys 2>/dev/null | \
    grep -E "^uid" | \
    grep -oE "[^<]+@[^>]+" | \
    tr -d ' ' || true
}
list_keys(){
    echo -e "\n${BLUE}====== 公钥 ======${NC}"
    gpg --list-keys
    echo -e "\n${BLUE}====== 私钥 ======${NC}"
    gpg --list-secret-keys
}

########## 加密 ##########
encrypt(){
    local target recipient idx basename out_dir final_path
    local -a keys=()
    
    while IFS= read -r line; do
        [[ -n "$line" ]] && keys+=("$line")
    done < <(get_all_uids)
    
    if ((${#keys[@]} == 0)); then
        while IFS= read -r line; do
            [[ -n "$line" ]] && keys+=("$line")
        done < <(get_all_uids_simple)
    fi
    
    (( ${#keys[@]} == 0 )) && { warn "无可用公钥，请先导入或创建"; return 1; }

    echo -e "\n${BLUE}====== 本地公钥列表 ======${NC}"
    local i=1
    for key in "${keys[@]}"; do
        printf " %2d) %s\n" "$i" "$key"
        ((i++))
    done

    while true; do
        read -rp "请选择接收者编号（1-${#keys[@]}）： " idx
        [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#keys[@]} )) && break
        err "无效编号，请输入 1-${#keys[@]}"
    done
    recipient="${keys[$((idx-1))]}"
    
    log "✅ 已选择接收者：$recipient"

    target=$(read_path "请输入要加密的文件或目录：")
    basename=$(basename "$target")

    read -rp "加密输出目录（直接回车使用源目录）： " out_dir
    [[ -z "$out_dir" ]] && out_dir="$(dirname "$target")"
    mkdir -p "$out_dir"

    if [[ -d "$target" ]]; then
        final_path="${out_dir}/${basename}.tar.gpg"
        local total_size=$(du -sb "$target" | awk '{print $1}')
        
        log "📦 正在打包加密目录：${basename}.tar.gpg"
        
        tar -cf - -C "$(dirname "$target")" "$(basename "$target")" \
          | pv -s "$total_size" \
          | gpg --cipher-algo AES256 \
                --compress-algo 1 \
                --compress-level 6 \
                --digest-algo SHA256 \
                -e -r "$recipient" -o "$final_path"
    else
        final_path="${out_dir}/${basename}.gpg"
        
        log "🔄 正在加密文件：${basename}.gpg"
        
        pv "$target" \
          | gpg --cipher-algo AES256 \
                --digest-algo SHA256 \
                -e -r "$recipient" -o "$final_path"
    fi

    log "✅ 加密完成：$(realpath "$final_path")"
}

########## 解密（修复版）##########
decrypt_core(){
    local input_file="$1" output_action="$2"
    local pass_file pass ret=0
    
    # 初始化环境
    init_gpg_env
    
    log "🔑 请输入您的私钥密码（支持特殊字符）："
    read -rs pass
    echo  # 换行
    
    # 创建临时密码文件（使用内存文件系统更安全）
    pass_file=$(mktemp -p /dev/shm 2>/dev/null || mktemp)
    chmod 600 "$pass_file"
    
    # 关键：使用 printf '%s' 原样写入密码，不解释任何转义字符
    printf '%s' "$pass" > "$pass_file"
    
    # 关键修复：使用 --passphrase-file 配合 --pinentry-mode loopback
    # 移除 --batch 因为它会阻止某些必要的交互
    # 添加 --no-tty 确保在管道中也能正常工作
    if gpg --yes \
           --no-tty \
           --pinentry-mode loopback \
           --passphrase-file "$pass_file" \
           --allow-multiple-messages \
           --ignore-mdc-error \
           -d "$input_file" 2>/tmp/gpg_err | eval "$output_action"; then
        ret=0
    else
        ret=1
        err "解密失败"
        
        # 详细错误诊断
        if [[ -s /tmp/gpg_err ]]; then
            local err_msg=$(cat /tmp/gpg_err)
            warn "GPG 错误详情：$err_msg"
            
            if echo "$err_msg" | grep -q "No secret key"; then
                warn "💡 提示：找不到匹配的私钥，请先用选项 8 查看已导入的密钥"
            elif echo "$err_msg" | grep -q "Bad session key\|decryption failed"; then
                warn "💡 提示：密码错误或文件损坏"
            elif echo "$err_msg" | grep -q "pinentry-mode"; then
                warn "💡 提示：gpg-agent 配置未生效"
                warn "   请手动执行：echo 'allow-loopback-pinentry' >> ~/.gnupg/gpg-agent.conf"
                warn "   然后执行：gpg-connect-agent killagent /bye"
            elif echo "$err_msg" | grep -q "Permission denied"; then
                warn "💡 提示：文件权限不足"
            fi
        fi
    fi
    
    # 安全清理密码文件
    if command -v shred &>/dev/null; then
        shred -uz "$pass_file" 2>/dev/null || rm -f "$pass_file"
    else
        # 覆盖后再删除
        dd if=/dev/urandom of="$pass_file" bs=1 count=$(stat -c%s "$pass_file" 2>/dev/null || echo 1024) 2>/dev/null || true
        rm -f "$pass_file"
    fi
    rm -f /tmp/gpg_err
    
    return $ret
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
    
    if [[ "$basename_full" == *.tar.gpg ]]; then
        log "💡 检测到目录加密格式，正在解压..."
        tar -xf "$output_file" -C "$out_dir"
        log "✅ 目录已解密到：$out_dir"
    else
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

########## 环境诊断 ##########
diagnose_env(){
    echo -e "\n${BLUE}======== GPG 环境诊断 ========${NC}"
    echo "GPG 版本：$(gpg --version | head -1)"
    echo "GPG_TTY：${GPG_TTY:-未设置}"
    echo "当前 TTY：$(tty 2>/dev/null || echo '无')"
    echo ""
    echo "gpg-agent.conf 配置："
    cat "$HOME/.gnupg/gpg-agent.conf" 2>/dev/null || echo "  (文件不存在)"
    echo ""
    echo "私钥列表："
    gpg --list-secret-keys 2>/dev/null | grep -E "(sec|uid)" || echo "  (无私钥)"
    echo ""
    echo "测试 loopback 模式："
    if echo "test" | gpg --pinentry-mode loopback --symmetric --passphrase-fd 0 -o /dev/null 2>&1; then
        log "✅ loopback 模式可用"
    else
        err "❌ loopback 模式不可用，需要配置 allow-loopback-pinentry"
    fi
    echo ""
    read -rp "按回车键继续..."
}

########## 菜单 ##########
# 初始化环境
init_gpg_env

while true; do
    echo -e "\n${BLUE}======== PGP 中文管家 v4.8（修复解密报错）========${NC}"
    echo "1) 创建新密钥"
    echo "2) 导入密钥"
    echo "3) 导出公钥"
    echo "4) 导出私钥"
    echo "5) 删除密钥"
    echo "6) 加密（目录→.tar.gpg，文件→.gpg）"
    echo "7) 解密（支持特殊字符密码）"
    echo "8) 查看已有密钥"
    echo "9) 环境诊断"
    echo "0) 退出"
    read -rp "请选择操作（0-9）： " c

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
        9) diagnose_env ;;
        0) log "bye~"; exit 0 ;;
        *) err "请输入有效数字 0-9" ;;
    esac
done
