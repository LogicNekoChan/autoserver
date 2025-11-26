#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ----------------------------
# 全局配置
# ----------------------------
readonly LOG_FILE="/var/log/system_maintenance.log"
readonly SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJmS95vKboqxjPxyz+fOhn2tNsrUkgWY1VSYvF8aUyA"
readonly SWAP_SIZE="2048M"

# ----------------------------
# 日志管理系统（安全 + 稳定）
# ----------------------------
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    mkdir -p "$(dirname "$LOG_FILE")"

    # 日志轮转
    find "$(dirname "$LOG_FILE")" -maxdepth 1 -name "system_maintenance.*.log" -mtime +7 -delete || true

    printf "[%s] [%s] %s\n" "$timestamp" "$level" "$message" | tee -a "$LOG_FILE"

    # 日志大小限制（10MB）
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE") -gt 10485760 ]]; then
        local rotate_log="${LOG_FILE}.$(date +%Y%m%d%H%M%S)"
        mv "$LOG_FILE" "$rotate_log"
        printf "[%s] [INFO] 日志文件已轮转到 %s\n" "$timestamp" "$rotate_log" | tee -a "$LOG_FILE"
    fi
}

# ----------------------------
# 安全命令执行
# ----------------------------
safe_exec() {
    local cmd="$*"
    log "DEBUG" "执行命令：${cmd}"

    if ! output=$(bash -c "$cmd" 2>&1); then
        log "ERROR" "命令执行失败: ${cmd}"
        log "ERROR" "错误输出: ${output}"
        return 1
    fi

    log "DEBUG" "命令输出: ${output}"
}

# ----------------------------
# 检测系统发行版
# ----------------------------
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    else
        log "ERROR" "无法识别系统发行版"
        exit 1
    fi
}

# ----------------------------
# SSH 安全加固
# ----------------------------
configure_ssh() {
    log "INFO" "开始配置 SSH 安全设置"
    local ssh_cfg="/etc/ssh/sshd_config"

    safe_exec "cp ${ssh_cfg} ${ssh_cfg}.bak.$(date +%s)"

    declare -A config=(
        ["PubkeyAuthentication"]="yes"
        ["PasswordAuthentication"]="no"
        ["PermitRootLogin"]="prohibit-password"
        ["ClientAliveInterval"]="300"
    )

    for key in "${!config[@]}"; do
        safe_exec "sed -Ei 's/^#?${key}.*/${key} ${config[$key]}/' ${ssh_cfg}"
        grep -q "^${key}" "$ssh_cfg" || echo "${key} ${config[$key]}" >> "$ssh_cfg"
    done

    safe_exec "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
    echo "$SSH_PUBKEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    safe_exec "sshd -t"
    safe_exec "systemctl restart sshd"

    log "INFO" "SSH 安全配置完成"
}

# ----------------------------
# 系统优化
# ----------------------------
optimize_system() {
    local os=$(detect_os)

    safe_exec "timedatectl set-timezone Asia/Shanghai"
    safe_exec "sysctl -w net.ipv4.tcp_syncookies=1"
    safe_exec "sysctl -w net.ipv4.tcp_max_syn_backlog=8192"

    case "$os" in
        ubuntu|debian)
            safe_exec "apt-get update -y"
            safe_exec "apt-get install -y curl jq vim neofetch pv"
            safe_exec "sysctl -p"
        ;;
        centos|rhel)
            safe_exec "yum install -y epel-release"
            safe_exec "yum install -y curl jq vim neofetch"
        ;;
        *)
            log "ERROR" "不支持的操作系统: $os"
            return 1
        ;;
    esac
}

