#!/bin/bash
set -eo pipefail

# ----------------------------
# 全局配置
# ----------------------------
LOG_FILE="/var/log/system_maintenance.log"
SSH_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJmS95vKboqxjPxyz+fOhn2tNsrUkgWY1VSYvF8aUyA"
SWAP_SIZE="2048M"
DOCKER_NETWORK="mintcat"
DOCKER_SUBNET="172.20.0.0/16"

# ----------------------------
# 日志管理系统（带轮转）
# ----------------------------
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # 日志轮转（保留7天）
    find /var/log -name "system_maintenance.*.log" -mtime +7 -delete 2>/dev/null
    
    # 写入日志文件
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
    
    # 限制日志文件大小（最大10MB）
    if [ $(stat -c%s "${LOG_FILE}" 2>/dev/null) -gt 10485760 ]; then
        rotate_log="${LOG_FILE}.$(date +%Y%m%d%H%M%S)"
        mv "${LOG_FILE}" "${rotate_log}"
        log "INFO" "日志文件已轮转: ${rotate_log}"
    fi
}

# ----------------------------
# 安全命令执行
# ----------------------------
safe_exec() {
    local cmd="$@"
    log "DEBUG" "执行命令: ${cmd}"

    if ! output=$(sudo bash -c "${cmd}" 2>&1); then
        log "ERROR" "命令执行失败: ${cmd}"
        log "ERROR" "错误输出: ${output}"
        return 1
    fi

    log "DEBUG" "命令输出: ${output}"
    return 0
}

# ----------------------------
# 系统信息检测
# ----------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        echo "${ID}"
    else
        log "ERROR" "无法检测操作系统"
        return 1
    fi
}

# ----------------------------
# SSH安全配置
# ----------------------------
configure_ssh() {
    local sshd_config="/etc/ssh/sshd_config"

    log "INFO" "开始配置SSH安全设置"

    # 备份原配置
    safe_exec "cp ${sshd_config} ${sshd_config}.bak" || return 1

    # 修改配置参数
    declare -A ssh_params=(
        ["PubkeyAuthentication"]="yes"
        ["PasswordAuthentication"]="no"
        ["PermitRootLogin"]="prohibit-password"
        ["ClientAliveInterval"]="300"
    )

    for key in "${!ssh_params[@]}"; do
        safe_exec "sed -i '/^#\?${key}[[:space:]]/c\\${key} ${ssh_params[$key]}' ${sshd_config}"
    done

    # 添加SSH公钥
    local ssh_dir="/root/.ssh"
    safe_exec "mkdir -p ${ssh_dir} && chmod 700 ${ssh_dir}"
    echo "${SSH_PUBKEY}" | safe_exec "tee -a ${ssh_dir}/authorized_keys && chmod 600 ${ssh_dir}/authorized_keys"

    # 测试配置有效性
    if ! safe_exec "sshd -t"; then
        log "ERROR" "SSH配置测试失败，恢复备份文件"
        safe_exec "mv ${sshd_config}.bak ${sshd_config}"
        return 1
    fi

    safe_exec "systemctl restart sshd"
    log "INFO" "SSH安全配置完成"
}

# ----------------------------
# 系统优化配置
# ----------------------------
optimize_system() {
    local os_type=$(detect_os)

    # 公共优化
    safe_exec "timedatectl set-timezone Asia/Shanghai"
    safe_exec "sysctl -w net.ipv4.tcp_syncookies=1"
    safe_exec "sysctl -w net.ipv4.tcp_max_syn_backlog=8192"

    case "${os_type}" in
        ubuntu|debian)
            safe_exec "apt-get update && apt-get install -y curl jq vim neofetch"
            safe_exec "sysctl -p /etc/sysctl.conf"
            ;;
        centos|rhel)
            safe_exec "yum install -y epel-release"
            safe_exec "yum install -y curl jq vim neofetch"
            ;;
        *)
            log "ERROR" "不支持的操作系统: ${os_type}"
            return 1
            ;;
    esac
}

# ----------------------------
# 网络性能优化（BBR）
# ----------------------------
enable_bbr() {
    local sysctl_conf="/etc/sysctl.conf"

    log "INFO" "启用BBR网络加速"

    # 内核参数配置
    declare -A bbr_params=(
        ["net.core.default_qdisc"]="fq"
        ["net.ipv4.tcp_congestion_control"]="bbr"
    )

    for key in "${!bbr_params[@]}"; do
        if ! grep -q "^${key}" "${sysctl_conf}"; then
            echo "${key} = ${bbr_params[$key]}" | safe_exec "tee -a ${sysctl_conf}"
        fi
    done

    safe_exec "sysctl -p"
    log "INFO" "当前拥塞控制算法: $(sysctl net.ipv4.tcp_congestion_control)"
}

