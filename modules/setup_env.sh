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
# 安全执行封装
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
# 环境检测
# ----------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        if [[ "${ID}" != "debian" ]]; then
            log "ERROR" "当前系统为 ${ID}，本脚本仅支持 Debian"
            exit 1
        fi
    else
        log "ERROR" "无法识别操作系统类型"
        exit 1
    fi
}

is_china_network() {
    if curl -s --connect-timeout 3 https://www.google.com > /dev/null; then
        return 1 # False
    else
        return 0 # True
    fi
}

# ----------------------------
# 优化软件源 (支持大陆加速)
# ----------------------------
optimize_mirror() {
    log "INFO" "开始优化 Debian 软件源"
    detect_os
    local codename
    codename=$(lsb_release -cs)

    safe_exec "cp -n /etc/apt/sources.list /etc/apt/sources.list.bak.$(date +%s)"

    local mirror_url="http://deb.debian.org"
    local security_url="http://deb.debian.org/debian-security"

    if is_china_network; then
        log "INFO" "检测到大陆环境，切换至阿里云镜像站"
        mirror_url="https://mirrors.aliyun.com"
        security_url="https://mirrors.aliyun.com"
    fi

    cat > /etc/apt/sources.list <<EOF
deb ${mirror_url}/debian/ ${codename} main contrib non-free non-free-firmware
deb-src ${mirror_url}/debian/ ${codename} main contrib non-free non-free-firmware

deb ${mirror_url}/debian/ ${codename}-updates main contrib non-free non-free-firmware
deb-src ${mirror_url}/debian/ ${codename}-updates main contrib non-free non-free-firmware

deb ${security_url}/debian-security/ ${codename}-security main contrib non-free non-free-firmware
deb-src ${security_url}/debian-security/ ${codename}-security main contrib non-free non-free-firmware
EOF

    safe_exec "apt-get clean all"
    safe_exec "apt-get update -y"
    log "INFO" "软件源优化完成"
}

# ----------------------------
# 系统基础优化
# ----------------------------
optimize_system() {
    log "INFO" "开始系统基础优化"
    
    # 时区设置
    safe_exec "timedatectl set-timezone Asia/Shanghai"

    # 内核参数调优
    cat > /etc/sysctl.d/99-sysctl.conf <<EOF
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=8192
net.core.somaxconn=4096
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_tw_reuse=1
fs.file-max=65535
EOF
    safe_exec "sysctl -p /etc/sysctl.d/99-sysctl.conf"

    # 基础工具安装
    log "INFO" "安装运维必备工具"
    safe_exec "apt-get update -y"
    safe_exec "apt-get install -y curl vim jq git wget htop iftop iotop lsof net-tools"

    log "INFO" "系统基础优化完成"
}

# ----------------------------
# 开启 BBR
# ----------------------------
enable_bbr() {
    log "INFO" "启用 BBR 网络加速"
    cat > /etc/sysctl.d/99-bbr.conf <<EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    safe_exec "sysctl -p /etc/sysctl.d/99-bbr.conf"
    local bbr_status
    bbr_status=$(sysctl -n net.ipv4.tcp_congestion_control)
    log "INFO" "当前 TCP 拥塞控制算法：$bbr_status"
}

# ----------------------------
# 自动配置 SWAP
# ----------------------------
manage_swap() {
    local swapfile="/swapfile"
    if swapon --noheadings | grep -q "$swapfile"; then
        log "INFO" "SWAP 已配置，跳过"
        return 0
    fi

    local mem_kb
    mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local mem_gb=$((mem_kb / 1024 / 1024))
    local swap_size="2G"

    [[ $mem_gb -ge 2 ]] && swap_size="4G"
    [[ $mem_gb -ge 8 ]] && swap_size="8G"
    [[ $mem_gb -ge 16 ]] && swap_size="16G"

    log "INFO" "物理内存 ${mem_gb}G，正在创建 ${swap_size} SWAP..."

    safe_exec "fallocate -l ${swap_size} ${swapfile} 2>/dev/null || dd if=/dev/zero of=${swapfile} bs=1M count=${swap_size%G}000"
    safe_exec "chmod 600 ${swapfile}"
    safe_exec "mkswap ${swapfile}"
    safe_exec "swapon ${swapfile}"
    echo "${swapfile} swap swap defaults 0 0" >> /etc/fstab

    # Swap 权重优化
    cat > /etc/sysctl.d/99-swap.conf <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
    safe_exec "sysctl -p /etc/sysctl.d/99-swap.conf"
    log "INFO" "SWAP 配置完成"
}

