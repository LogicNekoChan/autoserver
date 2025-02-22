#!/bin/bash
# modules/setup_env.sh
# 系统维护管理模块：提供自动化系统初始化、最快软件源更换等功能

# 快速部署菜单模块
system_maintenance_menu() {
    while true; do
        clear
        echo "==============================="
        echo "      系统维护管理菜单       "
        echo "==============================="
        echo "1. 自动化系统初始化"
        echo "2. 更换最快的软件源"
        echo "3. 返回主菜单"
        echo "==============================="
        read -p "请选择一个选项 (1-3): " deploy_choice

        case $deploy_choice in
            1)
                quick_setup
                pause
                ;;
            2)
                change_to_fastest_mirror
                pause
                ;;
            3)
                return
                ;;
            *)
                echo "无效选项，请重试。"
                sleep 2
                ;;
        esac
    done
}

# 快速部署基础环境
quick_setup() {
    echo "正在检测系统信息..."
    local os_type=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os_type=$ID
    else
        echo "无法检测系统信息，脚本支持 Ubuntu 和 Debian 系统。"
        return
    fi

    echo "当前系统: $NAME $VERSION"
    echo "开始执行基础环境部署..."

    echo "1. 更新系统并安装基本依赖..."
    case $os_type in
        ubuntu | debian)
            sudo apt update -y && sudo apt install -y neofetch vim jq curl && sudo apt upgrade -y
            ;;
        *)
            echo "当前系统不支持自动化部署，请手动安装依赖。"
            return
            ;;
    esac
    echo "系统更新和依赖安装完成。"

    echo "2. 设置系统时间为上海时间..."
    sudo timedatectl set-timezone Asia/Shanghai
    echo "当前系统时间: $(date)"

    echo "3. 启用 BBR 模式..."
    enable_bbr

    echo "4. 设置 Swap 空间..."
    setup_swap

    echo "5. 设置 SSH 密钥登录并禁用密码登录..."
    setup_ssh_key_auth

    echo "6. 安装 Docker 和 Docker Compose..."
    install_docker

    echo "7. 创建 mintcat 虚拟网络..."
    create_mintcat_network

    echo "基础环境部署已完成！"
}

# 创建 mintcat 虚拟网络
create_mintcat_network() {
    # 删除现有的 mintcat 虚拟网络
    echo "删除现有 mintcat 虚拟网络配置..."
    docker network rm mintcat 2>/dev/null

    # 创建新的 mintcat 虚拟网络
    echo "创建新的 mintcat 虚拟网络..."
    docker network create \
        --driver bridge \
        --scope local \
        --attachable \
        --subnet 172.20.0.0/16 \
        --gateway 172.20.0.1 \
        --ip-range 172.20.0.0/25 \
        mintcat
    echo "mintcat 虚拟网络已成功创建。"
}

# 自动检测最快的软件源并更换
change_to_fastest_mirror() {
    echo "正在检测并切换到最快的软件源..."

    # 备份现有的软件源文件
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

    # 安装并使用 netselect-apt 获取最快镜像
    sudo apt-get install -y netselect-apt
    sudo netselect-apt

    # 更新 apt 缓存
    sudo apt update -y
    echo "最快的软件源已设置并更新完毕。"
}

# 启用 BBR 模式
enable_bbr() {
    sudo modprobe tcp_bbr
    echo "tcp_bbr" | sudo tee -a /etc/modules-load.d/bbr.conf >/dev/null
    echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf >/dev/null
    echo "net.ipv4.tcp_congestion_control = bbr" | sudo tee -a /etc/sysctl.conf >/dev/null
    sudo sysctl -p >/dev/null

    if lsmod | grep -q bbr; then
        echo "BBR 模式已成功启用。"
    else
        echo "BBR 模式启用失败，请手动检查配置。"
    fi
}

# 设置 Swap 空间
setup_swap() {
    local total_disk_size=$(df --output=size / | tail -1)
    local swap_size=2048

    if [ "$total_disk_size" -lt 10240 ]; then
        swap_size=500
    fi

    sudo swapoff -a
    sudo dd if=/dev/zero of=/swapfile bs=1M count=$swap_size
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab >/dev/null

    echo "Swap 设置完成，当前 Swap 空间: $(free -m | awk '/Swap/ {print $2}') MB"
}

# 设置 SSH 密钥登录并禁用密码登录
setup_ssh_key_auth() {
    local ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCzx8GlO5jVkNiwBG57J2zVwllC1WHQbRaFVI8H5u+fZnt3YuuIsCJBCRfM7/7Ups6wdEVwhgk+PEq8nE3WgZ8SBgNoAO+CgZprdDi+nx7zBRqrHw9oJcHQysiAw+arRW29g2TZgVhszjVq5G6MoVYGjnnPzLEcZS37by0l9eZD9u1hAB4FtIdw+VfrfJG177HLfiLkSm6PkO3QMWTYGmGjE3zpMxWeascWCn6UTDpjt6UiSMgcmAlx4FP8mkRRMc5TvxqnUKbgdjYBU2V+dZQx1keovrd0Yh8KitPEGd6euok3e7WmtLQlXH8WOiPlCr2YJfW3vQjlDVg5UU83GSGr root@mintcat"

    echo "正在设置 SSH 密钥登录..."
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "$ssh_key" > ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys

    echo "正在修改 SSH 配置..."
    # 禁用密码登录
    sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

    # 检查并开启 root 登录
    if grep -q '^PermitRootLogin no' /etc/ssh/sshd_config || ! grep -q '^PermitRootLogin' /etc/ssh/sshd_config; then
        echo "当前不允许 root 登录，正在启用..."
        sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        echo "已允许 root 登录，无需修改。"
    fi

    # 重启 SSH 服务
    sudo systemctl restart sshd
    echo "SSH 密钥登录已配置，密码登录已禁用，root 登录已启用。"
}

# 安装 Docker 和 Docker Compose
install_docker() {
    curl -fsSL https://get.docker.com | bash -s docker
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo curl -L "https://github.com/docker/compose/releases/download/$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo "Docker 和 Docker Compose 安装完成。"
}

# 暂停等待用户按键
pause() {
    read -p "按 Enter 键继续..."
}

# 脚本入口：调用系统维护菜单
system_maintenance_menu