# ----------------------------
# 智能SWAP管理
# ----------------------------
manage_swap() {
    local swap_file="/swapfile"

    # 检查现有SWAP
    if swapon --show | grep -q "${swap_file}"; then
        log "INFO" "检测到现有SWAP文件，跳过创建"
        return 0
    fi

    log "INFO" "创建SWAP文件: ${SWAP_SIZE}"
    safe_exec "fallocate -l ${SWAP_SIZE} ${swap_file}"
    safe_exec "chmod 600 ${swap_file}"
    safe_exec "mkswap ${swap_file}"
    safe_exec "swapon ${swap_file}"
    safe_exec "echo '${swap_file} swap swap defaults 0 0' >> /etc/fstab"

    # 调整Swappiness
    safe_exec "sysctl vm.swappiness=10"
    safe_exec "echo 'vm.swappiness=10' >> /etc/sysctl.conf"

    log "INFO" "SWAP状态: $(swapon --show)"
}

# ---------------------------- 
# Docker环境部署
# ----------------------------
setup_docker() {
    log "INFO" "开始部署Docker环境"

    # 安全安装Docker
    if ! command -v docker &>/dev/null; then
        log "INFO" "安装Docker..."
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh --channel stable || {
            log "ERROR" "Docker安装失败"
            return 1
        }
        safe_exec "systemctl enable --now docker"
    else
        log "INFO" "Docker已安装，跳过安装步骤"
    fi

    # 安装Docker Compose
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
    if ! command -v docker-compose &>/dev/null; then
        log "INFO" "安装Docker Compose..."
        safe_exec "curl -L https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m) -o /usr/local/bin/docker-compose"
        safe_exec "chmod +x /usr/local/bin/docker-compose"
    else
        log "INFO" "Docker Compose已安装，跳过安装步骤"
    fi

    # 创建专用网络
    if ! docker network inspect "${DOCKER_NETWORK}" &>/dev/null; then
        safe_exec "docker network create --driver bridge --subnet ${DOCKER_SUBNET} ${DOCKER_NETWORK}"
    fi

    log "INFO" "Docker版本: $(docker --version)"
    log "INFO" "Docker Compose版本: $(docker-compose --version)"
}

# ----------------------------
# 镜像源优化
# ----------------------------
optimize_mirror() {
    local os_type=$(detect_os)

    log "INFO" "开始优化软件源"

    case "${os_type}" in
        ubuntu|debian)
            safe_exec "apt-get install -y netselect-apt"
            local mirror=$(netselect-apt -s -t 20 -o /dev/stdout | grep 'Best mirror' | awk '{print $3}')
            [ -z "${mirror}" ] && return 1

            safe_exec "sed -i 's|http://.*\.archive\.ubuntu\.com|${mirror}|g' /etc/apt/sources.list"
            safe_exec "apt-get update"
        ;;
        centos|rhel)
            safe_exec "yum install -y yum-utils"
            safe_exec "yum-config-manager --enable fastestmirror"
            safe_exec "yum clean all"
        ;;
        *)
            log "ERROR" "不支持的操作系统: ${os_type}"
            return 1
    esac

    log "INFO" "软件源优化完成"
}

# ----------------------------
# 交互式菜单系统
# ----------------------------
show_menu() {
    while :; do
        clear
        echo "====================================="
        echo "      系统维护管理平台 v2.0       "
        echo "====================================="
        echo "1) 全自动系统初始化"
        echo "2) 安全加固配置"
        echo "3) 网络性能优化"
        echo "4) 容器环境部署"
        echo "5) 软件源加速"
        echo "6) 退出"
        echo "====================================="
        
        read -p "请输入操作编号 (1-6): " choice
        case "${choice}" in
            1)
                log "INFO" "开始执行全自动系统初始化"
                optimize_system
                manage_swap
                enable_bbr
                configure_ssh
                setup_docker
                ;;
            2)
                log "INFO" "开始安全加固配置"
                configure_ssh
                optimize_system
                ;;
            3)
                log "INFO" "开始网络性能优化"
                enable_bbr
                ;;
            4)
                log "INFO" "开始容器环境部署"
                setup_docker
                ;;
            5)
                log "INFO" "开始软件源加速"
                optimize_mirror
                ;;
            6)
                log "INFO" "退出系统维护管理"
                exit 0
                ;;
            *)
                log "WARN" "无效的输入选例"
                ;;
        esac
        
        read -p "操作执行完成，按任意键返回菜单..."
    done
}

# ----------------------------
# 主程序入口
# ----------------------------
main() {
    # 权限验证
    [ "$(id -u)" -ne 0 ] && log "ERROR" "必须使用root权限运行" && exit 1
    
    # 日志目录创建
    mkdir -p "$(dirname "${LOG_FILE}")"
    
    show_menu
}

# 启动主程序
main