# ----------------------------
# SSH 安全加固
# ----------------------------
configure_ssh() {
    log "INFO" "开始 SSH 安全加固"
    local ssh_cfg="/etc/ssh/sshd_config"
    safe_exec "cp -n ${ssh_cfg} ${ssh_cfg}.bak.$(date +%s)"

    declare -A config=(
        ["PubkeyAuthentication"]="yes"
        ["PasswordAuthentication"]="no"
        ["PermitRootLogin"]="prohibit-password"
        ["MaxAuthTries"]="3"
        ["ClientAliveInterval"]="300"
        ["ClientAliveCountMax"]="2"
    )

    for key in "${!config[@]}"; do
        sed -Ei "s/^#?${key}.*/${key} ${config[$key]}/" "$ssh_cfg"
        grep -q "^${key}" "$ssh_cfg" || echo "${key} ${config[$key]}" >> "$ssh_cfg"
    done

    # 注入公钥
    safe_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
    echo "$SSH_PUBKEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    
    safe_exec "sshd -t" && safe_exec "systemctl restart ssh"
    log "INFO" "SSH 加固完成（已禁用密码登录，仅限公钥）"
}

# ----------------------------
# Docker 部署 (大陆优化版)
# ----------------------------
setup_docker() {
    log "INFO" "部署 Docker 环境"
    detect_os

    # 卸载旧版本
    safe_exec "apt-get remove -y docker docker-engine docker.io containerd runc || true"
    safe_exec "apt-get install -y ca-certificates curl gnupg lsb-release"

    local gpg_url="https://download.docker.com/linux/debian/gpg"
    local repo_url="https://download.docker.com/linux/debian"

    if is_china_network; then
        log "INFO" "检测到大陆网络，使用阿里云 Docker 源"
        gpg_url="https://mirrors.aliyun.com/docker-ce/linux/debian/gpg"
        repo_url="https://mirrors.aliyun.com/docker-ce/linux/debian"
    fi

    # 配置密钥与仓库
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "$gpg_url" | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $repo_url $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list >/dev/null

    safe_exec "apt-get update -y"
    safe_exec "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"

    # 大陆镜像加速器配置
    if is_china_network; then
        log "INFO" "配置 Docker 镜像加速器 (Registry Mirror)"
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com",
    "https://docker.m.daocloud.io"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF
    fi

    safe_exec "systemctl daemon-reload"
    safe_exec "systemctl enable --now docker"
    log "INFO" "Docker 安装完成: $(docker --version)"
}

# ----------------------------
# 菜单
# ----------------------------
show_menu() {
    while true; do
        clear
        cat <<EOF
================================================
           Debian 系统自动化运维工具
================================================
1) 全自动一键初始化 (推荐)
2) 优化软件源 (支持大陆加速)
3) 系统基础优化 (时区/内核/工具)
4) 启用 BBR 网络加速
5) 自动配置 SWAP 虚拟内存
6) SSH 安全加固 (公钥登录)
7) 部署 Docker 环境 (国内加速)
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
                log "INFO" ">>> 全自动初始化流程全部完成！"
                ;;
            2) optimize_mirror ;;
            3) optimize_system ;;
            4) enable_bbr ;;
            5) manage_swap ;;
            6) configure_ssh ;;
            7) setup_docker ;;
            8) exit 0 ;;
            *) log "WARN" "无效选项，请重新选择" ;;
        esac
        echo -e "\n按回车键返回菜单..."
        read
    done
}

# ----------------------------
# 主程序入口
# ----------------------------
main() {
    if [[ $(id -u) -ne 0 ]]; then
        echo "错误：必须使用 root 用户运行此脚本！"
        exit 1
    fi
    show_menu
}

main
