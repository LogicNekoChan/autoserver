#!/bin/bash
# 自动进入项目根目录，保证所有相对路径正确
BASE_DIR="/root/autoserver"
cd "$BASE_DIR" || { echo "无法进入 $BASE_DIR ，脚本终止！"; exit 1; }

# 如果 linuxbash 命令不存在，就自动创建软链接
if ! command -v linuxbash &>/dev/null; then
    echo "首次运行，正在注册 linuxbash 命令..."
    sudo ln -s "$(realpath "$0")" /usr/local/bin/linuxbash
    echo "注册完成！现在你可以在任何地方输入 linuxbash 来运行本脚本。"
    sleep 2
fi

source "utils/common.sh"      # 现在路径一定正确

function main_menu() {
    clear
    echo "========== AutoServer 自动化部署 =========="
    echo "1. 一键部署环境"
    echo "2. 容器管理（部署/备份/恢复/删除）"
    echo "3. Crontab 任务管理"
    echo "4. 重装系统"
    echo "5. PGP管理"
    echo "6. 7zip管理"
    echo "7. 卸载关联（取消 linuxbash 命令）"
    echo "0. 退出"
    echo "============================================"
    read -p "请选择操作: " choice
    case "$choice" in
        1) source "modules/setup_env.sh" ;;
        2) source "container_manage/main.sh" ;;
        3) source "modules/crontab_manage.sh" ;;
        4) source "modules/reinstall_os.sh" ;;
        5) source "modules/pgp_manager.sh" ;;
        6) source "modules/7zip_manager.sh" ;;
        7) uninstall_linuxbash ;;
        0) exit 0 ;;
        *) echo "无效选择，请重新输入！" && sleep 1 ;;
    esac
}

function uninstall_linuxbash() {
    if [[ -L /usr/local/bin/linuxbash ]]; then
        sudo rm /usr/local/bin/linuxbash
        echo "已删除 linuxbash 命令关联。"
    else
        echo "linuxbash 命令未激活，无需卸载。"
    fi
    echo "按任意键返回主菜单..."
    read -n 1
}

while true; do
    main_menu
    echo "按任意键返回主菜单..."
    read -n 1
done
