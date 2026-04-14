#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ----------------------------
# 全局配置
# ----------------------------
readonly LOG_FILE="/var/log/system_maintenance.log"
readonly SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJmS95vKboqxjPxyz+fOhn2tNsrUkgWY1VSYvF8aUyA"

# ----------------------------
# 日志系统
# ----------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    mkdir -p "$(dirname "$LOG_FILE")"
    find "$(dirname "$LOG_FILE")" -maxdepth 1 -name "system_maintenance.*.log" -mtime +7 -delete 2>/dev/null || true

    printf "[%s] [%s] %s\n" "$timestamp" "$level" "$message" | tee -a "$LOG_FILE"

    if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        local rotate_log="${LOG_FILE}.$(date +%Y%m%d%H%M%S)"
        mv "$LOG_FILE" "$rotate_log"
        printf "[%s] [INFO] 日志已轮转至 %s\n" "$(date "+%Y-%m-%d %H:%M:%S")" "$rotate_log" | tee -a "$LOG_FILE"
    fi
}

# ----------------------------
# 安全执行
# ----------------------------
safe_exec() {
    local cmd="$*"
    log "DEBUG" "执行：${cmd}"
    local output
    if output=$(eval "${cmd}" 2>&1); then
        return 0
    else
        log "ERROR" "失败：${output}"
        return 1
    fi
}

# ----------------------------
# 仅允许 Debian
# ----------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${ID}" != "debian" ]]; then
            log "ERROR" "仅支持 Debian 系统"
            exit 1
        fi
    else
        log "ERROR" "无法识别系统"
        exit 1
    fi
}

# ----------------------------
# 自动计算 SWAP 大小（最合理规则）
# ----------------------------
get_swap_size() {
    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_kb / 1024 / 1024))

    if [[ $mem_gb -lt 2 ]]; then
        echo "2G"
    elif [[ $mem_gb -lt 8 ]]; then
        echo "4G"
    elif [[ $mem_gb -lt 16 ]]; then
        echo "8G"
    elif [[ $mem_gb -lt 32 ]]; then
        echo "16G"
    else
        echo "16G"
    fi
}

# ----------------------------
# SSH 加固
# ----------------------------
configure_ssh() {
    log "INFO" 开始 SSH 安全加固
    local ssh_cfg="/etc/ssh/sshd_config"
    safe_exec "cp -n ${ssh_cfg} ${ssh_cfg}.bak.$(date +%s)"

    declare -A ssh_config=(
        ["PubkeyAuthentication"]="yes"
        ["PasswordAuthentication"]="no"
        ["PermitRootLogin"]="prohibit-password"
        ["ClientAliveInterval"]="300"
        ["ClientAliveCountMax"]="2"
        ["MaxAuthTries"]="3"
    )

    for key in "${!ssh_config[@]}"; do
        sed -Ei "s/^#?${key}.*/${key} ${ssh_config[$key]}/" "$ssh_cfg"
        grep -q "^${key}" "$ssh_cfg" || echo "${key} ${ssh_config[$key]}" >> "$ssh_cfg"
    done

    safe_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
    echo "$SSH_PUBKEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys

    safe_exec "sshd -t"
    safe_exec "systemctl restart ssh"
    log "INFO" SSH 配置完成
}

# ----------------------------
# 系统优化
# ----------------------------
optimize_system() {
    log "INFO" 开始系统基础优化
    detect_os

    safe_exec "timedatectl set-timezone Asia/Shanghai"

    cat > /etc/sysctl.d/99-sysctl.conf <<EOF
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=4096
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_tw_reuse=1
EOF

    safe_exec "sysctl -p /etc/sysctl.d/99-sysctl.conf"

    log "INFO" 安装基础工具
    safe_exec "apt update -y"
    safe_exec "apt install -y curl vim jq git wget htop iftop iotop"

    log "INFO" 系统优化完成
}

# ----------------------------
# BBR
# ----------------------------
enable_bbr() {
    log "INFO" 启用 BBR
    cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    safe_exec "sysctl -p /etc/sysctl.d/99-bbr.conf"
    local bbr
    bbr=$(sysctl -n net.ipv4.tcp_congestion_control)
    log "INFO" 当前拥塞算法：$bbr
}

# ----------------------------
# 自动 SWAP
# ----------------------------
manage_swap() {
    local swapfile="/swapfile"
    local swap_size
    swap_size=$(get_swap_size)

    if swapon --noheadings | grep -q "$swapfile"; then
        log "INFO" SWAP 已存在，跳过
        return 0
    fi

    log "INFO" 检测内存大小，自动设置 SWAP：$swap_size

    safe_exec "fallocate -l ${swap_size} ${swapfile} 2>/dev/null || dd if=/dev/zero of=${swapfile} bs=1M count=${swap_size%G}"
    safe_exec "chmod 600 ${swapfile}"
    safe_exec "mkswap ${swapfile}"
    safe_exec "swapon ${swapfile}"

    echo "$swapfile swap swap defaults 0 0" | tee -a /etc/fstab

    cat > /etc/sysctl.d/99-swap.conf <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
    safe_exec "sysctl -p /etc/sysctl.d/99-swap.conf"

    log "INFO" SWAP 配置完成
}

# ----------------------------
# Docker
# ----------------------------
setup_docker() {
    log "INFO" 部署 Docker
    detect_os

    safe_exec "apt remove -y docker docker-engine docker.io containerd runc || true"
    safe_exec "apt install -y ca-certificates curl gnupg lsb-release"

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null

    safe_exec "apt update -y"
    safe_exec "apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    safe_exec "systemctl enable --now docker"

    log "INFO" Docker：$(docker --version)
    log "INFO" Compose：$(docker compose version)
}

# ----------------------------
# 换源
# ----------------------------
optimize_mirror() {
    log "INFO" 优化 Debian 软件源
    detect_os
    local codename
    codename=$(lsb_release -cs)

    safe_exec "cp -n /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s)"

    cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian/ ${codename} main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ ${codename} main contrib non-free non-free-firmware

deb http://deb.debian.org/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ ${codename}-updates main contrib non-free non-free-firmware

deb http://deb.debian.org/debian-security/ ${codename}-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security/ ${codename}-security main contrib non-free non-free-firmware
EOF

    safe_exec "apt clean all"
    safe_exec "apt update -y"
    log "INFO" 软件源优化完成
}

# ----------------------------
# 菜单
# ----------------------------
show_menu() {
    while true; do
        clear
        cat <<EOF
================================================
           Debian 系统维护工具箱
================================================
1) 全自动一键初始化（推荐）
2) SSH 安全加固
3) 系统基础优化
4) 启用 BBR 网络加速
5) 自动配置 SWAP（按内存大小）
6) 部署 Docker 环境
7) 优化软件源
8) 退出
================================================
EOF
        read -rp "请选择 [1-8]: " choice

        case "$choice" in
            1)
                optimize_mirror
                optimize_system
                manage_swap
                enable_bbr
                configure_ssh
                setup_docker
                log "INFO" 全自动初始化完成！
                ;;
            2) configure_ssh ;;
            3) optimize_system ;;
            4) enable_bbr ;;
            5) manage_swap ;;
            6) setup_docker ;;
            7) optimize_mirror ;;
            8) exit 0 ;;
            *) log "WARN" 无效输入 ;;
        esac

        echo -e "\n按回车继续..."
        read
    done
}

# ----------------------------
# 入口
# ----------------------------
main() {
    if [[ $(id -u) -ne 0 ]]; then
        echo "请使用 root 运行"
        exit 1
    fi
    show_menu
}

main
