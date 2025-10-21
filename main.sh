#!/bin/bash

# 如果 linuxbash 命令不存在，就自动创建软链接
if ! command -v linuxbash &>/dev/null; then
    echo "首次运行，正在注册 linuxbash 命令..."
    sudo ln -s "$(realpath "$0")" /usr/local/bin/linuxbash
    echo "注册完成！现在你可以在任何地方输入 linuxbash 来运行本脚本。"
    sleep 2
fi

# 你原来的代码从这里开始
source "$(dirname "$0")/utils/common.sh"

function main_menu() {
    clear
    echo "========== AutoServer 自动化部署 =========="
    echo "1. 一键部署环境"
    echo "2. 容器管理（部署/备份/恢复/删除）"
    echo "3. Crontab 任务管理"
    echo "4. 重装系统"
    echo "5. PGP管理"
    echo "0. 退出"
    echo "============================================"
    read -p "请选择操作: " choice
    case "$choice" in
        1) source "$(dirname "$0")/modules/setup_env.sh" ;;
        2) source "$(dirname "$0")/container_manage/main.sh" ;;
        3) source "$(dirname "$0")/modules/crontab_manage.sh" ;;
        4) source "$(dirname "$0")/modules/reinstall_os.sh" ;;
        5) source "$(dirname "$0")/service/pgp_manager.sh" ;;
        0) exit 0 ;;
        *) echo "无效选择，请重新输入！" && sleep 1 ;;
    esac
}

while true; do
    main_menu
    echo "按任意键返回主菜单..."
    read -n 1
done
