#!/usr/bin/env bash
# ==========================================
# Ubuntu 交互式 PGP 密钥/文件管理器
# 优化增强版：加密 + 解密 + 签名 + 验签 + 批量处理
# 中文交互 | 强容错 | 高安全 | 全兼容
# ==========================================

# 安全模式配置（不使用严格模式，避免非预期中断）
set -o pipefail
shopt -s nullglob
shopt -s extglob

# ==================== 全局配置 ====================
# 依赖命令
REQUIRED_COMMANDS=("gpg" "tar" "realpath")
# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[36m'
PURPLE='\033[35m'
NC='\033[0m'

# ==================== 工具函数 ====================
# 日志输出函数
log()  { echo -e "${GREEN}[✅ 提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[⚠️ 警告]${NC} $*"; }
err()  { echo -e "${RED}[❌ 错误]${NC} $*" >&2; }
info() { echo -e "${BLUE}[ℹ️ 信息]${NC} $*"; }
title(){ echo -e "\n${PURPLE}===== $* =====${NC}"; }

# 依赖检查
check_dependencies() {
    local missing=()
    for cmd in "${REQUIRED_COMMANDS[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        err "缺少依赖：${missing[*]}"
        info "请执行安装：sudo apt update && sudo apt install -y gnupg tar coreutils"
        exit 1
    fi
}

# 安全读取路径（自动处理引号、空格、绝对路径、存在性检查）
safe_read_path() {
    local prompt="$1"
    local path

    read -rp "$prompt" path
    # 去除首尾引号
    path="${path#\"}"
    path="${path%\"}"
    path="${path#\'}"
    path="${path%\'}"

    if [ ! -e "$path" ]; then
        err "路径不存在：$path"
        return 1
    fi

    realpath -s "$path"
    return 0
}

# 安全读取目录
safe_read_dir() {
    local prompt="$1"
    local dir

    read -rp "$prompt" dir
    dir="${dir#\"}"
    dir="${dir%\"}"
    dir="${dir#\'}"
    dir="${dir%\'}"

    if [ ! -d "$dir" ]; then
        err "不是有效目录：$dir"
        return 1
    fi

    realpath -s "$dir"
    return 0
}

# 文件覆盖确认
confirm_overwrite() {
    local file="$1"
    if [ -f "$file" ] || [ -d "$file" ]; then
        read -rp "⚠️ 目标已存在：$file，是否覆盖？(y/N) " choice
        case "$choice" in
            [Yy]*) return 0 ;;
            *) return 1 ;;
        esac
    fi
    return 0
}

# ==================== 密钥管理函数 ====================
# 创建PGP密钥
create_pgp_key() {
    title "创建PGP密钥对"
    info "将启动GPG官方密钥生成向导，按提示操作即可"
    gpg --full-generate-key
    log "密钥创建流程完成"
}

# 导入密钥
import_pgp_key() {
    title "导入PGP密钥"
    local key_file
    key_file=$(safe_read_path "请输入密钥文件路径（.asc/.gpg）：") || return 1

    gpg --import "$key_file"
    log "密钥导入成功"
}

# 导出公钥
export_public_key() {
    title "导出公钥"
    local email output

    read -rp "请输入密钥邮箱/ID：" email
    [ -z "$email" ] && { err "邮箱/ID不能为空"; return 1; }

    output="${email}_pub.asc"
    read -rp "保存文件名（默认：$output）：" custom_output
    [ -n "$custom_output" ] && output="$custom_output"

    confirm_overwrite "$output" || return 1
    gpg --armor --export "$email" > "$output"
    log "公钥已导出：$(realpath "$output")"
}

# 导出私钥（高风险）
export_secret_key() {
    title "导出私钥（⚠️ 高风险操作）"
    warn "私钥是最高机密，泄露将导致所有加密内容被破解！"
    read -rp "确认要导出私钥？(y/N) " confirm
    [ "$confirm" != "y" ] && { info "已取消操作"; return; }

    local email output
    read -rp "请输入密钥邮箱/ID：" email
    [ -z "$email" ] && { err "邮箱/ID不能为空"; return 1; }

    output="${email}_sec.asc"
    read -rp "保存文件名（默认：$output）：" custom_output
    [ -n "$custom_output" ] && output="$custom_output"

    confirm_overwrite "$output" || return 1
    gpg --armor --export-secret-keys "$email" > "$output"
    warn "私钥已导出！请立即加密保存，切勿泄露：$(realpath "$output")"
}

