#!/bin/bash
# autoserver 主入口

# 加载公共函数
source "$(dirname "$0")/utils/common.sh"

# 显示主菜单
function main_menu() {
    clear
    echo "========== AutoServer 自动化部署 =========="
    echo "1. 一键部署环境"
    echo "2. 容器管理（部署/备份/恢复/删除）"
    echo "3. Crontab 任务管理"
    echo "4. WireGuard 管理"  # 新增 WireGuard 管理选项
    echo "0. 退出"
    echo "============================================"
    read -p "请选择操作: " choice
    case "$choice" in
        1) source "$(dirname "$0")/modules/setup_env.sh" ;;
        2) source "$(dirname "$0")/modules/container_manage.sh" ;;
        3) source "$(dirname "$0")/modules/crontab_manage.sh" ;;
        4) source "$(dirname "$0")/modules/wireguard_manage.sh" ;;  # 调用 WireGuard 管理模块
        0) exit 0 ;;
        *) echo "无效选择，请重新输入！" && sleep 1 ;;
    esac
}

while true; do
    main_menu
    echo "按任意键返回主菜单..."
    read -n 1
done
