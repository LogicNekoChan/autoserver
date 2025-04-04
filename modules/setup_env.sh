#!/bin/bash
# modules/setup_env.sh
# 系统维护管理模块：提供自动化系统初始化、最快软件源更换等功能

# 全局日志文件路径
LOG_FILE="/var/log/system_maintenance.log"

# ----------------------------
# 日志记录函数
# ----------------------------
log_message() {
    local message="$1"
    echo "$(date "+%Y-%m-%d %H:%M:%S") - $message" >> "$LOG_FILE"
}

# ----------------------------
# 执行带 sudo 权限的命令
# ----------------------------
execute_sudo() {
    local command="$1"
    echo "执行命令: $command"
    if ! sudo bash -c "$command"; then
        echo "[ERROR] 命令执行失败: $command"
        log_message "[ERROR] 命令执行失败: $command"
        return 1
    else
        log_message "成功执行命令: $command"
    fi
}

# ----------------------------
# 修改 SSH 端口（改为 8848），并启用密钥登录
# ----------------------------
change_ssh_port() {
    local new_port=8848
    echo "正在修改 SSH 端口为 ${new_port} 并启用密钥登录..."

    # 备份原始 SSH 配置
    execute_sudo "cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak"

    # 修改 SSH 端口
    execute_sudo "sed -i 's/^#\?Port .*/Port ${new_port}/' /etc/ssh/sshd_config"

    # 启用密钥登录，同时不关闭密码登录
    execute_sudo "sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config"
    execute_sudo "sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config"

    # 在配置文件中添加授权的公钥
    echo "将 SSH 公钥添加到 authorized_keys..."
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCzx8GlO5jVkNiwBG57J2zVwllC1WHQbRaFVI8H5u+fZnt3YuuIsCJBCRfM7/7Ups6wdEVwhgk+PEq8nE3WgZ8SBgNoAO+CgZprdDi+nx7zBRqrHw9oJcHQysiAw+arRW29g2TZgVhszjVq5G6MoVYGjnnPzLEcZS37by0l9eZD9u1hAB4FtIdw+VfrfJG177HLfiLkSm6PkO3QMWTYGmGjE3zpMxWeascWCn6UTDpjt6UiSMgcmAlx4FP8mkRRMc5TvxqnUKbgdjYBU2V+dZQx1keovrd0Yh8KitPEGd6euok3e7WmtLQlXH8WOiPlCr2YJfW3vQjlDVg5UU83GSGr root@mintcat" | execute_sudo "tee -a /root/.ssh/authorized_keys"

    # 配置防火墙
    if command -v ufw >/dev/null 2>&1; then
        echo "检测到 UFW，正在添加防火墙规则..."
        execute_sudo "ufw allow ${new_port}/tcp"
    else
        echo "未检测到 UFW，使用 iptables 允许端口 ${new_port}..."
        execute_sudo "iptables -A INPUT -p tcp --dport ${new_port} -j ACCEPT"
        execute_sudo "iptables-save > /etc/iptables.rules"
    fi

    # 重启 SSH 服务
    execute_sudo "systemctl restart ssh"

    echo "SSH 端口已修改为 ${new_port}，并启用了密钥登录和密码登录并存。请使用 'ssh -p ${new_port} 用户名@服务器IP' 进行连接。"
}

# ----------------------------
# 自动化系统初始化
# ----------------------------
quick_setup() {
    echo "正在检测系统信息..."
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        os_type="$ID"
    else
        echo "[ERROR] 无法检测系统信息，脚本支持 Ubuntu 和 Debian 系统。"
        log_message "[ERROR] 无法检测系统信息，脚本支持 Ubuntu 和 Debian 系统。"
        return 1
    fi

    echo "当前系统: $NAME $VERSION"
    echo "开始执行基础环境部署..."

    # 1. 更新系统并安装基本依赖
    echo "步骤 1：更新系统并安装基本依赖..."
    case "$os_type" in
        ubuntu|debian)
            execute_sudo "apt update"
            execute_sudo "apt install -y neofetch vim jq curl"
            ;;
        *)
            echo "[ERROR] 当前系统不支持自动化部署。"
            log_message "[ERROR] 当前系统不支持自动化部署：$NAME"
            return 1
            ;;
    esac
    echo "系统更新和依赖安装完成。"

    # 2. 设置时区
    echo "步骤 2：设置系统时间为上海时区..."
    execute_sudo "timedatectl set-timezone Asia/Shanghai"
    echo "当前系统时间: $(date)"

    # 3. 启用 BBR
    echo "步骤 3：启用 BBR 模式..."
    enable_bbr

    # 4. 设置 Swap
    echo "步骤 4：设置 Swap 空间..."
    setup_swap

    # 5. 配置 SSH 密钥登录
    echo "步骤 5：配置 SSH 密钥登录..."
    setup_ssh_key_auth

    # 5.1 修改 SSH 端口为 8848
    echo "步骤 5.1：修改 SSH 端口..."
    change_ssh_port

    # 6. 安装 Docker
    echo "步骤 6：安装 Docker..."
    install_docker

    # 7. 创建 mintcat 虚拟网络
    echo "步骤 7：创建 mintcat 虚拟网络..."
    create_mintcat_network

    echo "基础环境部署已完成！"
}

# ----------------------------
# 其他系统优化函数（BBR、Swap、Docker）
# ----------------------------
enable_bbr() {
    execute_sudo "modprobe tcp_bbr"
    execute_sudo "echo 'tcp_bbr' > /etc/modules-load.d/bbr.conf"
    execute_sudo "sysctl -p"
}

setup_swap() {
    execute_sudo "dd if=/dev/zero of=/swapfile bs=1M count=2048"
    execute_sudo "chmod 600 /swapfile"
    execute_sudo "mkswap /swapfile"
    execute_sudo "swapon /swapfile"
    execute_sudo "echo '/swapfile swap swap defaults 0 0' >> /etc/fstab"
}

install_docker() {
    execute_sudo "curl -fsSL https://get.docker.com | bash"
    execute_sudo "systemctl start docker"
    execute_sudo "systemctl enable docker"
    execute_sudo "curl -L 'https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)' -o /usr/local/bin/docker-compose"
    execute_sudo "chmod +x /usr/local/bin/docker-compose"
}

create_mintcat_network() {
    execute_sudo "docker network rm mintcat 2>/dev/null"
    execute_sudo "docker network create --driver bridge --subnet 172.20.0.0/16 mintcat"
}

# ----------------------------
# 系统维护管理菜单
# ----------------------------
system_maintenance_menu() {
    while true; do
        clear
        echo "==============================="
        echo "      系统维护管理菜单       "
        echo "==============================="
        echo "1. 自动化系统初始化"
        echo "2. 更换最快的软件源"
        echo "3. 退出"
        echo "==============================="
        read -p "请选择一个选项 (1-3): " choice
        case "$choice" in
            1)
                quick_setup
                read -p "操作完成，请按回车键返回菜单..."
                ;;
            2)
                change_to_fastest_mirror
                read -p "操作完成，请按回车键返回菜单..."
                ;;
            3)
                echo "退出系统维护管理。"
                exit 0
                ;;
            *)
                echo "[ERROR] 无效选项，请重试。"
                sleep 2
                ;;
        esac
    done
}

# ----------------------------
# 脚本入口
# ----------------------------
main() {
    system_maintenance_menu
}

main
