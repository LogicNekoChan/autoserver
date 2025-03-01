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
# 使用 bash -c 以便支持复杂和多行命令
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
# 自动化系统初始化（快速部署基础环境）
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
            echo "[ERROR] 当前系统不支持自动化部署，请手动安装依赖。"
            log_message "[ERROR] 当前系统不支持自动化部署：$NAME"
            return 1
            ;;
    esac
    echo "系统更新和依赖安装完成。"

    # 2. 设置系统时间为上海时区
    echo "步骤 2：设置系统时间为上海时区..."
    execute_sudo "timedatectl set-timezone Asia/Shanghai"
    echo "当前系统时间: $(date)"

    # 3. 启用 BBR 加速
    echo "步骤 3：启用 BBR 模式..."
    enable_bbr

    # 4. 设置 Swap 空间
    echo "步骤 4：设置 Swap 空间..."
    setup_swap

    # 5. 配置 SSH 密钥登录，禁用密码登录
    echo "步骤 5：配置 SSH 密钥登录，并禁用密码登录..."
    setup_ssh_key_auth

    # 6. 安装 Docker 与 Docker Compose
    echo "步骤 6：安装 Docker 和 Docker Compose..."
    install_docker

    # 7. 创建 mintcat 虚拟网络
    echo "步骤 7：创建 mintcat 虚拟网络..."
    create_mintcat_network

    echo "基础环境部署已完成！"
}

# ----------------------------
# 创建 mintcat 虚拟网络
# ----------------------------
create_mintcat_network() {
    echo "删除现有 mintcat 虚拟网络（如果存在）..."
    execute_sudo "docker network rm mintcat 2>/dev/null"

    echo "创建新的 mintcat 虚拟网络..."
    execute_sudo "docker network create --driver bridge --scope local --attachable --subnet 172.20.0.0/16 --gateway 172.20.0.1 --ip-range 172.20.0.0/25 mintcat"
    echo "mintcat 虚拟网络已成功创建。"
}

# ----------------------------
# 自动检测并切换到最快的软件源
# ----------------------------
change_to_fastest_mirror() {
    echo "正在检测并切换到最快的软件源..."

    echo "备份现有的软件源文件..."
    execute_sudo "cp /etc/apt/sources.list /etc/apt/sources.list.bak"

    echo "安装 netselect-apt 工具..."
    execute_sudo "apt-get update"
    execute_sudo "apt-get install -y netselect-apt"

    echo "执行 netselect-apt 检测最快镜像..."
    execute_sudo "netselect-apt"

    echo "更新 apt 缓存..."
    execute_sudo "apt update -y"
    echo "最快的软件源已设置并更新完毕。"
}

# ----------------------------
# 启用 BBR 模式
# ----------------------------
enable_bbr() {
    execute_sudo "modprobe tcp_bbr"
    execute_sudo "echo 'tcp_bbr' > /etc/modules-load.d/bbr.conf"
    execute_sudo "echo 'net.core.default_qdisc = fq' >> /etc/sysctl.conf"
    execute_sudo "echo 'net.ipv4.tcp_congestion_control = bbr' >> /etc/sysctl.conf"
    execute_sudo "sysctl -p"

    if lsmod | grep -q bbr; then
        echo "BBR 模式已成功启用。"
    else
        echo "[ERROR] BBR 模式启用失败，请手动检查配置。"
        log_message "[ERROR] BBR 模式启用失败"
    fi
}

# ----------------------------
# 设置 Swap 空间
# ----------------------------
setup_swap() {
    local total_disk_size
    total_disk_size=$(df --output=size / | tail -1 | tr -d ' ')
    local swap_size=2048

    # 如果根分区空间较小，则设置较小的 Swap
    if [ "$total_disk_size" -lt 10240 ]; then
        swap_size=500
    fi

    echo "创建 Swap 文件，大小：${swap_size} MB"
    execute_sudo "swapoff -a"
    execute_sudo "dd if=/dev/zero of=/swapfile bs=1M count=${swap_size} status=progress"
    execute_sudo "chmod 600 /swapfile"
    execute_sudo "mkswap /swapfile"
    execute_sudo "swapon /swapfile"
    execute_sudo "echo '/swapfile swap swap defaults 0 0' >> /etc/fstab"

    echo "Swap 设置完成，当前 Swap 空间: $(free -m | awk '/Swap/ {print \$2}') MB"
}

# ----------------------------
# 设置 SSH 密钥登录并禁用密码登录
# ----------------------------
setup_ssh_key_auth() {
    local ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCzx8GlO5jVkNiwBG57J2zVwllC1WHQbRaFVI8H5u+fZnt3YuuIsCJBCRfM7/7Ups6wdEVwhgk+PEq8nE3WgZ8SBgNoAO+CgZprdDi+nx7zBRqrHw9oJcHQysiAw+arRW29g2TZgVhszjVq5G6MoVYGjnnPzLEcZS37by0l9eZD9u1hAB4FtIdw+VfrfJG177HLfiLkSm6PkO3QMWTYGmGjE3zpMxWeascWCn6UTDpjt6UiSMgcmAlx4FP8mkRRMc5TvxqnUKbgdjYBU2V+dZQx1keovrd0Yh8KitPEGd6euok3e7WmtLQlXH8WOiPlCr2YJfW3vQjlDVg5UU83GSGr root@mintcat"

    echo "配置 SSH 密钥登录..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "$ssh_key" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys

    echo "修改 SSH 配置，禁用密码登录..."
    execute_sudo "sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"

    # 检查并确保允许 root 登录
    if grep -q '^PermitRootLogin no' /etc/ssh/sshd_config || ! grep -q '^PermitRootLogin' /etc/ssh/sshd_config; then
        echo "启用 root 登录..."
        execute_sudo "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config"
    else
        echo "root 登录已启用，无需修改。"
    fi

    execute_sudo "systemctl restart sshd"
    echo "SSH 配置完成，SSH 密钥登录已配置，密码登录已禁用。"
}

# ----------------------------
# 安装 Docker 和 Docker Compose
# ----------------------------
install_docker() {
    echo "开始安装 Docker..."
    if ! curl -fsSL https://get.docker.com | bash -s docker; then
        echo "[ERROR] Docker 安装失败，请检查网络连接或手动安装 Docker。"
        log_message "[ERROR] Docker 安装失败"
        return 1
    fi

    execute_sudo "systemctl start docker"
    execute_sudo "systemctl enable docker"

    echo "开始安装 Docker Compose..."
    local compose_version
    compose_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
    if [ -z "$compose_version" ]; then
        echo "[ERROR] 获取 Docker Compose 版本失败！"
        log_message "[ERROR] 获取 Docker Compose 版本失败！"
        return 1
    fi

    execute_sudo "curl -L 'https://github.com/docker/compose/releases/download/${compose_version}/docker-compose-$(uname -s)-$(uname -m)' -o /usr/local/bin/docker-compose"
    execute_sudo "chmod +x /usr/local/bin/docker-compose"

    echo "Docker 和 Docker Compose 安装完成。"
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
                log_message "[ERROR] 用户输入无效选项: $choice"
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