# 删除密钥
delete_pgp_key() {
    title "删除密钥"
    warn "此操作不可恢复！"
    local email
    read -rp "请输入要删除的邮箱/ID：" email
    [ -z "$email" ] && { err "邮箱/ID不能为空"; return 1; }

    gpg --delete-secret-and-public-keys "$email"
    log "密钥删除操作完成"
}

# 列出所有密钥
list_all_keys() {
    title "PGP密钥列表"
    echo -e "\n${BLUE}【公钥列表】${NC}"
    gpg --list-keys
    echo -e "\n${BLUE}【私钥列表】${NC}"
    gpg --list-secret-keys
}

# ==================== 加解密/签名函数 ====================
# 单个加密（支持文件/目录）
encrypt_single() {
    title "单个文件/目录加密"
    local target recipient

    target=$(safe_read_path "请输入要加密的文件/目录：") || return 1
    read -rp "接收者邮箱：" recipient
    [ -z "$recipient" ] && { err "接收者不能为空"; return 1; }

    local dir=$(dirname "$target")
    local name=$(basename "$target")
    cd "$dir" || return 1

    if [ -d "$name" ]; then
        info "检测到目录，自动打包加密..."
        local output="${name}.tar.gz.gpg"
        confirm_overwrite "$output" || return 1
        tar czf - "$name" | gpg -e -r "$recipient" -o "$output"
        log "目录加密完成：$output"
    else
        local output="${name}.gpg"
        confirm_overwrite "$output" || return 1
        gpg -e -r "$recipient" -o "$output" "$name"
        log "文件加密完成：$output"
    fi
}

# 单个解密
decrypt_single() {
    title "单个文件解密"
    local gpg_file

    gpg_file=$(safe_read_path "请输入 .gpg 加密文件路径：") || return 1
    local dir=$(dirname "$gpg_file")
    local name=$(basename "$gpg_file")
    cd "$dir" || return 1

    if [[ "$name" == *.tar.gz.gpg ]]; then
        info "检测为目录加密包，自动解压还原..."
        gpg -d "$name" | tar xzf -
        log "目录解密解压完成"
    else
        local output="${name%.gpg}"
        confirm_overwrite "$output" || return 1
        gpg -d "$name" > "$output"
        log "文件解密完成：$output"
    fi
}

