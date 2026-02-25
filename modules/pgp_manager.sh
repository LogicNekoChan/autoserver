#!/usr/bin/env bash
# ==========================================
# Ubuntu PGP 中文管家 v6.2（解密权限安全修复）
# 修复：跨文件系统原子写入、权限降级检测、多层级回退策略
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
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; CYAN='\033[35m'; NC='\033[0m'
log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }
info() { echo -e "${CYAN}[信息]${NC} $*"; }

########## 安全清理函数 ##########
cleanup_stack=()
cleanup_register() {
    cleanup_stack+=("$1")
}
cleanup_execute() {
    local i
    for ((i=${#cleanup_stack[@]}-1; i>=0; i--)); do
        eval "${cleanup_stack[$i]}" 2>/dev/null || true
    done
    cleanup_stack=()
}
trap 'cleanup_execute' EXIT INT TERM HUP

########## GPG 环境初始化 ##########
init_gpg_env(){
    export GPG_TTY=$(tty 2>/dev/null || echo "/dev/tty")
    
    local gpg_agent_conf="$HOME/.gnupg/gpg-agent.conf"
    local need_reload=false
    
    mkdir -p "$HOME/.gnupg"
    chmod 700 "$HOME/.gnupg"
    
    if [[ ! -f "$gpg_agent_conf" ]] || ! grep -q "^allow-loopback-pinentry" "$gpg_agent_conf" 2>/dev/null; then
        warn "首次运行：自动配置 gpg-agent..."
        echo "allow-loopback-pinentry" >> "$gpg_agent_conf"
        need_reload=true
    fi
    
    if [[ "$need_reload" == true ]]; then
        gpg-connect-agent killagent /bye 2>/dev/null || true
        gpg-connect-agent /bye 2>/dev/null || true
        log "✅ gpg-agent 已配置"
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
        err "请输入有效邮箱"
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
    warn "⚠️ 私钥导出危险，请妥善保管！"
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
    
    (( ${#keys[@]} == 0 )) && { warn "无可用公钥"; return 1; }

    echo -e "\n${BLUE}====== 本地公钥列表 ======${NC}"
    local i=1
    for key in "${keys[@]}"; do
        printf " %2d) %s\n" "$i" "$key"
        ((i++))
    done

    while true; do
        read -rp "请选择接收者编号（1-${#keys[@]}）： " idx
        [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#keys[@]} )) && break
        err "无效编号"
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
        log "📦 正在打包加密目录..."
        
        tar -cf - -C "$(dirname "$target")" "$(basename "$target")" \
          | pv -s "$total_size" \
          | gpg --cipher-algo AES256 -e -r "$recipient" -o "$final_path"
    else
        final_path="${out_dir}/${basename}.gpg"
        log "🔄 正在加密文件..."
        pv "$target" \
          | gpg --cipher-algo AES256 -e -r "$recipient" -o "$final_path"
    fi

    log "✅ 加密完成：$(realpath "$final_path")"
}

########## 安全密码输入 ##########
read_password_secure() {
    local prompt="${1:-请输入密码：}"
    local pass1 pass2
    
    while true; do
        echo -n "$prompt" >&2
        read -rs pass1
        echo "" >&2
        
        if [[ ${#pass1} -eq 0 ]]; then
            err "密码不能为空"
            continue
        fi
        
        if [[ "${2:-}" == "confirm" ]]; then
            echo -n "请再次输入密码确认：" >&2
            read -rs pass2
            echo "" >&2
            if [[ "$pass1" != "$pass2" ]]; then
                err "两次输入的密码不一致"
                continue
            fi
        fi
        
        printf '%s' "$pass1"
        return 0
    done
}

########## 创建安全密码文件 ##########
create_secure_passfile() {
    local password="$1"
    local pass_file
    
    if [[ -d /dev/shm ]] && [[ -w /dev/shm ]]; then
        pass_file=$(mktemp -p /dev/shm .gpg_pass.XXXXXX)
    else
        pass_file=$(mktemp .gpg_pass.XXXXXX)
        warn "⚠️ 无法使用内存存储密码，已使用磁盘临时文件"
    fi
    
    chmod 600 "$pass_file"
    printf '%s' "$password" > "$pass_file"
    echo "$pass_file"
}

########## 安全清理 ##########
secure_shred() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    
    local file_size
    file_size=$(stat -c%s "$file" 2>/dev/null || echo 1024)
    
    if command -v shred &>/dev/null; then
        shred -uz "$file" 2>/dev/null && return 0
    fi
    
    if [[ -w "$file" ]]; then
        dd if=/dev/urandom of="$file" bs=1 count="$file_size" 2>/dev/null || true
        sync
    fi
    rm -f "$file"
}

########## 智能临时目录选择（权限安全版）##########
select_temp_dir() {
    local target_dir="$1"
    local preferred_dir=""
    local temp_dir=""
    
    # 策略1：优先使用 $TMPDIR（通常是 /tmp，可跨文件系统）
    if [[ -n "${TMPDIR:-}" ]] && [[ -d "$TMPDIR" ]] && [[ -w "$TMPDIR" ]]; then
        preferred_dir="$TMPDIR"
    else
        preferred_dir="/tmp"
    fi
    
    # 检查目标目录是否可写（如果可写，尝试同文件系统以支持原子移动）
    if [[ -w "$target_dir" ]]; then
        # 检查是否在同一个文件系统（设备ID相同）
        local src_dev target_dev
        src_dev=$(stat -c %d "$preferred_dir" 2>/dev/null || echo 0)
        target_dev=$(stat -c %d "$target_dir" 2>/dev/null || echo 1)
        
        if [[ "$src_dev" == "$target_dev" ]]; then
            # 同文件系统，使用 /tmp（通常是 tmpfs，更快）
            temp_dir=$(mktemp -d -p "$preferred_dir" ".gpg_decrypt.XXXXXX")
        else
            # 跨文件系统，尝试在目标目录创建（为了原子移动）
            # 但先检查是否是只读挂载或其他限制
            if temp_dir=$(mktemp -d -p "$target_dir" ".gpg_decrypt.XXXXXX" 2>/dev/null); then
                info "使用目标目录临时空间（跨文件系统原子写入）"
            else
                # 目标目录无法创建临时文件，使用 /tmp 并接受跨文件系统拷贝
                temp_dir=$(mktemp -d -p "$preferred_dir" ".gpg_decrypt.XXXXXX")
                info "使用系统临时目录（跨文件系统移动）"
            fi
        fi
    else
        # 目标目录只读，必须使用其他位置
        temp_dir=$(mktemp -d -p "$preferred_dir" ".gpg_decrypt.XXXXXX")
        info "目标目录只读，使用系统临时目录"
    fi
    
    # 确保临时目录安全权限
    chmod 700 "$temp_dir"
    echo "$temp_dir"
}

########## 安全文件移动（处理跨文件系统）##########
safe_finalize() {
    local temp_file="$1"
    local target_file="$2"
    
    # 检查目标是否已存在
    if [[ -e "$target_file" ]]; then
        local backup="${target_file}.backup.$(date +%s)"
        warn "目标文件已存在，创建备份：$(basename "$backup")"
        mv "$target_file" "$backup" 2>/dev/null || {
            err "无法创建备份，目标文件可能被占用"
            return 1
        }
    fi
    
    # 尝试原子移动
    if mv "$temp_file" "$target_file" 2>/dev/null; then
        return 0
    fi
    
    # 跨文件系统或权限问题，使用拷贝+删除
    info "跨文件系统拷贝中..."
    if cp "$temp_file" "$target_file" && rm -f "$temp_file"; then
        chmod 644 "$target_file"
        return 0
    else
        err "文件写入失败"
        return 1
    fi
}

########## 解密核心 ##########
decrypt_core(){
    local input_file="$1"
    local output_action="$2"
    local debug_mode="${3:-false}"
    
    local pass_file pass ret=0 gpg_stderr
    local input_size
    
    init_gpg_env
    input_size=$(stat -c%s "$input_file" 2>/dev/null || echo 0)
    
    if [[ "$debug_mode" == "true" ]]; then
        info "调试模式已启用"
        read -rp "是否显示密码输入？(yes/no): " show_pass
        if [[ "$show_pass" == "yes" ]]; then
            read -rp "请输入密码：" pass
            info "密码长度：${#pass} 字符"
        else
            pass=$(read_password_secure "请输入密码：")
        fi
    else
        pass=$(read_password_secure "🔑 请输入私钥密码：")
    fi
    
    pass_file=$(create_secure_passfile "$pass")
    cleanup_register "secure_shred '$pass_file'"
    
    gpg_stderr=$(mktemp)
    cleanup_register "rm -f '$gpg_stderr'"
    
    log "🔓 正在解密..."
    
    local decrypt_cmd="gpg --batch --yes --no-tty --pinentry-mode loopback"
    decrypt_cmd+=" --passphrase-file '$pass_file'"
    decrypt_cmd+=" --allow-multiple-messages --ignore-mdc-error"
    
    if [[ "$input_size" -gt 10485760 ]] && command -v pv &>/dev/null; then
        if ! pv -s "$input_size" "$input_file" | eval "$decrypt_cmd -d" 2>"$gpg_stderr" | eval "$output_action"; then
            ret=1
        fi
    else
        if ! eval "$decrypt_cmd -d '$input_file'" 2>"$gpg_stderr" | eval "$output_action"; then
            ret=1
        fi
    fi
    
    if [[ $ret -ne 0 ]] && [[ -s "$gpg_stderr" ]]; then
        local err_msg
        err_msg=$(cat "$gpg_stderr")
        err "解密失败"
        
        if echo "$err_msg" | grep -qi "Bad passphrase"; then
            err "❌ 密码错误"
        elif echo "$err_msg" | grep -qi "No secret key"; then
            err "❌ 未找到对应的私钥"
        elif echo "$err_msg" | grep -qi "CRC error"; then
            err "❌ 文件损坏或传输错误"
        elif echo "$err_msg" | grep -qi "unknown compress algorithm"; then
            err "❌ 使用了不支持的压缩算法"
        elif echo "$err_msg" | grep -qi "resource limit"; then
            err "❌ 资源限制"
        elif echo "$err_msg" | grep -qi "Permission denied"; then
            err "❌ 权限被拒绝（检查文件系统挂载选项）"
        else
            err "GPG 错误详情：$err_msg"
        fi
    fi
    
    pass=""
    cleanup_execute
    return $ret
}

########## 解密单文件（权限安全版）##########
decrypt_single(){
    local file="$1"
    local out_dir temp_dir output_file final_output
    local basename_full is_tar
    
    basename_full=$(basename "$file")
    out_dir=$(dirname "$file")
    
    # 使用智能临时目录选择
    temp_dir=$(select_temp_dir "$out_dir")
    cleanup_register "rm -rf '$temp_dir'"
    
    output_file="$temp_dir/output.data"
    
    [[ "$basename_full" == *.tar.gpg ]] && is_tar=true || is_tar=false
    
    log "🔓 开始解密：$basename_full"
    info "临时工作目录：$temp_dir"
    
    if ! decrypt_core "$file" "cat > '$output_file'" "${2:-false}"; then
        return 1
    fi
    
    # 处理输出
    if [[ "$is_tar" == true ]]; then
        local tar_dir="$temp_dir/extract"
        mkdir -p "$tar_dir"
        
        if tar -xf "$output_file" -C "$tar_dir" 2>/dev/null; then
            local extracted
            extracted=$(find "$tar_dir" -mindepth 1 -maxdepth 1)
            
            if [[ -n "$extracted" ]]; then
                local item_name
                item_name=$(basename "$extracted")
                
                # 构建最终路径
                local final_path="$out_dir/$item_name"
                if [[ -e "$final_path" ]]; then
                    final_path="${out_dir}/${item_name}.decrypted.$(date +%s)"
                    warn "目标 '$item_name' 已存在，重命名为 '$(basename "$final_path")'"
                fi
                
                # 使用安全finalize（处理跨文件系统）
                if safe_finalize "$extracted" "$final_path"; then
                    log "✅ 目录已解密：$final_path"
                else
                    err "❌ 无法写入目标位置"
                    return 1
                fi
            else
                warn "⚠️ 压缩包为空"
            fi
        else
            err "❌ 解压失败，文件可能损坏"
            return 1
        fi
    else
        # 普通文件
        local out_name="${basename_full%.gpg}"
        [[ -z "$out_name" ]] && out_name="decrypted_output"
        
        local final_path="$out_dir/$out_name"
        if [[ -e "$final_path" ]]; then
            final_path="${out_dir}/${out_name}.decrypted.$(date +%s)"
            warn "文件 '$out_name' 已存在，保存为 '$(basename "$final_path")'"
        fi
        
        if safe_finalize "$output_file" "$final_path"; then
            log "✅ 文件已解密：$final_path"
        else
            err "❌ 无法写入目标位置"
            return 1
        fi
    fi
    
    # 清理临时目录
    rm -rf "$temp_dir" 2>/dev/null || true
    cleanup_stack=("${cleanup_stack[@]//rm -rf \'$temp_dir\'}")
    
    return 0
}

########## 批量解密 ##########
decrypt_batch(){
    local dir file_ext
    local -a files=()
    
    read -rp "请输入要解密的目录（默认当前目录）：" dir
    [[ -z "$dir" ]] && dir="."
    [[ -d "$dir" ]] || { err "目录不存在：$dir"; return 1; }
    
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$dir" -maxdepth 1 -name "*.gpg" -type f -print0 2>/dev/null)
    
    ((${#files[@]} == 0)) && { warn "未找到 .gpg 文件"; return 1; }
    
    info "找到 ${#files[@]} 个加密文件："
    printf '  - %s\n' "${files[@]}"
    
    read -rp "确认批量解密？(yes/no)：" confirm
    [[ "$confirm" != "yes" ]] && { warn "已取消"; return 1; }
    
    local success=0 failed=0
    for file in "${files[@]}"; do
        echo ""
        if decrypt_single "$f"; then
            ((success++))
        else
            ((failed++))
            warn "跳过：$file"
        fi
    done
    
    echo ""
    log "批量解密完成：成功 $success 个，失败 $failed 个"
}

########## 环境诊断 ##########
diagnose_env(){
    echo -e "\n${BLUE}======== GPG 环境诊断 ========${NC}"
    echo "GPG 版本：$(gpg --version | head -1)"
    echo "GPG_TTY：${GPG_TTY:-未设置}"
    echo "内存文件系统：$([[ -d /dev/shm ]] && echo '可用 (/dev/shm)' || echo '不可用')"
    echo ""
    
    echo "临时目录测试："
    local test_dirs=("/tmp" "$HOME" "/var/tmp")
    for d in "${test_dirs[@]}"; do
        if [[ -d "$d" ]] && [[ -w "$d" ]]; then
            local testfile
            testfile=$(mktemp -p "$d" ".test.XXXXXX" 2>/dev/null && echo "OK" || echo "FAIL")
            echo "  $d: $testfile"
            rm -f "$d"/.test.* 2>/dev/null || true
        else
            echo "  $d: 不可写或不存在"
        fi
    done
    echo ""
    
    echo "密钥列表："
    gpg --list-secret-keys
    echo ""
    
    echo "测试解密环境："
    local test_pass="test_$(date +%s)"
    local test_file
    test_file=$(mktemp)
    echo "test data" | gpg --pinentry-mode loopback --symmetric --passphrase "$test_pass" -o "$test_file" 2>/dev/null && \
    gpg --pinentry-mode loopback --batch --passphrase "$test_pass" -d "$test_file" >/dev/null 2>&1 && \
        log "✅ 加解密测试通过" || err "❌ 测试失败"
    rm -f "$test_file"
    echo ""
    read -rp "按回车键继续..."
}

########## 菜单 ##########
init_gpg_env

while true; do
    echo -e "\n${BLUE}======== PGP 中文管家 v6.2（权限安全修复版）========${NC}"
    echo "1) 创建新密钥"
    echo "2) 导入密钥"
    echo "3) 导出公钥"
    echo "4) 导出私钥"
    echo "5) 删除密钥"
    echo "6) 加密"
    echo "7) 解密单个文件（权限安全版）"
    echo "8) 批量解密"
    echo "9) 查看已有密钥"
    echo "10) 环境诊断"
    echo "0) 退出"
    read -rp "请选择操作（0-10）： " c

    case $c in
        1) create_key ;;
        2) import_key ;;
        3) export_pub_key ;;
        4) export_sec_key ;;
        5) delete_key ;;
        6) encrypt ;;
        7) f=$(read_path "请输入要解密的文件：") || continue
           decrypt_single "$f" ;;
        8) decrypt_batch ;;
        9) list_keys ;;
        10) diagnose_env ;;
        0) log "bye~"; exit 0 ;;
        *) err "请输入有效数字 0-10" ;;
    esac
done
