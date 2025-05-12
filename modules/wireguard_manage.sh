#!/bin/bash
# WireGuard 管理模块

# 加载公共函数
source "$(dirname "$0")/autoserver/utils/common.sh"

# 显示 WireGuard 管理菜单
function wireguard_menu() {
    clear
    echo "========== WireGuard 管理 =========="
    echo "1. 安装 WireGuard"
    echo "2. 启动 WireGuard 服务"
    echo "3. 停止 WireGuard 服务"
    echo "4. 查看 WireGuard 配置"
    echo "5. 设置开机启动"
    echo "6. 取消开机启动"
    echo "0. 返回主菜单"
    echo "===================================="
    read -p "请选择操作: " choice
    case "$choice" in
        1) install_wireguard ;;
        2) start_wireguard ;;
        3) stop_wireguard ;;
        4) view_config ;;
        5) set_autostart ;;
        6) unset_autostart ;;
        0) return ;;
        *) echo "无效选择，请重新输入！" && sleep 1 ;;
    esac
}

# 安装 WireGuard
function install_wireguard() {
    echo "正在安装 WireGuard..."
    if ! sudo apt install -y wireguard > /dev/null; then
        echo "WireGuard 安装失败！"
        return 1
    fi
    echo "WireGuard 安装成功！"
}

# 启动 WireGuard 服务
function start_wireguard() {
    local config=$(list_configs)
    if [ -z "$config" ]; then
        echo "未选择配置文件或操作取消！"
        return 1
    fi
    echo "正在启动 WireGuard 服务..."
    if ! sudo wg setconf $(basename "$config" .conf) "$config" > /dev/null; then
        echo "WireGuard 服务启动失败！"
        return 1
    fi
    echo "WireGuard 服务启动成功！"
}

# 停止 WireGuard 服务
function stop_wireguard() {
    local config=$(list_configs)
    if [ -z "$config" ]; then
        echo "未选择配置文件或操作取消！"
        return 1
    fi
    echo "正在停止 WireGuard 服务..."
    if ! sudo wg down $(basename "$config" .conf) > /dev/null; then
        echo "停止 WireGuard 服务失败！"
        return 1
    fi
    echo "WireGuard 服务已停止！"
}

# 查看 WireGuard 配置
function view_config() {
    local config=$(list_configs)
    if [ -z "$config" ]; then
        echo "未选择配置文件或操作取消！"
        return 1
    fi
    if ! sudo cat "$config"; then
        echo "无法访问配置文件！请检查权限。"
        return 1
    fi
}

# 列出所有可用的 WireGuard 配置文件
function list_configs() {
    local configs=($(sudo find /etc/wireguard -type f -name "*.conf" 2>/dev/null)
                || echo "没有找到任何 WireGuard 配置文件！"))
    if [ ${#configs[@]} -eq 0 ]; then
        echo "没有找到任何 WireGuard 配置文件！"
        return 1
    fi

    echo "可用的 WireGuard 配置文件："
    for i in "${!configs[@]}"; do
        echo "$((i + 1)). ${configs[$i]}"
    done
    echo "0. 返回"
    read -p "请选择配置文件编号: " choice
    if [ "$choice" -eq 0 ]; then
        return 0
    elif [ "$choice" -ge 1 ] && [ "$choice" -le ${#configs[@]} ]; then
        selected_config=${configs[$((choice - 1))]}
        echo "已选择配置文件: $selected_config"
        echo "$selected_config"
        return 0
    else
        echo "无效选择！"
        return 1
    fi
}

# 设置开机启动
function set_autostart() {
    local config=$(list_configs)
    if [ -z "$config" ]; then
        echo "未选择配置文件或操作取消！"
        return 1
    fi

    local service_name="wg-quick@$(basename "$config" .conf)"
    if ! sudo systemctl is-enabled "$service_name" &>/dev/null; then
        echo "WireGuard 配置 $config 已经设置开机启动！"
    else
        # 添加到 systemd 服务并启用
        if ! sudo systemctl enable "$service_name" > /dev/null; then
            echo "设置开机启动失败！"
            return 1
        fi
        echo "WireGuard 开机启动已设置！"
    fi
}

# 取消开机启动
function unset_autostart() {
    local config=$(list_configs)
    if [ -z "$config" ]; then
        echo "未选择配置文件或操作取消！"
        return 1
    fi

    local service_name="wg-quick@$(basename "$config" .conf)"
    if ! sudo systemctl is-enabled "$service_name" &>/dev/null; then
        echo "WireGuard 配置 $config 没有设置开机启动！"
    else
        # 禁用 systemd 服务
        if ! sudo systemctl disable "$service_name" > /dev/null; then
            echo "取消开机启动失败！"
            return 1
        fi
        echo "WireGuard 开机启动已取消！"
    fi
}

# 主循环
while true; do
    wireguard_menu
    echo -e "\n按任意键返回 WireGuard 管理菜单..."
    read -n 1 input
    if [ "$input" != "" ]; then
        break
    fi
done
