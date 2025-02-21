#!/bin/bash
# 一键部署环境模块

source "$(dirname "$0")/../utils/common.sh"

OS_TYPE=$(detect_os)
echo_info "检测到操作系统类型：$OS_TYPE"

install_packages_debian() {
    apt-get update
    apt-get install -y jq vim neofetch sudo curl tar
}

install_packages_centos() {
    yum install -y epel-release
    yum install -y jq vim neofetch sudo curl tar
}

install_docker() {
    # 这里采用官方安装脚本
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm -f get-docker.sh
}

install_docker_compose() {
    # 下载 docker-compose 二进制文件
    curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

enable_bbr_fq() {
    # 修改内核参数开启 BBR 和 fq
    echo_info "配置内核参数开启 BBR 和 fq..."
    grep -q "net.core.default_qdisc" /etc/sysctl.conf || echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    grep -q "net.ipv4.tcp_congestion_control" /etc/sysctl.conf || echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p
}

echo_info "开始安装必要的软件包..."
if [ "$OS_TYPE" = "debian" ]; then
    install_packages_debian
elif [ "$OS_TYPE" = "centos" ]; then
    install_packages_centos
else
    echo_error "无法识别的系统类型！"
    exit 1
fi

echo_info "安装 Docker..."
install_docker

echo_info "安装 Docker Compose..."
install_docker_compose

enable_bbr_fq

echo_info "环境部署完成！"