# ----------------------------
# 启用 BBR
# ----------------------------
enable_bbr() {
    log "INFO" "启用 BBR"

    local sysctl_conf="/etc/sysctl.conf"
    declare -A bbr=(
        ["net.core.default_qdisc"]="fq"
        ["net.ipv4.tcp_congestion_control"]="bbr"
    )

    for key in "${!bbr[@]}"; do
        grep -q "^${key}" "$sysctl_conf" || echo "${key} = ${bbr[$key]}" >> "$sysctl_conf"
    done

    safe_exec "sysctl -p"
    log "INFO" "当前 TCP 拥塞算法：$(sysctl -n net.ipv4.tcp_congestion_control)"
}

# ----------------------------
# SWAP 管理
# ----------------------------
manage_swap() {
    local swapfile="/swapfile"

    if swapon --show | grep -q "$swapfile"; then
        log "INFO" "SWAP 已存在，跳过"
        return 0
    fi

    log "INFO" "创建 SWAP: $SWAP_SIZE"

    safe_exec "fallocate -l $SWAP_SIZE $swapfile"
    safe_exec "chmod 600 $swapfile"
    safe_exec "mkswap $swapfile"
    safe_exec "swapon $swapfile"

    echo "$swapfile swap swap defaults 0 0" | tee -a /etc/fstab
    echo "vm.swappiness=10" | tee -a /etc/sysctl.conf
    safe_exec "sysctl -w vm.swappiness=10"
}

# ----------------------------
# Docker 环境部署
# ----------------------------
setup_docker() {
    log "INFO" "部署 Docker 环境"

    if ! command -v docker >/dev/null 2>&1; then
        curl -fsSL https://get.docker.com -o /tmp/install_docker.sh
        sh /tmp/install_docker.sh
    fi

    safe_exec "systemctl enable --now docker"

    # 安装 compose v2
    if ! docker compose version &>/dev/null; then
        safe_exec "mkdir -p /usr/libexec/docker/cli-plugins/"
        local arch
        arch=$(uname -m)
        safe_exec "curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch} -o /usr/libexec/docker/cli-plugins/docker-compose"
        safe_exec "chmod +x /usr/libexec/docker/cli-plugins/docker-compose"
    fi

    log "INFO" "Docker: $(docker --version)"
    log "INFO" "Compose: $(docker compose version)"
}

# ----------------------------
# 软件源优化
# ----------------------------
optimize_mirror() {
    local os=$(detect_os)

    case "$os" in
        ubuntu|debian)
            safe_exec "apt-get install -y netselect-apt"
            local mirror
            mirror=$(netselect-apt -s -t 20 -o /dev/stdout | awk '/Best/ {print $3}')
            [[ -n "$mirror" ]] && sed -i "s|http://[^ ]*archive.ubuntu.com|$mirror|g" /etc/apt/sources.list
            safe_exec "apt-get update"
        ;;
        centos|rhel)
            safe_exec "yum install -y yum-utils"
            safe_exec "yum-config-manager --enable fastestmirror"
            safe_exec "yum clean all"
        ;;
        *)
            log "ERROR" "不支持的系统: $os"
        ;;
    esac
}

# ----------------------------
# 主菜单
# ----------------------------
show_menu() {
    while true; do
        clear
        cat <<EOF
=====================================
      系统维护管理平台 v3.0
=====================================
1) 全自动系统初始化
2) 安全加固配置
3) 网络性能优化（BBR）
4) Docker 环境部署
5) 软件源优化
6) 退出
=====================================
EOF
        read -rp "请输入操作编号 (1-6): " choice

        case "$choice" in
            1) optimize_system; manage_swap; enable_bbr; configure_ssh; setup_docker ;;
            2) configure_ssh; optimize_system ;;
            3) enable_bbr ;;
            4) setup_docker ;;
            5) optimize_mirror ;;
            6) exit 0 ;;
            *) log "WARN" "无效输入" ;;
        esac

        read -rp "执行完毕，按任意键返回菜单..."
    done
}

# ----------------------------
# 主入口
# ----------------------------
main() {
    [[ $(id -u) -eq 0 ]] || { echo "必须使用 root 运行"; exit 1; }

    show_menu
}

main
