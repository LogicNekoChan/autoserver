#!/bin/bash
# WireGuard 管理模块

# 加载公共函数
source "$(dirname "$0")/../utils/common.sh"

# 显示 WireGuard 管理菜单
function wireguard_menu() {
    clear
    echo "========== WireGuard 管理 =========="
    echo "1. 安装 WireGuard"
    echo "2. 启动 WireGuard 服务"
    echo "3. 停止 WireGuard 服务"
    echo "4. 查看 WireGuard 配置"
    echo "0. 返回主菜单"
    echo "===================================="
    read -p "请选择操作: " choice
    case "$choice" in
        1) install_wireguard ;;
        2) start_wireguard ;;
        3) stop_wireguard ;;
        4) view_config ;;
        0) return ;;
        *) echo "无效选择，请重新输入！" && sleep 1 ;;
    esac
}

# 安装 WireGuard
function install_wireguard() {
    echo "正在安装 WireGuard..."
    sudo apt update && sudo apt install -y wireguard
    if [ $? -eq 0 ]; then
        echo "WireGuard 安装成功！"
    else
        echo "WireGuard 安装失败！"
    fi
}

# 启动 WireGuard 服务
function start_wireguard() {
    echo "正在启动 WireGuard 服务..."
    sudo wg setconf wg0 /etc/wireguard/wg0.conf
    if [ $? -eq 0 ]; then
        echo "WireGuard 服务启动成功！"
    else
        echo "WireGuard 服务启动失败！"
    fi
}

# 停止 WireGuard 服务
function stop_wireguard() {
    echo "正在停止 WireGuard 服务..."
    sudo wg down wg0
    if [ $? -eq 0 ]; then
        echo "WireGuard 服务已停止！"
    else
        echo "停止 WireGuard 服务失败！"
    fi
}

# 查看 WireGuard 配置
function view_config() {
    echo "WireGuard 配置如下："
    cat /etc/wireguard/wg0.conf
}

# 主循环
while true; do
    wireguard_menu
    echo "按任意键返回 WireGuard 管理菜单..."
    read -n 1
done
