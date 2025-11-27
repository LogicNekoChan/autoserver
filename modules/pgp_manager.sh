#!/usr/bin/env bash
# ==========================================
# Ubuntu PGP 中文管家 v4.0（完整功能版 - 支持分卷/压缩/目录/空格）
# ==========================================
# 严格模式：遇到错误即退出，防止脚本继续运行
set -euo pipefail

########## 依赖检查 ##########
# 重新引入 split 依赖
for cmd in gpg tar pv split realpath; do
  command -v "$cmd" >/dev/null || { echo "❌ 请先安装：sudo apt install gnupg tar pv coreutils"; exit 1; }
done

########## 彩色输出 ##########
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; BLUE='\033[36m'; NC='\033[0m'
log()  { echo -e "${GREEN}[提示]${NC} $*"; }
warn() { echo -e "${YELLOW}[警告]${NC} $*"; }
err()  { echo -e "${RED}[错误]${NC} $*" >&2; }

########## 路径读取 ##########
# 注意：realpath "$_p" 的输出已正确处理了路径中的空格，使用时必须双引号引用
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
    # read_path 返回的路径带有空格，必须引用
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
    # 引用 $out 以处理空格
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
    # 引用 $out 以处理空格
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


########## 6. 加密（分卷/压缩） ##########
encrypt(){
    local target recipient idx basename out_dir split_mb temp_file merged_file target_to_encrypt final_extension
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

    read -rp "是否分卷？输入 MB 大小（留空则不分卷）： " split_mb
    
    temp_file="$(mktemp -u)"
    merged_file="$(mktemp -u --suffix=.gpg)" # 临时存储完整的加密文件

    # 1. 打包目录或文件 (使用 Gzip 压缩)
    if [[ -d "$target" ]]; then
        log "📦 正在打包目录 (启用 Gzip 压缩)..."
        temp_file="${temp_file}.tar.gz"
        final_extension=".tar.gz.gpg"
        tar -czf "$temp_file" -C "$(dirname "$target")" "$(basename "$target")"
        target_to_encrypt="$temp_file"
    else
        # 复制文件到临时位置以标准化流程，处理单个文件
        log "🔄 复制文件到临时位置..."
        cp -a "$target" "$temp_file"
        final_extension=".gpg"
        target_to_encrypt="$temp_file"
    fi

    # 2. 一次性公钥加密
    log "🔐 正在加密..."
    # 使用 pv 显示进度，并确保所有文件路径都被引用
    pv "$target_to_encrypt" | gpg --no-sign -e -r "$recipient" -o "$merged_file"

    rm -f "$temp_file"

    # 3. 分卷 或 输出单个文件
    if [[ -n "$split_mb" ]]; then
        log "✂️ 正在分卷..."
        # 分卷后的文件名以 .part.aa 结尾
        split -b "${split_mb}M" "$merged_file" "${out_dir}/${basename}${final_extension}.part"
        rm -f "$merged_file"
        log "✅ 分卷加密完成，存放在：$(realpath "$out_dir")，文件名为 ${basename}${final_extension}.part[aa, ab...]"
        log "📢 提醒：分卷解密请使用选项 7，然后选择第一个分卷文件 (*.partaa)。"
    else
        # 不分卷，重命名为最终文件名
        local final_path="${out_dir}/${basename}${final_extension}"
        mv "$merged_file" "$final_path"
        log "✅ 加密完成，文件存放在：$(realpath "$final_path")"
        [[ -d "$target" ]] && log "📢 提醒：您加密的是目录，接收方在 Windows 上解密后会得到一个 **.tar.gz** 文件，需要手动解压一次。"
    fi
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
    # 确保 $input_file 被引用
    echo "$pass" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 -d "$input_file" | eval "$output_action"

    [[ $? -ne 0 ]] && { err "解密失败，密码错误或文件已损坏。"; return 1; }
}

########## 解密非分卷文件 ##########
decrypt_single(){
    local file="$1" out
    local basename_no_gpg
    # 移除 .gpg 扩展名
    basename_no_gpg=$(basename "$file" .gpg)
    
    log "📦 正在解密..."

    # 判断解密输出是否为 .tar.gz 包
    if [[ "$basename_no_gpg" =~ \.tar\.gz$ ]]; then
        # 解密并解包目录
        log "💡 检测到 .tar.gz 格式 (压缩目录)，正在解包到 $(dirname "$file")..."
        # 调用核心解密函数，并确保 tar 解包目录 $dir 被引用
        decrypt_core "$file" 'pv | tar xzf - -C "$(dirname "$file")"' || return 1
        log "✅ 文件已解密并解包"
    else
        # 解密单个文件
        # 输出文件名：去除 .gpg 后的部分 + .decrypted
        out="$(dirname "$file")/${basename_no_gpg}.decrypted"
        # 调用核心解密函数，并确保输出文件 $out 被引用
        decrypt_core "$file" 'pv > "$out"' || return 1
        log "✅ 文件已解密：$(realpath "$out")"
    fi
}


########## 解密分卷文件 ##########
decrypt_split(){
    local first="$1"
    local dir base merged_file base_no_part
    
    dir=$(dirname "$first")
    
    # 提取基础文件名，去除 .part.aa, .part.ab 等后缀
    base_no_part=$(basename "$first" | sed 's/\.part.*$//')
    merged_file="$(mktemp -u --suffix=.gpg)"

    # 启用 nullglob 防止在没有匹配文件时，模式字符串本身被当作文件
    shopt -s nullglob
    # 搜索所有分卷文件，注意引用以处理空格
    parts=( "$dir/$base_no_part".part* )
    shopt -u nullglob # 关闭 nullglob

    [[ ${#parts[@]} -eq 0 ]] && { err "未找到分卷：$dir/$base_no_part.part*"; return 1; }

    log "🔐 正在合并分卷..."
    : > "$merged_file"
    # 循环合并分卷，引用 $f 以处理文件名空格
    for f in "${parts[@]}"; do
        cat "$f" >> "$merged_file"
    done
    
    # 核心解密操作委托给 decrypt_single (它会处理解包 tar.gz 的逻辑)
    decrypt_single "$merged_file" || return 1
    
    rm -f "$merged_file"
    log "✅ 分卷合并和解密完成"
}


########## 7. 解密 - 自动判断 ##########
decrypt_auto(){
    local file="$1"
    if [[ "$file" =~ \.part[a-z][a-z]$ ]]; then
        log "检测到分卷文件（*.partaa），将开始合并解密..."
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
    echo -e "\n${BLUE}======== PGP 中文管家 v4.0 完整功能版 ========${NC}"
    echo "1) 创建新密钥"
    echo "2) 导入密钥"
    echo "3) 导出公钥"
    echo "4) 导出私钥"
    echo "5) 删除密钥"
    echo "6) 加密（文件/目录，支持分卷和压缩）"
    echo "7) 解密（自动识别分卷，一次授权）"
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
            # f 必须被引用，否则 read_path 得到的路径空格会分裂
            f=$(read_path "请输入要解密的 .gpg 文件（或第一个分卷文件 *.partaa）：") || continue
            decrypt_auto "$f" 
            ;;
        8) list_keys ;;
        9) log "bye~"; exit 0 ;;
        *) err "请输入有效数字 1-9" ;;
    esac
done