# 批量加密
batch_encrypt() {
    title "批量文件加密"
    local src_dir recipient out_dir count=0

    src_dir=$(safe_read_dir "请输入待加密文件目录：") || return 1
    read -rp "接收者邮箱：" recipient
    [ -z "$recipient" ] && { err "接收者不能为空"; return 1; }

    read -rp "输出目录（默认 ./encrypted）：" out_dir
    out_dir=${out_dir:-./encrypted}
    mkdir -p "$out_dir"
    out_dir=$(realpath "$out_dir")

    info "开始批量加密：$src_dir -> $out_dir"
    for item in "$src_dir"/*; do
        [ ! -f "$item" ] && continue
        local filename=$(basename "$item")
        [[ "$filename" =~ \.(gpg|sig)$ ]] && continue

        local output="$out_dir/$filename.gpg"
        gpg -e -r "$recipient" -o "$output" "$item"
        ((count++))
        log "已加密：$filename"
    done

    log "批量加密完成！总计 $count 个文件 | 输出目录：$out_dir"
}

# 批量解密
batch_decrypt() {
    title "批量文件解密"
    local src_dir out_dir count=0

    src_dir=$(safe_read_dir "请输入 .gpg 文件目录：") || return 1
    read -rp "输出目录（默认 ./decrypted）：" out_dir
    out_dir=${out_dir:-./decrypted}
    mkdir -p "$out_dir"
    out_dir=$(realpath "$out_dir")

    info "开始批量解密：$src_dir -> $out_dir"
    for gpg_file in "$src_dir"/*.gpg; do
        [ ! -f "$gpg_file" ] && continue
        local filename=$(basename "$gpg_file" .gpg)
        local output="$out_dir/$filename"

        gpg -d "$gpg_file" > "$output"
        ((count++))
        log "已解密：$filename"
    done

    log "批量解密完成！总计 $count 个文件 | 输出目录：$out_dir"
}

# 单独签名文件
sign_file() {
    title "文件签名（生成 .sig）"
    local file signer

    file=$(safe_read_path "请输入要签名的文件：") || return 1
    read -rp "签名者邮箱（你的私钥）：" signer
    [ -z "$signer" ] && { err "签名者不能为空"; return 1; }

    local output="${file}.sig"
    confirm_overwrite "$output" || return 1
    gpg --detach-sign -u "$signer" -o "$output" "$file"
    log "签名完成：$output"
    warn "请将【原文件 + .sig】一起发送给对方验证"
}

# 验证签名
verify_signature() {
    title "验证文件签名"
    local file

    file=$(safe_read_path "请输入原文件（自动匹配 .sig）：") || return 1
    info "正在验证签名..."

    if gpg --verify "${file}.sig" "$file"; then
        log "验证通过 ✅ 文件完整、签名有效"
    else
        err "验证失败 ❌ 文件被篡改或签名无效"
    fi
}

# 签名+加密（最安全）
sign_and_encrypt() {
    title "签名+加密（推荐）"
    local file signer recipient

    file=$(safe_read_path "请输入文件：") || return 1
    read -rp "签名者邮箱（你）：" signer
    read -rp "接收者邮箱（对方）：" recipient
    [ -z "$signer" ] || [ -z "$recipient" ] && { err "信息不能为空"; return 1; }

    local output="${file}.gpg"
    confirm_overwrite "$output" || return 1
    gpg -u "$signer" -e -r "$recipient" -s -o "$output" "$file"
    log "已完成签名+加密：$output"
}

# 解密+验签
decrypt_and_verify() {
    title "解密+验签"
    local file

    file=$(safe_read_path "请输入加密签名文件：") || return 1
    local output="${file%.gpg}"
    confirm_overwrite "$output" || return 1

    info "正在解密并验证签名..."
    if gpg -d -o "$output" "$file"; then
        log "操作成功 ✅ 解密完成 + 签名有效"
    else
        err "操作失败 ❌ 解密或验签未通过"
    fi
}

# ==================== 主菜单 ====================
show_menu() {
    clear
    echo -e "${PURPLE}================================================${NC}"
    echo -e "            PGP 密钥/文件管理工具（增强版）"
    echo -e "${PURPLE}================================================${NC}"
    echo "1) 创建PGP密钥对     2) 导入密钥        3) 导出公钥"
    echo "4) 导出私钥          5) 删除密钥        6) 单个加密"
    echo "7) 单个解密          8) 批量加密        9) 批量解密"
    echo "10) 单独文件签名     11) 验证签名       12) 签名+加密"
    echo "13) 解密+验签        14) 查看所有密钥   15) 退出程序"
    echo -e "${PURPLE}================================================${NC}"
}

main() {
    check_dependencies
    log "PGP管理工具启动成功！"
    sleep 1

    while true; do
        show_menu
        read -rp "请选择操作 [1-15]：" choice

        case $choice in
            1) create_pgp_key ;;
            2) import_pgp_key ;;
            3) export_public_key ;;
            4) export_secret_key ;;
            5) delete_pgp_key ;;
            6) encrypt_single ;;
            7) decrypt_single ;;
            8) batch_encrypt ;;
            9) batch_decrypt ;;
            10) sign_file ;;
            11) verify_signature ;;
            12) sign_and_encrypt ;;
            13) decrypt_and_verify ;;
            14) list_all_keys ;;
            15) log "感谢使用，再见！👋"; exit 0 ;;
            *) err "无效输入，请输入 1-15 的数字" ;;
        esac

        echo -e "\n按回车键继续..."
        read -r
    done
}

# 启动主程序
main
